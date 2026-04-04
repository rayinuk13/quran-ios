//
//  ImageDataServiceTests.swift
//
//
//  Created by Mohamed Afifi on 2022-01-09.
//

import QuranGeometry
import QuranKit
import SnapshotTesting
import TestResources
import XCTest
@testable import ImageService

class ImageDataServiceTests: XCTestCase {
    // MARK: Internal

    var service: ImageDataService!
    let quran = Quran.hafsMadani1405

    @MainActor
    override func setUpWithError() throws {
        service = ImageDataService(
            ayahInfoDatabase: TestResources.resourceURL("hafs_1405_ayahinfo.db"),
            imagesURL: TestResources.testDataURL.appendingPathComponent("images")
        )
    }

    func testPageMarkers() async throws {
        let quran = Reading.hafs_1421.quran
        service = ImageDataService(
            ayahInfoDatabase: TestResources.resourceURL("hafs_1421_ayahinfo_1120.db"),
            imagesURL: URL(string: "invalid")!
        )

        var surasHeaders = 0
        for page in quran.pages {
            let ayahNumbers = try await service.ayahNumbers(page)
            let pageSuraHeaders = try await service.suraHeaders(page)
            XCTAssertEqual(ayahNumbers.count, page.verses.count, "Page \(page.pageNumber)")
            surasHeaders += pageSuraHeaders.count
        }
        XCTAssertEqual(surasHeaders, quran.suras.count)
    }

    func testWordFrameCollection() async throws {
        let page = quran.pages[0]
        let imagePage = try await service.imageForPage(page)
        let wordFrames = imagePage.wordFrames

        XCTAssertEqual(wordFrames.lines[0].frames, wordFrames.wordFramesForVerse(page.firstVerse))
        XCTAssertEqual(
            CGRect(x: 705, y: 254.0, width: 46.0, height: 95.0),
            wordFrames.wordFrameForWord(Word(verse: page.firstVerse, wordNumber: 2))?.rect
        )
        XCTAssertEqual([], wordFrames.wordFramesForVerse(quran.lastVerse))

        let verticalScaling = WordFrameScale.scaling(imageSize: imagePage.pageSize, into: CGSize(width: 359, height: 668))
        let horizontalScaling = WordFrameScale.scaling(imageSize: imagePage.pageSize, into: CGSize(width: 708, height: 1170.923076923077))

        XCTAssertEqual(
            Word(verse: AyahNumber(quran: quran, sura: 1, ayah: 7)!, wordNumber: 3),
            wordFrames.wordAtLocation(CGPoint(x: 103, y: 235), imageScale: verticalScaling)
        )

        XCTAssertEqual(
            Word(verse: AyahNumber(quran: quran, sura: 1, ayah: 3)!, wordNumber: 1),
            wordFrames.wordAtLocation(CGPoint(x: 540, y: 290), imageScale: horizontalScaling)
        )

        XCTAssertNil(wordFrames.wordAtLocation(.zero, imageScale: verticalScaling))
    }

    @MainActor
    func testGettingImageAtPage1() async throws {
        let page = quran.pages[0]
        let image = try await service.imageForPage(page)
        XCTAssertEqual(image.startAyah, page.firstVerse)
        try verifyImagePage(image)
    }

    @MainActor
    func testGettingImageAtPage3() async throws {
        let page = quran.pages[2]
        let image = try await service.imageForPage(page)
        XCTAssertEqual(image.startAyah, page.firstVerse)
        try verifyImagePage(image)
    }

    @MainActor
    func testGettingImageAtPage604() async throws {
        let page = quran.pages.last!
        let image = try await service.imageForPage(page)
        XCTAssertEqual(image.startAyah, page.firstVerse)
        try verifyImagePage(image)
    }

    // MARK: - Line-based page tests

    func testLineBasedPage() async throws {
        let (tempImagesURL, tempDir) = try makeLineBasedImagesDir(pageNumber: 2, lineCount: 3, includeSideline: false)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lineService = ImageDataService(
            ayahInfoDatabase: TestResources.resourceURL("hafs_1405_ayahinfo.db"),
            imagesURL: tempImagesURL
        )
        let page = quran.pages[1] // page 2
        let imagePage = try await lineService.imageForPage(page)

        // Should return line-based content, not a full-page image.
        guard case .lineBased(let lines) = imagePage.content else {
            return XCTFail("Expected lineBased content, got \(imagePage.content)")
        }
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines.map(\.number), [1, 2, 3], "Lines must be in ascending order")
        XCTAssertTrue(lines.allSatisfy { $0.sidelineImage == nil })
        XCTAssertEqual(imagePage.startAyah, page.firstVerse)

        // No stitched file must be written to disk.
        let generatedDir = tempImagesURL.appendingPathComponent("generated")
        XCTAssertFalse(FileManager.default.fileExists(atPath: generatedDir.path), "No generated directory should be created")
    }

    func testLineBasedPageWithSideline() async throws {
        let (tempImagesURL, tempDir) = try makeLineBasedImagesDir(pageNumber: 2, lineCount: 2, includeSideline: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lineService = ImageDataService(
            ayahInfoDatabase: TestResources.resourceURL("hafs_1405_ayahinfo.db"),
            imagesURL: tempImagesURL
        )
        let page = quran.pages[1] // page 2
        let imagePage = try await lineService.imageForPage(page)

        guard case .lineBased(let lines) = imagePage.content else {
            return XCTFail("Expected lineBased content, got \(imagePage.content)")
        }
        XCTAssertEqual(lines.count, 2)
        XCTAssertNotNil(lines[0].sidelineImage, "Line 1 should have a sideline image")
        XCTAssertNil(lines[1].sidelineImage, "Line 2 should not have a sideline image")
    }

    func testLineBasedPageSizeComputedFromLines() async throws {
        let (tempImagesURL, tempDir) = try makeLineBasedImagesDir(pageNumber: 2, lineCount: 3, includeSideline: false)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lineService = ImageDataService(
            ayahInfoDatabase: TestResources.resourceURL("hafs_1405_ayahinfo.db"),
            imagesURL: tempImagesURL
        )
        let page = quran.pages[1]
        let imagePage = try await lineService.imageForPage(page)

        // Each test line image is 100×20; total virtual page = 100×60.
        XCTAssertEqual(imagePage.pageSize, CGSize(width: 100, height: 60))
        XCTAssertNil(imagePage.image)
        XCTAssertEqual(imagePage.lines.count, 3)
    }

    func testMissingAssets() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let emptyService = ImageDataService(
            ayahInfoDatabase: TestResources.resourceURL("hafs_1405_ayahinfo.db"),
            imagesURL: tempDir
        )
        let page = quran.pages[0]
        do {
            _ = try await emptyService.imageForPage(page)
            XCTFail("Expected an error for missing image assets")
        } catch {
            // Expected
            XCTAssertTrue(error.localizedDescription.contains("No image found"), "Error: \(error)")
        }
    }

    func testFullPageImageTakesPrecedenceOverLineDirectory() async throws {
        // Create a temp dir that has BOTH a full-page PNG and a line directory for the same page.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pageNumber = 2
        // Write the full-page PNG.
        let pageImage = makeSolidColorImage(size: CGSize(width: 100, height: 200), color: .blue)
        let pageImageData = try XCTUnwrap(pageImage.pngData())
        let pageImageURL = tempDir.appendingPathComponent("page002.png")
        try pageImageData.write(to: pageImageURL)

        // Also write a line directory.
        let lineDir = tempDir.appendingPathComponent("\(pageNumber)", isDirectory: true)
        try FileManager.default.createDirectory(at: lineDir, withIntermediateDirectories: true)
        let lineImage = makeSolidColorImage(size: CGSize(width: 100, height: 20), color: .red)
        let lineData = try XCTUnwrap(lineImage.pngData())
        try lineData.write(to: lineDir.appendingPathComponent("1.png"))

        let lineService = ImageDataService(
            ayahInfoDatabase: TestResources.resourceURL("hafs_1405_ayahinfo.db"),
            imagesURL: tempDir
        )
        let page = quran.pages[1]
        let imagePage = try await lineService.imageForPage(page)

        // Full-page PNG must win.
        guard case .fullPage = imagePage.content else {
            return XCTFail("Expected fullPage content, got \(imagePage.content)")
        }
    }

    // MARK: Private

    @MainActor
    private func verifyImagePage(_ imagePage: ImagePage, testName: String = #function) throws {
        // assert the image (only valid for full-page assets used in the default test setup)
        let image = try XCTUnwrap(imagePage.image)
        assertSnapshot(matching: image, as: .image, testName: testName)

        // assert the word frames values
        let frames = imagePage.wordFrames.lines.flatMap(\.frames).sorted { $0.word < $1.word }
        assertSnapshot(matching: frames, as: .json, testName: testName)

        if ProcessInfo.processInfo.environment["LocalSnapshots"] != nil {
            print("[Test] Asserting LocalSnapshots")
            // assert the drawn word frames
            let highlightedImage = try drawFrames(image, frames: imagePage.wordFrames, strokeWords: false)
            assertSnapshot(matching: highlightedImage, as: .image, testName: testName)
        }
    }

    private func drawFrames(_ image: UIImage, frames: WordFrameCollection, strokeWords: Bool) throws -> UIImage {
        UIGraphicsBeginImageContextWithOptions(image.size, false, 0)
        let fillColors: [UIColor] = [
            .systemRed,
            .systemBlue,
            .systemGreen,
            .systemOrange,
            .systemPurple,
            .systemTeal,
        ]
        let strokeColor = UIColor.gray
        let verses = Set(frames.lines.flatMap(\.frames).map(\.word.verse)).sorted()
        for (offset, verse) in verses.enumerated() {
            let frames = try XCTUnwrap(frames.wordFramesForVerse(verse))
            let color = fillColors[offset % fillColors.count]
            color.setFill()
            strokeColor.setStroke()
            for frame in frames {
                let path = UIBezierPath(rect: frame.rect)
                path.fill()
                if strokeWords {
                    path.stroke()
                }
            }
        }
        image.draw(at: .zero)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return try XCTUnwrap(newImage)
    }

    /// Creates a temporary images directory containing a line-based page directory.
    /// Returns (imagesURL, rootTempDir) so callers can clean up.
    private func makeLineBasedImagesDir(
        pageNumber: Int,
        lineCount: Int,
        includeSideline: Bool
    ) throws -> (imagesURL: URL, rootTempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let pageDir = tempDir.appendingPathComponent("\(pageNumber)", isDirectory: true)
        try FileManager.default.createDirectory(at: pageDir, withIntermediateDirectories: true)

        for i in 1 ... lineCount {
            let lineImage = makeSolidColorImage(size: CGSize(width: 100, height: 20), color: .gray)
            let data = try XCTUnwrap(lineImage.pngData())
            try data.write(to: pageDir.appendingPathComponent("\(i).png"))
        }

        if includeSideline {
            let sidelineDir = pageDir.appendingPathComponent("sidelines", isDirectory: true)
            try FileManager.default.createDirectory(at: sidelineDir, withIntermediateDirectories: true)
            let sidelineImage = makeSolidColorImage(size: CGSize(width: 20, height: 10), color: .darkGray)
            let data = try XCTUnwrap(sidelineImage.pngData())
            // Only add a sideline for line 1.
            try data.write(to: sidelineDir.appendingPathComponent("1.png"))
        }

        return (tempDir, tempDir)
    }

    private func makeSolidColorImage(size: CGSize, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
