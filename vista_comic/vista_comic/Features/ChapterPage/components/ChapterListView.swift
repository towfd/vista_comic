//
//  comic_list.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/7.
//

import SwiftUI

struct ChapterListView: View {
    let comic: Comic
    let chapter: Chapter

    @Environment(\.chapterDownloads) private var downloads

    private var chapterID: DownloadedChapterID {
        DownloadedChapterID(comicID: comic.id, chapterID: chapter.id)
    }

    var body: some View{
        // The download control sits outside the link rather than inside it: a
        // button nested in a `NavigationLink` hands its taps to the link, so
        // cancelling a download would open the reader instead.
        HStack(spacing: 0){
            NavigationLink(value: ReaderRoute(comicID: comic.id, chapterID: chapter.id)){
                HStack(spacing: 17){
                    // The chapter's own first page, not one shared stock
                    // image: what a chapter looks like is the fastest way to
                    // recognise it, and a list where every row shows the same
                    // picture is telling the reader nothing.
                    CoverImage(url: chapter.coverURL)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    VStack(alignment: .leading, spacing: 10){
                        Text(chapter.title)
                            .font(AppFont.rowTitle)

                        HStack(spacing: 4){
                            if let icon = readStateIcon {
                                Image(systemName: icon)
                            }
                            Text(readStateLabel)
                        }
                        .font(AppFont.caption)
                        .foregroundStyle(readStateColor)
                    }

                    Spacer()

                    VStack(){
                        Text("#\(chapter.number)")
                            .font(AppFont.rowTitle)
                    }
                }
            }
            .foregroundStyle(.grayFont)

            ChapterDownloadButton(
                state: downloads.state(for: chapterID),
                start: { downloads.download(comic: comic, chapter: chapter) },
                cancel: { downloads.cancel(chapterID) }
            )
            .padding(.trailing, 2)
        }.frame(maxWidth: .infinity, maxHeight: 73, alignment: .center)
    }

    private var readStateLabel: String {
        switch chapter.readState {
        case .unread: return String(localized: "unread")
        case .reading: return String(localized: "reading")
        case .read: return String(localized: "read")
        }
    }

    private var readStateIcon: String? {
        switch chapter.readState {
        case .unread: return nil
        case .reading: return "book.fill"
        case .read: return "checkmark.circle.fill"
        }
    }

    private var readStateColor: Color {
        switch chapter.readState {
        case .reading: return Color(.primaryRed)
        case .unread, .read: return Color(.grayFont)
        }
    }
}

#Preview {
    NavigationStack {
        ChapterListView(comic: SampleData.comics[0], chapter: SampleData.comics[0].chapters[0])
            .padding()
    }
}
