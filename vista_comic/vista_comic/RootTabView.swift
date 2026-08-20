//
//  RootTabView.swift
//  vista_comic
//
//  The app's root navigation shell (tab-bar-navigation M4 kickoff): hosts the
//  existing library/reader flow (書庫) alongside a second tab. `HomeView` is
//  unchanged — it simply becomes one tab's content instead of the app's root.
//
//  `comprehension-response-ux` ticket 19 puts 歷史紀錄 in the slot 單字本 held.
//  It is a replacement rather than an addition: the thing worth keeping a tab
//  for is the lines the reader asked for a deeper explanation of, which is a
//  record of what they studied rather than of everything they glanced at. Ticket 21 then deleted 單字本 outright, so 歷史紀錄 is now
//  the only thing this slot has ever held as far as the code is concerned.
//

import SwiftUI

struct RootTabView: View {
    @Environment(\.studyRepository) private var studyRepository
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }

            // 已下載 sits between them because it is the offline entry point
            // (`offline-download` ticket 05): when 書庫 cannot be reached, this
            // is the tab that is guaranteed to be about things that work.
            DownloadsView()
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }

            // 單字庫 takes the slot 歷史紀錄 held (vocabulary stage 2). That
            // tab was the second attempt at somewhere to look back at what had
            // been read, after 單字本, and went unused like the first. What
            // replaces it is not a third place to browse — it is where a bad
            // card gets fixed.
            StudyView()
                .tabItem {
                    Label("Vocabulary", systemImage: "text.book.closed")
                }
        }
        // Refreshes the deck snapshot the already-collected marker reads. Here
        // rather than in the reader, because the reader must not pay for a
        // network call every time a selection sheet opens — and the shell is on
        // screen the whole time.
        //
        // Best-effort and unobserved: `cards()` stores the snapshot as a side
        // effect of succeeding, and a failure just leaves the previous one in
        // place, which is exactly what it is for.
        .task { _ = try? await studyRepository.cards() }
        // Words are collected in the reader and can be queued offline, so
        // returning to the foreground is when the snapshot is most likely to be
        // behind what the reader has actually kept.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { _ = try? await studyRepository.cards() }
            }
        }
    }
}

#Preview {
    RootTabView()
}
