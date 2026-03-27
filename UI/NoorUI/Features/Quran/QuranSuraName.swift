//
//  QuranSuraName.swift
//
//
//  Created by Mohamed Afifi on 2024-02-10.
//

import NoorFont
import QuranText
import SwiftUI

public struct QuranSuraName: View {
    @ScaledMetric var bottomPadding = 5
    @ScaledMetric var topPadding = 10

    let suraName: String
    let besmAllah: String
    let besmAllahFontSize: FontSize
    let arabicFontName: FontName

    public init(suraName: String, besmAllah: String, besmAllahFontSize: FontSize, arabicFontName: FontName = .quran) {
        self.suraName = suraName
        self.besmAllah = besmAllah
        self.besmAllahFontSize = besmAllahFontSize
        self.arabicFontName = arabicFontName
    }

    public var body: some View {
        VStack {
            NoorImage.suraHeader.image.resizable()
                .aspectRatio(contentMode: .fit)
                .overlay {
                    Text(suraName)
                        .font(.title3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                }
            Text(besmAllah)
                .font(.quran(ofSize: besmAllahFontSize, fontName: arabicFontName))
                .dynamicTypeSize(besmAllahFontSize.dynamicTypeSize)
        }
        .padding(.bottom, bottomPadding)
        .padding(.top, topPadding)
        .readableInsetsPadding(.horizontal)
    }
}
