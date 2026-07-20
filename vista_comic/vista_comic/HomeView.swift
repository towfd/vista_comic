//
//  ContentView.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/3.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            FavouriteView(comics: SampleData.comics)
                .navigationDestination(for: Comic.self) { comic in
                    ChapterPageView(comic: comic)
                }
                .navigationDestination(for: ReaderRoute.self) { route in
                    ComicView(comic: route.comic, chapter: route.chapter)
                }
        }
    }
}

#Preview {
    HomeView()
}
