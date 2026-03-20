//
//  ContentImageBuilder.swift
//  Quran
//
//  Created by Afifi, Mohamed on 9/16/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import AnnotationsService
import AppDependencies
import Foundation
import ImageService
import QuranKit
import QuranPagesFeature
import ReadingService
import SwiftUI
import UIKit
import Utilities
import VLogging

@MainActor
public struct ContentImageBuilder {
    // MARK: Lifecycle

    public init(container: AppDependencies, highlightsService: QuranHighlightsService) {
        self.container = container
        self.highlightsService = highlightsService
    }

    // MARK: Public

    public func build(at page: Page) -> some View {
        let reading = ReadingPreferences.shared.reading
        let imageService = Self.buildImageDataService(reading: reading, container: container)

        let viewModel = ContentImageViewModel(
            reading: reading,
            page: page,
            imageDataService: imageService,
            highlightsService: highlightsService
        )
        return ContentImageView(viewModel: viewModel)
    }

    // MARK: Internal

    static func buildImageDataService(reading: Reading, container: AppDependencies) -> ImageDataService {
        let readingForImageData = Self.readingForImageData(reading, container: container)
        let readingDirectory = Self.readingDirectory(readingForImageData, container: container)
        return ImageDataService(
            ayahInfoDatabase: readingForImageData.ayahInfoDatabase(in: readingDirectory),
            imagesURL: readingForImageData.images(in: readingDirectory)
        )
    }

    // MARK: Private

    private let container: AppDependencies
    private let highlightsService: QuranHighlightsService

    private static func readingDirectory(_ reading: Reading, container: AppDependencies) -> URL {
        let remoteResource = container.remoteResources?.resource(for: reading)
        let remotePath = remoteResource?.downloadDestination.url
        if let remotePath, FileManager.default.fileExists(atPath: remotePath.path) {
            logger.info("Images: Use remote resources for reading \(reading)")
            return remotePath
        }

        if let bundlePath = Bundle.main.url(forResource: reading.localPath, withExtension: nil) {
            logger.info("Images: Use bundled resources for reading \(reading)")
            return bundlePath
        }

        // Avoid crashing if neither bundled nor remote resources are available.
        logger.error("Images: Missing resources for reading \(reading). Falling back to app bundle root.")
        return Bundle.main.bundleURL
    }

    private static func readingForImageData(_ reading: Reading, container: AppDependencies) -> Reading {
        if hasImageData(for: reading, container: container) {
            return reading
        }

        let fallback: Reading = .hafs_1405
        if reading != fallback, hasImageData(for: fallback, container: container) {
            logger.error("Images: Missing image data for reading \(reading). Falling back to \(fallback).")
            return fallback
        }

        logger.error("Images: Missing image data for reading \(reading) and no fallback was found.")
        return reading
    }

    private static func hasImageData(for reading: Reading, container: AppDependencies) -> Bool {
        let directory = readingDirectory(reading, container: container)
        let ayahInfoDatabase = reading.ayahInfoDatabase(in: directory)
        let images = reading.images(in: directory)
        return FileManager.default.fileExists(atPath: ayahInfoDatabase.path)
            && FileManager.default.fileExists(atPath: images.path)
    }
}

private extension Reading {
    func ayahInfoDatabase(in directory: URL) -> URL {
        switch self {
        case .hafs_1405:
            return directory.appendingPathComponent("images_1920/databases/ayahinfo_1920.db")
        case .hafs_1421:
            return directory.appendingPathComponent("images_1120/databases/ayahinfo_1120.db")
        case .hafs_1440:
            return directory.appendingPathComponent("images_1352/databases/ayahinfo_1352.db")
        case .naskh:
            return directory.appendingPathComponent("images_1342/databases/ayahinfo_1342.db")
        case .tajweed:
            return directory.appendingPathComponent("images_1280/databases/ayahinfo_1280.db")
        }
    }

    func images(in directory: URL) -> URL {
        switch self {
        case .hafs_1405:
            return directory.appendingPathComponent("images_1920/width_1920")
        case .hafs_1421:
            return directory.appendingPathComponent("images_1120/width_1120")
        case .hafs_1440:
            return directory.appendingPathComponent("images_1352/width_1352")
        case .naskh:
            return directory.appendingPathComponent("images_1342/width_1342")
        case .tajweed:
            return directory.appendingPathComponent("images_1280/width_1280")
        }
    }

    // TODO: Add cropInsets back
    var cropInsets: UIEdgeInsets {
        switch self {
        case .hafs_1405:
            return .zero // UIEdgeInsets(top: 10, left: 34, bottom: 40, right: 24)
        case .hafs_1421:
            return .zero
        case .hafs_1440:
            return .zero
        case .naskh:
            return .zero
        case .tajweed:
            return .zero
        }
    }
}
