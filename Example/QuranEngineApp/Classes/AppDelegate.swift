//
//  AppDelegate.swift
//  QuranEngineApp
//
//  Created by Mohamed Afifi on 2023-06-24.
//

import AppStructureFeature
import AudioBannerFeature
import CarPlay
import Logging
import MediaPlayer
import NoorFont
import NoorUI
import QuranAudio
import QuranAudioKit
import QuranKit
import QuranTextKit
import ReadingService
import ReciterService
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    // MARK: Internal

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        print("Documents directory: ", FileManager.documentsURL)

        FontName.registerFonts()
        LoggingSystem.bootstrap(StreamLogHandler.standardError)

        Task {
            // Eagerly load download manager to handle any background downloads.
            await container.downloadManager.start()

            // Begin fetching resources immediately after download manager is initialized.
            await container.readingResources.startLoadingResources()
        }

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configurationName = switch connectingSceneSession.role {
        case .carTemplateApplication: "CarPlay Configuration"
        default: "Default Configuration"
        }
        return UISceneConfiguration(name: configurationName, sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        let downloadManager = container.downloadManager
        downloadManager.setBackgroundSessionCompletion(completionHandler)
    }

    // MARK: Private

    private let container = Container.shared
}

@available(iOS 14.0, *)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private let controller = CarPlayPlaybackController.shared

    func templateApplicationScene(
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

    func templateApplicationScene(
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
    private let logger = Logger(label: "QuranEngineApp.CarPlayPlaybackController")
    private let audioPlayer = QuranAudioPlayer()
    private let downloader = QuranAudioDownloader(
        baseURL: Container.shared.filesAppHost,
        downloader: Container.shared.downloadManager
    )
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
        guard let reciter = selectedReciter else {
            return
        }
        selectedSura = sura
        playTask?.cancel()
        playTask = Task {
            do {
                if ! await downloader.downloaded(reciter: reciter, from: sura.firstVerse, to: sura.lastVerse) {
                    let download = try await downloader.download(from: sura.firstVerse, to: sura.lastVerse, reciter: reciter)
                    for try await _ in download.progress { }
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
