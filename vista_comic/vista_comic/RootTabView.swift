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
//  remembered to save. `VocabularyView` stays in the tree, unreferenced, until
//  the removal ticket takes it out along with the rest of the M9 paths.
//

import SwiftUI

struct RootTabView: View {
    @Environment(\.comprehensionRepository) private var repository
    @Environment(\.scenePhase) private var scenePhase

    /// The badge lives here, not in `HistoryView` (ticket 22). A tab's content
    /// does not appear until the tab is selected, so a badge owned by 歷史紀錄
    /// could only ever learn an explanation had arrived at the moment the reader
    /// opened the tab it was meant to send them to. The shell is on screen the
    /// whole time, so it is the only thing that can speak while the reader is
    /// somewhere else.
    @State private var badge = UnreadExplanationBadge()

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
                .badge(badge.count)
        }
        .environment(\.unreadExplanationBadge, badge)
        // Catches whatever finished while the app was dead. The watch cannot:
        // it only knows about records enqueued in this run.
        .task { await badge.refresh(using: repository) }
        // Explanations land while the app is elsewhere — that is the whole
        // point of enqueueing them — so coming back is when the count is most
        // likely to be stale.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await badge.refresh(using: repository) }
            }
        }
    }
}

#Preview {
    RootTabView()
}
