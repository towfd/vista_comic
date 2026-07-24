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
                // Continue Reading always shows: the backend decides which chapter
                // it opens (`continueChapterId` — most-recent reading chapter, else
                // first unread, else first) and returns it on the `/comics` list.
                NavigationLink(
                    value: ReaderRoute(comicID: comic.id, chapterID: continueChapterID)
                ){
                    continueLabel
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

    /// The id Continue opens. The backend-provided `continueChapterId` when the
    /// card came from `/comics`; otherwise a best-effort fallback to the first
    /// chapter id (e.g. sample data / previews). An empty id is harmless: the
    /// reader resolves it to the comic's first chapter after loading the detail.
    private var continueChapterID: String {
        comic.continueChapterId ?? comic.chapters.first?.id ?? ""
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
