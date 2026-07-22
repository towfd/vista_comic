//
//  comic_list.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/7.
//

import SwiftUI

struct ComicListView: View {
    let comic: Comic

    var body: some View{
        VStack{
            HStack(spacing: 17){
                CoverImage(url: comic.coverURL)
                    .frame(width: 76, height: 64, alignment: .center)
                VStack(alignment: .leading){
                    HStack{
                        Text(comic.title)
                            .font(AppFont.rowTitle)
                        Spacer()
                        Text("#\(comic.chapterCount)")
                            .font(AppFont.rowTitle)
                            .foregroundStyle(.grayFont)
                    }.padding(.bottom)

                    Text(lastReadText)
                        .font(AppFont.caption)
                        .foregroundStyle(.grayFont)
                }
            }

            HStack(spacing: 30){
                // Continue Reading opens the in-progress chapter, else the first
                // unread chapter, else the first chapter. Hidden entirely when no
                // chapter is known (e.g. the live `/comics` list omits chapters),
                // so the card never shows a permanently disabled CTA.
                if let continueChapter {
                    NavigationLink(value: ReaderRoute(comic: comic, chapter: continueChapter)){
                        continueLabel
                    }
                }

                NavigationLink(value: comic){
                    Text("chapter(\(comic.chapterCount))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.primaryRed)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: 147, alignment: .center)
    }

    private var lastReadText: String {
        guard let lastReadAt = comic.lastReadAt else {
            return String(localized: "not started yet")
        }
        let when = lastReadAt.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "\(when) · last read")
    }

    /// The chapter Continue Reading should open: the in-progress chapter,
    /// else the first unread chapter, else the first chapter.
    private var continueChapter: Chapter? {
        comic.chapters.first { $0.readState == .reading }
            ?? comic.chapters.first { $0.readState == .unread }
            ?? comic.chapters.first
    }

    private var continueLabel: some View {
        Text("continue")
            .font(.system(size: 12, weight: .bold))
            .padding()
            .frame(maxWidth: .infinity)
            // Adaptive so the outlined button stays readable in dark mode
            // instead of rendering as a hardcoded white block.
            .background(Color(.systemBackground))
            .foregroundStyle(.primaryRed)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.primaryRed, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    NavigationStack {
        ComicListView(comic: SampleData.comics[0])
            .padding()
    }
}
