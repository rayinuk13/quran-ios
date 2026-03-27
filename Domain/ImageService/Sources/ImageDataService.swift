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
        let imageURL = try imageURLForPage(page)
        guard let image = UIImage(contentsOfFile: imageURL.path) else {
            throw ImageDataServiceError.missingImage(page: page, path: imageURL.path)
        }

        // preload the image
        let unloadedImage: UIImage = image
        let preloadedImage = preloadImage(unloadedImage)

        let frames: WordFrameCollection
        do {
            frames = try await wordFrames(page)
        } catch {
            logger.error("Images: Failed loading word frames for page \(page). Showing image without word frames. Error=\(error)")
            frames = WordFrameCollection(lines: [])
        }

        return ImagePage(image: preloadedImage, wordFrames: frames, startAyah: page.firstVerse)
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

    private func imageURLForPage(_ page: Page) throws -> URL {
        let pageImageURL = imagesURL.appendingPathComponent("page\(page.pageNumber.as3DigitString()).png")
        if FileManager.default.fileExists(atPath: pageImageURL.path) {
            return pageImageURL
        }

        if let stitchedPageURL = try stitchedImageURLForLineBasedPageIfNeeded(page) {
            return stitchedPageURL
        }

        logFiles(directory: imagesURL) // <reading>/images/width/
        logFiles(directory: imagesURL.deletingLastPathComponent()) // <reading>/images/
        logFiles(directory: imagesURL.deletingLastPathComponent().deletingLastPathComponent()) // <reading>/
        throw ImageDataServiceError.missingImage(page: page, path: pageImageURL.path)
    }

    private func stitchedImageURLForLineBasedPageIfNeeded(_ page: Page) throws -> URL? {
        let fileManager = FileManager.default
        let pageDirectory = imagesURL.appendingPathComponent("\(page.pageNumber)", isDirectory: true)
        guard fileManager.fileExists(atPath: pageDirectory.path) else {
            return nil
        }

        let generatedDirectory = imagesURL.appendingPathComponent("generated", isDirectory: true)
        let generatedPageURL = generatedDirectory.appendingPathComponent("page\(page.pageNumber.as3DigitString()).png")
        if fileManager.fileExists(atPath: generatedPageURL.path) {
            return generatedPageURL
        }

        let lineImages = try loadLineImages(from: pageDirectory)
        guard !lineImages.isEmpty else {
            return nil
        }

        let width = lineImages.map { $0.image.size.width }.max() ?? 0
        let height = lineImages.reduce(CGFloat(0)) { $0 + $1.image.size.height }

        var rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        rendererFormat.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: rendererFormat
        )
        let stitchedImage = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))

            var y: CGFloat = 0
            for line in lineImages {
                let lineFrame = CGRect(x: 0, y: y, width: line.image.size.width, height: line.image.size.height)
                line.image.draw(in: lineFrame)

                let sideLinePath = pageDirectory
                    .appendingPathComponent("sidelines", isDirectory: true)
                    .appendingPathComponent("\(line.number).png")
                if let sideLineImage = UIImage(contentsOfFile: sideLinePath.path) {
                    let sideLineY = y + (line.image.size.height - sideLineImage.size.height) / 2
                    let sideLineFrame = CGRect(
                        x: 0,
                        y: sideLineY,
                        width: sideLineImage.size.width,
                        height: sideLineImage.size.height
                    )
                    sideLineImage.draw(in: sideLineFrame)
                }

                y += line.image.size.height
            }
        }

        try fileManager.createDirectory(at: generatedDirectory, withIntermediateDirectories: true)
        if let data = stitchedImage.pngData() {
            try data.write(to: generatedPageURL, options: Data.WritingOptions.atomic)
            logger.info("Images: Generated stitched page image for page \(page.pageNumber) at \(generatedPageURL.path)")
            return generatedPageURL
        }

        return nil
    }

    private func loadLineImages(from pageDirectory: URL) throws -> [(number: Int, image: UIImage)] {
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
            return (line.number, image)
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
