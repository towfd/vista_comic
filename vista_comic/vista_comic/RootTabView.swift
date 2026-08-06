//
//  RootTabView.swift
//  vista_comic
//
//  The app's root navigation shell (tab-bar-navigation M4 kickoff): hosts the
//  existing library/reader flow (書庫) alongside a second tab. `HomeView` is
//  unchanged — it simply becomes one tab's content instead of the app's root.
//
//  `comprehension-response-ux` ticket 19 puts 歷史紀錄 in the slot 單字本 held.
//  It is a replacement rather than an addition: every translate now records
//  itself automatically, so the thing worth keeping a tab for is what the
//  reader actually produced while reading — not the short list of items they
//  remembered to save. Ticket 21 then deleted 單字本 outright, so 歷史紀錄 is now
//  the only thing this slot has ever held as far as the code is concerned.
//

import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
    }
}

#Preview {
    RootTabView()
}
