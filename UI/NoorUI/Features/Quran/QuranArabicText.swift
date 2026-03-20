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

public struct QuranArabicText: View {
    @ScaledMetric var bottomPadding = 5
    @ScaledMetric var topPadding = 10
    @ScaledMetric var cornerRadius = 6

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

            HStack(alignment: .center, spacing: 4) {
                AyahEndMark(number: arabicVerseNumber, fontSize: fontSize, arabicFontName: arabicFontName)

                Text(text)
                    .font(.quran(ofSize: fontSize, fontName: arabicFontName))
                    .dynamicTypeSize(fontSize.dynamicTypeSize)
            }
            .textAlignment(follows: .rightToLeft)
        }
        .padding(.bottom, bottomPadding)
        .padding(.top, topPadding)
        .readableInsetsPadding(.horizontal)
    }

    private var arabicVerseNumber: String {
        NumberFormatter.arabicNumberFormatter.format(verse.ayah)
    }
}

private struct AyahEndMark: View {
    let number: String
    let fontSize: FontSize
    let arabicFontName: FontName

    var body: some View {
        ZStack {
            Text("۝")
                .font(.custom(arabicFontName, size: markerFontSize))
            Text(number)
                .font(.custom(arabicFontName, size: numberFontSize))
                .offset(y: markerFontSize * 0.02)
        }
        .frame(minWidth: markerFontSize * 0.82)
        .fixedSize()
    }

    private var markerFontSize: CGFloat {
        fontSize.fontSize(forMediumSize: 22)
    }

    private var numberFontSize: CGFloat {
        fontSize.fontSize(forMediumSize: 11)
    }
}
