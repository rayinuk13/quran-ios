import QuranKit

public struct CarPlaySuraNavigator {
    public init(quran: Quran) {
        self.quran = quran
    }

    public func next(after sura: Sura?) -> Sura? {
        guard let sura else {
            return quran.suras.first
        }
        return sura.next
    }

    public func previous(before sura: Sura?) -> Sura? {
        guard let sura else {
            return quran.suras.first
        }
        return sura.previous
    }

    private let quran: Quran
}
