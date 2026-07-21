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

    var body: some View{
        VStack{
            NavigationLink(value: ReaderRoute(comic: comic, chapter: chapter)){
                HStack(spacing: 17){
                    Image("Landscape_4")
                        .resizable()
                        .frame(width: 60, height: 60, alignment: .center)

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
                    }.padding(.trailing, 10)
                }
            }
            .foregroundStyle(.grayFont)
        }.frame(maxWidth: .infinity, maxHeight: 73, alignment: .center)
    }

    private var readStateLabel: String {
        switch chapter.readState {
        case .unread: return "unread"
        case .reading: return "reading"
        case .read: return "read"
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
