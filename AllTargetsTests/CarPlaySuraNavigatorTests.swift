import AudioBannerFeature
import QuranKit
import XCTest

final class CarPlaySuraNavigatorTests: XCTestCase {
    func testNext_afterNil_returnsFirstSura() {
        let navigator = CarPlaySuraNavigator(quran: .hafsMadani1440)

        let next = navigator.next(after: nil)

        XCTAssertEqual(next, Quran.hafsMadani1440.suras.first)
    }

    func testNext_afterLastSura_returnsNil() {
        let quran = Quran.hafsMadani1440
        let navigator = CarPlaySuraNavigator(quran: quran)

        let next = navigator.next(after: quran.suras.last)

        XCTAssertNil(next)
    }

    func testPrevious_beforeNil_returnsFirstSura() {
        let navigator = CarPlaySuraNavigator(quran: .hafsMadani1440)

        let previous = navigator.previous(before: nil)

        XCTAssertEqual(previous, Quran.hafsMadani1440.suras.first)
    }

    func testPrevious_beforeFirstSura_returnsNil() {
        let quran = Quran.hafsMadani1440
        let navigator = CarPlaySuraNavigator(quran: quran)

        let previous = navigator.previous(before: quran.suras.first)

        XCTAssertNil(previous)
    }
}
