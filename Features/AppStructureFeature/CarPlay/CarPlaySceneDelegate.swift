import AppDependencies
import AudioBannerFeature
import CarPlay
import Logging
import MediaPlayer
import QuranAudio
import QuranAudioKit
import QuranKit
import QuranTextKit
import ReadingService
import ReciterService

@available(iOS 14.0, *)
public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private let controller = CarPlayPlaybackController.shared

    public func templateApplicationScene(
        _: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to _: CPWindow
    ) {
        self.interfaceController = interfaceController
        Task {
            await controller.loadIfNeeded()
            installRootTemplate()
        }
    }

    public func templateApplicationScene(
        _: CPTemplateApplicationScene,
        didDisconnectInterfaceController _: CPInterfaceController,
        from _: CPWindow
    ) {
        interfaceController = nil
    }

    private func installRootTemplate() {
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.tabTitle = "Now Playing"

        let chapters = CPListTemplate(title: "Chapters", sections: [CPListSection(items: controller.chapterItems())])
        chapters.tabTitle = "Chapters"

        let reciters = CPListTemplate(title: "Reciters", sections: [CPListSection(items: controller.reciterItems())])
        reciters.tabTitle = "Reciters"

        let root = CPTabBarTemplate(templates: [nowPlaying, chapters, reciters])
        interfaceController?.setRootTemplate(root, animated: false, completion: nil)
    }
}

public enum CarPlayRuntimeDependencies {
    public static var appDependencies: (any AppDependencies)?
}

@MainActor
private final class CarPlayPlaybackController {
    // MARK: Lifecycle

    private init() {
        setUpRemoteCommands()
    }

    // MARK: Internal

    static let shared = CarPlayPlaybackController()

    func loadIfNeeded() async {
        reciters = await reciterRetriever.getReciters()
        selectedReciter = reciters.first { $0.id == preferences.lastSelectedReciterId } ?? reciters.first
    }

    func chapterItems() -> [CPListItem] {
        quran.suras.map { sura in
            let detailText: String? = selectedSura == sura ? "Selected" : nil
            let item = CPListItem(text: sura.localizedName(withNumber: true), detailText: detailText)
            item.handler = { [weak self] _, completion in
                Task {
                    await self?.play(sura: sura)
                    completion()
                }
            }
            return item
        }
    }

    func reciterItems() -> [CPListItem] {
        reciters.map { reciter in
            let detailText: String? = selectedReciter == reciter ? "Selected" : nil
            let item = CPListItem(text: reciter.localizedName, detailText: detailText)
            item.handler = { [weak self] _, completion in
                self?.select(reciter: reciter)
                completion()
            }
            return item
        }
    }

    // MARK: Private

    private var selectedSura: Sura?
    private var playTask: Task<Void, Never>?

    private let quran = ReadingPreferences.shared.reading.quran
    private let reciterRetriever = ReciterDataRetriever()
    private let preferences = ReciterPreferences.shared
    private let navigator = CarPlaySuraNavigator(quran: ReadingPreferences.shared.reading.quran)
    private let logger = Logger(label: "AppStructureFeature.CarPlayPlaybackController")
    private let audioPlayer = QuranAudioPlayer()
    private var reciters: [Reciter] = []

    private var selectedReciter: Reciter? {
        didSet {
            guard let selectedReciter else {
                return
            }
            preferences.lastSelectedReciterId = selectedReciter.id
        }
    }

    private func select(reciter: Reciter) {
        selectedReciter = reciter
    }

    private func play(sura: Sura) async {
        guard
            let reciter = selectedReciter,
            let container = CarPlayRuntimeDependencies.appDependencies
        else {
            return
        }
        selectedSura = sura
        playTask?.cancel()
        playTask = Task {
            do {
                let downloader = QuranAudioDownloader(
                    baseURL: container.filesAppHost,
                    downloader: container.downloadManager
                )
                if !await downloader.downloaded(reciter: reciter, from: sura.firstVerse, to: sura.lastVerse) {
                    let download = try await downloader.download(from: sura.firstVerse, to: sura.lastVerse, reciter: reciter)
                    for try await _ in download.progress {}
                }
                try await audioPlayer.play(
                    reciter: reciter,
                    rate: AudioPreferences.shared.playbackRate,
                    from: sura.firstVerse,
                    to: sura.lastVerse,
                    verseRuns: .one,
                    listRuns: .one
                )
            } catch {
                logger.error("CarPlay playback failed: \(error)")
            }
        }
    }

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self, let sura = selectedSura else {
                return .commandFailed
            }
            Task {
                await self.play(sura: sura)
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.audioPlayer.pauseAudio()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, let next = navigator.next(after: selectedSura) else {
                return .noSuchContent
            }
            Task {
                await self.play(sura: next)
            }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, let previous = navigator.previous(before: selectedSura) else {
                return .noSuchContent
            }
            Task {
                await self.play(sura: previous)
            }
            return .success
        }
    }
}
