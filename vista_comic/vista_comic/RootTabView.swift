//
//  RootTabView.swift
//  vista_comic
//
//  The app's root navigation shell (tab-bar-navigation M4 kickoff): hosts the
//  existing library/reader flow (書庫) alongside a placeholder learning-record
//  tab (單字本) that a later feature will populate. `HomeView` is unchanged —
//  it simply becomes one tab's content instead of the app's root.
//

import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            LearningRecordView()
                .tabItem {
                    Label("Learning Record", systemImage: "text.book.closed")
                }
        }
    }
}

#Preview {
    RootTabView()
}
