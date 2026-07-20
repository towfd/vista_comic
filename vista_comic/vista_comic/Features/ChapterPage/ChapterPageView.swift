//
//  ChapterPageView.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/7.
//
import SwiftUI

struct ChapterPageView: View{
    let comic: Comic

    var body: some View{
        VStack{
            Image(comic.coverImageName)
                .resizable()
                .frame(width: 187, height: 187)
            Text(comic.title)
                .font(AppFont.title)

            ScrollView{
                ForEach(comic.chapters){ chapter in
                    ChapterListView(comic: comic, chapter: chapter)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChapterPageView(comic: SampleData.comics[0])
            .navigationDestination(for: ReaderRoute.self) { route in
                ComicView(comic: route.comic, chapter: route.chapter)
            }
    }
}
