//
//  Favourite.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/3.
//

import SwiftUI

struct FavouriteView: View {
    let comics: [Comic]

    var body: some View {
        ScrollView {
            VStack {
                Text("Library")
                    .font(AppFont.title)

                if comics.isEmpty {
                    emptyState
                } else {
                    ForEach(comics) { comic in
                        ComicListView(comic: comic)
                    }
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No comics yet",
            systemImage: "books.vertical",
            description: Text("Comics you add will appear here.")
        )
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}

#Preview("Populated") {
    NavigationStack {
        FavouriteView(comics: SampleData.comics)
            .navigationDestination(for: Comic.self) { comic in
                ChapterPageView(comic: comic)
            }
    }
}

#Preview("Empty") {
    NavigationStack {
        FavouriteView(comics: [])
    }
}
