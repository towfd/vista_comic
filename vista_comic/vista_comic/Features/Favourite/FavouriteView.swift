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
                Text("Favourite")
                    .font(AppFont.title)

                ForEach(comics) { comic in
                    ComicListView(comic: comic)
                }
            }
            .padding()
        }
    }
}

#Preview {
    NavigationStack {
        FavouriteView(comics: SampleData.comics)
            .navigationDestination(for: Comic.self) { comic in
                ChapterPageView(comic: comic)
            }
    }
}
