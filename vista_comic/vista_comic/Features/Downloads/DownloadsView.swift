//
//  DownloadsView.swift
//  vista_comic
//
//  已下載 (`offline-download` ticket 05): one place that answers "what can I
//  read without a connection, and what is it costing me" — and lets the reader
//  act on the answer.
//
//  **It is also the offline entry point**, which is why it is a tab rather than
//  a screen pushed from somewhere. A reader on a plane gets a list that is
//  guaranteed to be about things that work, instead of browsing 書庫 and finding
//  out one chapter at a time.
//
//  **Deleting is what makes the cap's first-in-first-out tolerable.** Without
//  this screen the reader's only influence over what is kept is the order they
//  downloaded things in; with it, eviction is a default they can override.
//
//  Nothing here touches the network. The chapter records carry their own comic
//  and chapter titles precisely so that this screen needs no catalog — a list
//  that could only name things by id would be no use in the one situation it
//  exists for.
//

import SwiftUI

struct DownloadsView: View {
    @Environment(\.offlineChapterStore) private var store
    @Environment(\.chapterDownloads) private var downloads

    @State private var groups: [DownloadedComicGroup] = []
    /// Distinguishes "nothing is downloaded" from "we have not looked yet", so
    /// the empty state cannot flash on the way in.
    @State private var hasLoaded = false
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Downloads")
                // Opening an entry goes straight into the Reader, in this tab's
                // own navigation stack — 書庫's is untouched, exactly as
                // 歷史紀錄's jump-to-source is.
                .navigationDestination(for: ReaderRoute.self) { route in
                    ComicView(
                        comicID: route.comicID,
                        chapterID: route.chapterID,
                        targetPage: route.targetPage,
                        isPeek: route.isPeek
                    )
                }
                .toolbar {
                    if !groups.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Delete all", role: .destructive) {
                                isConfirmingDeleteAll = true
                            }
                        }
                    }
                }
                // Clearing everything is irreversible with no undo, so it asks
                // first — the pattern this app already uses for removing a
                // saved record. Deleting one chapter does not: it is a smaller
                // loss, and re-downloading it is one tap.
                .alert("Delete everything downloaded?", isPresented: $isConfirmingDeleteAll) {
                    Button("Delete", role: .destructive) { downloads.deleteEverything() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes every downloaded chapter from this device. It can't be undone.")
                }
        }
        .task { await reload() }
        // The store is read during body evaluation and so cannot be observable.
        // These two are what the manager mirrors of it: the slot count moves on
        // every admission, eviction, cancellation and deletion, and the
        // completed set moves when a download finishes.
        .onChange(of: downloads.usedSlots) { _, _ in Task { await reload() } }
        .onChange(of: downloads.completed) { _, _ in Task { await reload() } }
    }

    @ViewBuilder
    private var content: some View {
        if groups.isEmpty {
            if hasLoaded {
                emptyState
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            populatedList
        }
    }

    private var populatedList: some View {
        VStack(spacing: 0) {
            allowance
            List {
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.entries) { entry in
                            row(for: entry)
                                // A swipe deletes outright: one chapter is a
                                // small, re-downloadable loss, and a dialog per
                                // row would make tidying up the chore this
                                // feature is meant to avoid. Full swipe is off
                                // so a stray flick cannot do it.
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        downloads.delete(entry.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// What the allowance is costing, in slots and in bytes.
    private var allowance: some View {
        HStack {
            Text("\(downloads.usedSlots)/\(OfflineDownloadLimits.maxChapters) downloaded")
            Spacer()
            Text(totalBytes.formatted(.byteCount(style: .file)))
        }
        .font(AppFont.caption)
        .foregroundStyle(Color(.grayFont))
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var totalBytes: Int64 {
        groups.reduce(0) { $0 + $1.bytes }
    }

    /// A finished chapter opens the Reader. One still downloading does not: it
    /// would open, and offline it would fail — which is the one thing this
    /// screen exists to stop happening.
    @ViewBuilder
    private func row(for entry: DownloadedChapterEntry) -> some View {
        let state = downloads.state(for: entry.id)
        if state == .downloaded {
            NavigationLink(
                value: ReaderRoute(comicID: entry.chapter.comicID, chapterID: entry.chapter.chapterID)
            ) {
                DownloadedChapterRow(entry: entry, state: state)
            }
        } else {
            DownloadedChapterRow(entry: entry, state: state)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing downloaded yet",
            systemImage: "arrow.down.circle",
            description: Text("Chapters you download appear here, ready to read with no connection.")
        )
    }

    /// Reads the store and measures the files off the main thread — twenty
    /// chapters is a couple of thousand of them, and this runs while the reader
    /// is looking at the screen.
    private func reload() async {
        let store = self.store
        groups = await Task.detached(priority: .userInitiated) {
            let records = store.downloadedChapters()
            var sizes: [DownloadedChapterID: Int64] = [:]
            for record in records {
                sizes[record.id] = store.sizeOnDisk(of: record.id)
            }
            return downloadedComicGroups(from: records, sizes: sizes)
        }.value
        hasLoaded = true
    }
}

#Preview {
    DownloadsView()
}
