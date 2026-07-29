//
//  RootTabView.swift
//  vista_comic
//
//  The app's root navigation shell (tab-bar-navigation M4 kickoff): hosts the
//  existing library/reader flow (書庫) alongside a placeholder vocabulary tab
//  (單字本) that the ocr-translation feature will populate. `HomeView` is
//  unchanged — it simply becomes one tab's content instead of the app's root.
//

import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            VocabularyView()
                .tabItem {
                    Label("Vocabulary", systemImage: "text.book.closed")
                }
        }
    }
}

#Preview {
    RootTabView()
}
