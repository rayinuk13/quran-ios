//
//  QuranArabicText.swift
//
//
//  Created by Mohamed Afifi on 2024-02-10.
//

import Localization
import NoorFont
import QuranKit
import QuranText
import SwiftUI
import UIKit

public struct QuranArabicText: View {
    @ScaledMetric var bottomPadding = 5
    @ScaledMetric var topPadding = 10
    @ScaledMetric var cornerRadius = 6
    @ScaledMetric var verseTrailingPadding = 12
    @ScaledMetric var verseLeadingPadding = 10

    let verse: AyahNumber
    let text: String
    let fontSize: FontSize
    let arabicFontName: FontName

    public init(verse: AyahNumber, text: String, fontSize: FontSize, arabicFontName: FontName = .quran) {
        self.verse = verse
        self.text = text
        self.fontSize = fontSize
        self.arabicFontName = arabicFontName
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(lFormat("translation.text.ayah-number", verse.sura.suraNumber, verse.ayah))
                .padding(8)
                .themedSecondaryForeground()
                .themedSecondaryBackground()
                .cornerRadius(cornerRadius)

            InlineQuranVerseText(
                text: text,
                verseNumber: arabicVerseNumber,
                fontSize: fontSize,
                arabicFontName: arabicFontName
            )
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, verseLeadingPadding)
            .padding(.trailing, verseTrailingPadding)
        }
        .padding(.bottom, bottomPadding)
        .padding(.top, topPadding)
        .readableInsetsPadding(.horizontal)
    }

    private var arabicVerseNumber: String {
        NumberFormatter.arabicNumberFormatter.format(verse.ayah)
    }
}

private struct InlineQuranVerseText: UIViewRepresentable {
    let text: String
    let verseNumber: String
    let fontSize: FontSize
    let arabicFontName: FontName

    func makeUIView(context: Context) -> AyahInlineLabel {
        let label = AyahInlineLabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .right
        label.semanticContentAttribute = .forceRightToLeft
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: AyahInlineLabel, context: Context) {
        label.attributedText = attributedText
    }

    private var attributedText: NSAttributedString {
        let verseFont = UIFont(arabicFontName, size: verseFontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.baseWritingDirection = .rightToLeft
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: verseFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: UIColor.label,
        ]

        let attributed = NSMutableAttributedString(string: text, attributes: attributes)
        attributed.append(NSAttributedString(string: " ", attributes: attributes))
        attributed.append(NSAttributedString(attachment: ayahMarkerAttachment))
        return attributed
    }

    private var ayahMarkerAttachment: NSTextAttachment {
        let attachment = NSTextAttachment()
        attachment.image = renderedAyahMarker()
        attachment.bounds = CGRect(
            x: 0,
            y: verseFontSize * -0.16,
            width: markerSize,
            height: markerSize
        )
        return attachment
    }

    private func renderedAyahMarker() -> UIImage {
        let baseImage = NoorImage.ayahEnd.uiImage
        let size = CGSize(width: markerSize, height: markerSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            baseImage.draw(in: CGRect(origin: .zero, size: size))

            let numberFont = UIFont(.arabic, size: numberFontSize)
            let numberAttributes: [NSAttributedString.Key: Any] = [
                .font: numberFont,
                .foregroundColor: UIColor.label,
                .strokeColor: UIColor.label,
                .strokeWidth: -0.9,
            ]
            let attributedNumber = NSAttributedString(string: verseNumber, attributes: numberAttributes)
            let measured = attributedNumber.boundingRect(
                with: CGSize(width: markerSize, height: markerSize),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            let rect = CGRect(
                x: ((markerSize - measured.width) / 2).rounded(.down),
                y: (((markerSize - measured.height) / 2) - markerSize * 0.03).rounded(.down),
                width: ceil(measured.width),
                height: ceil(measured.height)
            )
            attributedNumber.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
    }

    private var verseFontSize: CGFloat {
        fontSize.fontSize(forMediumSize: 25)
    }

    private var markerSize: CGFloat {
        fontSize.fontSize(forMediumSize: 22)
    }

    private var numberFontSize: CGFloat {
        fontSize.fontSize(forMediumSize: 12)
    }
}

private final class AyahInlineLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }

    override func layoutSubviews() {
        preferredMaxLayoutWidth = bounds.width
        super.layoutSubviews()
    }
}
