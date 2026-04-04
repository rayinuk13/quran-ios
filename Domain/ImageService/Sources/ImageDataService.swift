//
//  ImageDataService.swift
//
//
//  Created by Mohamed Afifi on 2021-12-15.
//

import QuranGeometry
import QuranKit
import UIKit
import VLogging
import WordFramePersistence
import WordFrameService

public struct ImageDataService {
    // MARK: Lifecycle

    public init(ayahInfoDatabase: URL, imagesURL: URL) {
        self.imagesURL = imagesURL
        persistence = GRDBWordFramePersistence(fileURL: ayahInfoDatabase)
    }

    // MARK: Public

    public func suraHeaders(_ page: Page) async throws -> [SuraHeaderLocation] {
        try await persistence.suraHeaders(page)
    }

    public func ayahNumbers(_ page: Page) async throws -> [AyahNumberLocation] {
        try await persistence.ayahNumbers(page)
    }

    public func imageForPage(_ page: Page) async throws -> ImagePage {
        let frames: WordFrameCollection
        do {
            frames = try await wordFrames(page)
        } catch {
            logger.error("Images: Failed loading word frames for page \(page). Showing image without word frames. Error=\(error)")
            frames = WordFrameCollection(lines: [])
        }

        // Prefer a single pre-rendered page image when available.
        let pageImageURL = imagesURL.appendingPathComponent("page\(page.pageNumber.as3DigitString()).png")
        if FileManager.default.fileExists(atPath: pageImageURL.path) {
            guard let image = UIImage(contentsOfFile: pageImageURL.path) else {
                throw ImageDataServiceError.missingImage(page: page, path: pageImageURL.path)
            }
            let preloadedImage = preloadImage(image)
            return ImagePage(image: preloadedImage, wordFrames: frames, startAyah: page.firstVerse)
        }

        // Fall back to a line-based page directory.
        let pageDirectory = imagesURL.appendingPathComponent("\(page.pageNumber)", isDirectory: true)
        if FileManager.default.fileExists(atPath: pageDirectory.path) {
            let lines = try loadLineImages(from: pageDirectory)
            if !lines.isEmpty {
                return ImagePage(lines: lines, wordFrames: frames, startAyah: page.firstVerse)
            }
        }

        logFiles(directory: imagesURL) // <reading>/images/width/
        logFiles(directory: imagesURL.deletingLastPathComponent()) // <reading>/images/
        logFiles(directory: imagesURL.deletingLastPathComponent().deletingLastPathComponent()) // <reading>/
        throw ImageDataServiceError.missingImage(page: page, path: pageImageURL.path)
    }

    // MARK: Internal

    func wordFrames(_ page: Page) async throws -> WordFrameCollection {
        let plainWordFrames = try await persistence.wordFrameCollectionForPage(page)
        let wordFrames = processor.processWordFrames(plainWordFrames)
        return wordFrames
    }

    // MARK: Private

    private let processor = WordFrameProcessor()
    private let persistence: WordFramePersistence
    private let imagesURL: URL

    private func logFiles(directory: URL) {
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let fileNames = files.map(\.lastPathComponent)
        logger.error("Images: Directory \(directory) contains files \(fileNames)")
    }

    private func loadLineImages(from pageDirectory: URL) throws -> [LineImage] {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: pageDirectory, includingPropertiesForKeys: nil)
        let lineFiles = files
            .filter { $0.pathExtension.lowercased() == "png" }
            .compactMap { file -> (number: Int, url: URL)? in
                guard let number = Int(file.deletingPathExtension().lastPathComponent) else {
                    return nil
                }
                return (number: number, url: file)
            }
            .sorted { $0.number < $1.number }

        return lineFiles.compactMap { line in
            guard let image = UIImage(contentsOfFile: line.url.path) else {
                return nil
            }
            let sidelinePath = pageDirectory
                .appendingPathComponent("sidelines", isDirectory: true)
                .appendingPathComponent("\(line.number).png")
            let sidelineImage = UIImage(contentsOfFile: sidelinePath.path)
            return LineImage(number: line.number, image: image, sidelineImage: sidelineImage)
        }
    }

    private func preloadImage(_ imageToPreload: UIImage, cropInsets: UIEdgeInsets = .zero) -> UIImage {
        let targetImage: CGImage?
        if let cgImage = imageToPreload.cgImage {
            targetImage = cgImage
        } else if let ciImage = imageToPreload.ciImage {
            let context = CIContext(options: nil)
            targetImage = context.createCGImage(ciImage, from: ciImage.extent)
        } else {
            targetImage = nil
        }
        guard var cgimg = targetImage else {
            return imageToPreload
        }

        let rect = CGRect(x: 0, y: 0, width: cgimg.width, height: cgimg.height)
        let croppedRect = rect.inset(by: cropInsets)
        let cropped = cgimg.cropping(to: croppedRect)
        cgimg = cropped ?? cgimg

        // make a bitmap context of a suitable size to draw to, forcing decode
        let width = cgimg.width
        let height = cgimg.height

        let colourSpace = CGColorSpaceCreateDeviceRGB()
        let imageContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colourSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )

        // draw the image to the context, release it
        imageContext?.draw(cgimg, in: CGRect(x: 0, y: 0, width: width, height: height))

        // now get an image ref from the context
        if let outputImage = imageContext?.makeImage() {
            let cachedImage = UIImage(cgImage: outputImage)
            return cachedImage
        }
        return imageToPreload
    }
}

private enum ImageDataServiceError: LocalizedError {
    case missingImage(page: Page, path: String)

    var errorDescription: String? {
        switch self {
        case let .missingImage(page, path):
            return "No image found for page '\(page)' at path '\(path)'."
        }
    }
}
