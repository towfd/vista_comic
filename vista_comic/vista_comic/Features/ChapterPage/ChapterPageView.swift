//
//  ChapterPageView.swift
//  vista_comic
//
//  Created by 林鈺峯 on 2026/7/7.
//
//  Chapter list screen. The comic arriving from the library carries only a
//  `chapterCount` (the `/comics` summary), so this screen fetches the comic's
//  detail (`/comics/{id}`) to load its chapters, with loading and failure states.
//
import SwiftUI

struct ChapterPageView: View {
    let comic: Comic

    @Environment(\.comicRepository) private var repository
    @Environment(\.chapterDownloads) private var downloads
    @State private var state: LoadState<Comic> = .loading
    /// First load shows the full-screen spinner; later refreshes are silent.
    @State private var hasLoadedOnce = false
    /// Selection mode (`offline-download` ticket 06). `nil` when the list is
    /// behaving normally, which is the state every other screen assumes.
    @State private var selection: Set<String>?
    /// Set when a selection is larger than the device can hold, since the
    /// alternative — quietly downloading some of it — answers a question the
    /// reader did not ask.
    @State private var isShowingTooManyChapters = false

    var body: some View {
        content
            .task { await load() }
            .alert("Too many chapters", isPresented: $isShowingTooManyChapters) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can download up to \(OfflineDownloadLimits.maxChapters) chapters at once.")
            }
            // Re-fetch when this screen is revealed again after the reader is
            // popped, so per-chapter read badges reflect saved progress. Gated on
            // `hasLoadedOnce` so it doesn't double-load on first appearance.
            .onAppear {
                if hasLoadedOnce {
                    Task { await load() }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let detail):
            loaded(detail)
                .refreshable { await rescanAndLoad() }
        case .failed:
            ErrorStateView { Task { await load() } }
        }
    }

    /// Same gesture as the library's, and for the more common reason: chapters
    /// arrive in a comic that is already on the shelf. A rescan rebuilds the
    /// whole catalog, so pulling here is exactly as effective as walking back to
    /// the library to do it — and this is where the reader already is.
    private func rescanAndLoad() async {
        try? await repository.rescan()
        await load()
    }

    private func loaded(_ detail: Comic) -> some View {
        VStack {
            selectionControls(for: detail)

            CoverImage(url: detail.coverURL)
                .frame(width: 187, height: 187)
            Text(detail.title)
                .font(AppFont.title)

            // What the allowance is costing, stated before the reader spends it.
            // The cap is never enforced by refusing — downloading a
            // twenty-first chapter drops the oldest — so this is the only place
            // that says the limit exists at all until 已下載 arrives.
            Text("\(downloads.usedSlots)/\(OfflineDownloadLimits.maxChapters) downloaded")
                .font(AppFont.caption)
                .foregroundStyle(Color(.grayFont))

            ScrollView {
                // Lazy now that each row loads its own cover: a comic with a
                // hundred chapters would otherwise request a hundred
                // full-resolution pages the moment the list appears.
                LazyVStack(spacing: 0) {
                    ForEach(detail.chapters) { chapter in
                        ChapterListView(
                            comic: detail,
                            chapter: chapter,
                            isSelecting: selection != nil,
                            isSelected: selection?.contains(chapter.id) ?? false,
                            onToggle: { toggle(chapter) }
                        )
                    }
                }
            }
        }
    }

    /// Enter, confirm, or leave selection mode.
    ///
    /// A row of buttons rather than a navigation-bar toolbar, because this
    /// screen has no navigation bar of its own to put them in — it is pushed
    /// with the library's, and its own title is drawn in the content.
    @ViewBuilder
    private func selectionControls(for detail: Comic) -> some View {
        HStack {
            if let selected = selection {
                Button("Cancel") { selection = nil }
                Spacer()
                // Leaving without confirming downloads nothing: the whole
                // selection is discarded with the mode.
                Button("Download (\(selected.count))") {
                    download(selected, from: detail)
                }
                .disabled(selected.isEmpty)
            } else {
                Spacer()
                Button("Select") { selection = [] }
            }
        }
        .font(AppFont.caption)
        .padding(.horizontal)
    }

    private func toggle(_ chapter: Chapter) {
        guard var selected = selection else { return }
        if selected.contains(chapter.id) {
            selected.remove(chapter.id)
        } else {
            selected.insert(chapter.id)
        }
        selection = selected
    }

    /// Hands the whole selection to the engine, which admits the chapters one
    /// at a time — five in means exactly five out at the cap, and a batch can
    /// never be admitted as a unit that dodges it.
    private func download(_ selected: Set<String>, from detail: Comic) {
        let chapters = detail.chapters.filter { selected.contains($0.id) }
        guard downloads.download(comic: detail, chapters: chapters) else {
            isShowingTooManyChapters = true
            return
        }
        selection = nil
    }

    private func load() async {
        // Only the first load shows the spinner; a refresh-on-return keeps the
        // current chapter list visible and swaps in fresh data on success.
        if !hasLoadedOnce {
            state = .loading
        }
        do {
            state = .loaded(try await repository.comic(id: comic.id))
            hasLoadedOnce = true
        } catch {
            // A failed background refresh keeps the stale list; only a failed
            // first load surfaces the error page.
            if !hasLoadedOnce {
                state = .failed(error)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChapterPageView(comic: SampleData.comics[0])
            .navigationDestination(for: ReaderRoute.self) { route in
                ComicView(comicID: route.comicID, chapterID: route.chapterID)
            }
    }
}
