//
//  ImagePage.swift
//  Quran
//
//  Created by Afifi, Mohamed on 9/15/19.
//  Copyright © 2019 Quran.com. All rights reserved.
//

import QuranKit
import UIKit

/// A single line image, used when a Quran page is stored as a directory of per-line PNGs.
public struct LineImage: Equatable {
    public let number: Int
    public let image: UIImage
    /// Optional sideline decoration image for this line (e.g. verse-end markers).
    public let sidelineImage: UIImage?

    public init(number: Int, image: UIImage, sidelineImage: UIImage? = nil) {
        self.number = number
        self.image = image
        self.sidelineImage = sidelineImage
    }
}

public struct ImagePage: Equatable {
    // MARK: Lifecycle

    /// Initialise with a single full-page image (e.g. `pageXYZ.png`).
    public init(image: UIImage, wordFrames: WordFrameCollection, startAyah: AyahNumber) {
        content = .fullPage(image)
        self.wordFrames = wordFrames
        self.startAyah = startAyah
    }

    /// Initialise with ordered line images for line-based pages.
    public init(lines: [LineImage], wordFrames: WordFrameCollection, startAyah: AyahNumber) {
        content = .lineBased(lines)
        self.wordFrames = wordFrames
        self.startAyah = startAyah
    }

    // MARK: Public

    public enum Content: Equatable {
        /// A single pre-rendered page image (e.g. `pageXYZ.png`).
        case fullPage(UIImage)
        /// Ordered per-line images with optional sideline decorations.
        case lineBased([LineImage])
    }

    public let content: Content
    public let wordFrames: WordFrameCollection
    public let startAyah: AyahNumber

    /// The full-page image, or `nil` when the page is line-based.
    public var image: UIImage? {
        guard case .fullPage(let img) = content else { return nil }
        return img
    }

    /// The ordered line images, or an empty array when the page has a single full-page image.
    public var lines: [LineImage] {
        guard case .lineBased(let lines) = content else { return [] }
        return lines
    }

    /// The total virtual page size derived from the content.
    public var pageSize: CGSize {
        switch content {
        case .fullPage(let img):
            return img.size
        case .lineBased(let lines):
            let width = lines.map(\.image.size.width).max() ?? 0
            let height = lines.reduce(CGFloat(0)) { $0 + $1.image.size.height }
            return CGSize(width: width, height: height)
        }
    }
}
