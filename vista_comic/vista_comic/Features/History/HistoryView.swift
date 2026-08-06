//
//  HistoryView.swift
//  vista_comic
//
//  歷史紀錄 tab content (`comprehension-response-ux` ticket 19), taking the tab
//  slot 單字本 held. Mirrors `VocabularyView`'s `LoadState`-driven
//  loading/loaded/failed wiring and its own `NavigationStack` — each tab is its
//  own navigation context.
//
//  The list is flat and newest-first, not grouped by comic and chapter: a
//  reader working through one long series would collapse into a single enormous
//  section, and a just-arrived explanation would stop being reliably at the top
//  — which is exactly where the thing the badge points at wants to be.
//
//  The badge used to be computed and displayed here. Ticket 22 moved ownership
//  up to `RootTabView`, because a tab's content does not appear until the tab is
//  selected — so a badge living here could only learn something had arrived once
//  the reader had already opened it. What stays here is the *counting*: this view
//  hands its freshly-fetched list to `UnreadExplanationBadge.recount(from:)`, so
//  the tab on screen never causes a second request and the badge can never
//  disagree with the list it points at.
//
//  A record changing on the detail screen still comes back up (`onChanged`)
//  rather than being re-fetched, for the same reason as before.
//
//  Ticket 20 adds swipe-to-delete. Deleting moved from a button to a swipe
//  because every translate now writes a row, so pruning is routine rather than
//  rare — but the confirmation stays, since deletion is still irreversible and
//  there is no undo. Retry deliberately did **not** move here: it lives only on
//  the detail screen, where it costs a deliberate tap into one record.
//

import SwiftUI

struct HistoryView: View {
    @Environment(\.comprehensionRepository) private var repository
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.unreadExplanationBadge) private var badge
    @State private var state: LoadState<[ComprehensionRecord]> = .loading
    /// The record a swipe has proposed deleting, held until the reader confirms
    /// — nothing is sent to the backend while this is set.
    @State private var pendingDeletion: ComprehensionRecord?
    /// Set on a failed delete to drive a one-shot alert. The row stays in the
    /// list, since nothing was actually deleted.
    @State private var showDeleteError = false

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: ComprehensionRecord.self) { record in
                    ComprehensionDetailView(
                        record: record,
                        onChanged: { replace($0) },
                        onDeleted: { remove($0) }
                    )
                }
                // The detail screen's jump-back pushes onto *this* tab's stack,
                // exactly as 單字本's did: each tab is its own navigation
                // context, so peeking at an old page never touches 書庫's.
                .navigationDestination(for: ReaderRoute.self) { route in
                    ComicView(
                        comicID: route.comicID,
                        chapterID: route.chapterID,
                        targetPage: route.targetPage,
                        isPeek: route.isPeek
                    )
                }
        }
        .task { await load() }
        // Explanations land while the app is elsewhere — that is the whole
        // point of enqueueing them — so coming back to the foreground is
        // exactly when the list is most likely to be stale.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        // Same two alerts the detail screen shows, from one definition — the
        // two screens must never word an irreversible action differently.
        .recordDeletionAlerts(
            isConfirming: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            isShowingFailure: $showDeleteError,
            confirm: {
                guard let record = pendingDeletion else { return }
                Task { await delete(record) }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let records):
            if records.isEmpty {
                emptyState
            } else {
                populatedList(records)
            }
        case .failed:
            // Distinct from the empty state on purpose: "we couldn't load this"
            // must never read as "your records are gone".
            ErrorStateView { Task { await load() } }
        }
    }

    private func populatedList(_ records: [ComprehensionRecord]) -> some View {
        List(records) { record in
            NavigationLink(value: record) {
                ComprehensionRow(record: record)
            }
            // A swipe only *proposes* the deletion; the alert is what performs
            // it. `allowsFullSwipe` is off for the same reason the confirmation
            // exists — a full-swipe gesture that deletes on its own is exactly
            // the stray flick this list must survive.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    pendingDeletion = record
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("History")
        .refreshable { await load() }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing here yet",
            systemImage: "clock.arrow.circlepath",
            description: Text("Everything you translate while reading is recorded here automatically.")
        )
    }

    /// Newest first. Sorted here rather than trusted from the API so the order
    /// the reader depends on is stated in one place they can see.
    private func load() async {
        do {
            let records = try await repository.list()
            state = .loaded(records.sorted { $0.createdAt > $1.createdAt })
        } catch {
            state = .failed(error)
        }
        publishCount()
    }

    /// Swaps one record in place after the detail screen changed it — marked it
    /// read, or retried it — so the badge and the row's status follow without a
    /// round trip, and without the list reordering or scrolling under the
    /// reader on their way back.
    private func replace(_ updated: ComprehensionRecord) {
        guard case .loaded(var records) = state,
              let index = records.firstIndex(where: { $0.id == updated.id })
        else { return }
        records[index] = updated
        state = .loaded(records)
        publishCount()
    }

    /// Deletes `record` and, on success, drops it from the displayed list in
    /// place — no full reload, so the rest of the list neither flickers nor
    /// scrolls. A failure leaves the row exactly where it is, because it is
    /// still there on the backend.
    private func delete(_ record: ComprehensionRecord) async {
        switch await deleteComprehensionRecord(id: record.id, using: repository) {
        case .loaded:
            remove(record)
        case .failed:
            showDeleteError = true
        case .loading:
            break
        }
    }

    /// Drops one row, whether this screen deleted it or the detail screen did.
    private func remove(_ record: ComprehensionRecord) {
        guard case .loaded(var records) = state else { return }
        records.removeAll { $0.id == record.id }
        state = .loaded(records)
        publishCount()
    }

    /// Hands the badge the list this view already holds, so opening a record or
    /// deleting one moves the number with no second request.
    ///
    /// A failed load publishes nothing: the previous count is more honest than
    /// zero, since "we couldn't ask" is not "nothing is waiting" — the same rule
    /// that stops the list itself degrading a read failure into an empty state.
    private func publishCount() {
        guard case .loaded(let records) = state else { return }
        badge.recount(from: records)
    }
}

// MARK: - Preview support

/// Preview-only stub, mirroring `PreviewTranslationRepository`'s role for
/// `TranslationRepository` — keeps `#Preview`s off the network, since
/// `comprehensionRepository`'s environment default is the live API conformer.
private struct PreviewComprehensionRepository: ComprehensionRepository {
    struct StubError: Error {}

    var listResult: Result<[ComprehensionRecord], StubError> = .success([])

    func enqueue(
        sourceText: String,
        translatedText: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int,
        useStrongerModel: Bool
    ) async throws -> ComprehensionRecord { .preview() }

    func list() async throws -> [ComprehensionRecord] { try listResult.get() }
    func record(id: Int) async throws -> ComprehensionRecord { .preview() }
    func setRead(id: Int, isRead: Bool) async throws -> ComprehensionRecord {
        .preview(isRead: isRead)
    }
    func retry(id: Int) async throws -> ComprehensionRecord { .preview() }
    func delete(id: Int) async throws {}
}

extension ComprehensionRecord {
    /// Preview/sample-only factory. `ComprehensionRecord` exposes no memberwise
    /// initializer beyond `Decodable`, so this decodes a canned payload —
    /// mirroring `SavedTranslation.preview()`'s own reasoning. Not `private`
    /// because `ComprehensionRow`'s `#Preview` uses it too.
    static func preview(
        id: Int = 1,
        sourceText: String = "お前、なかなかやるじゃないか",
        status: String = "pending",
        notes: String? = nil,
        cloudTranslation: String? = nil,
        isRead: Bool = false,
        comicTitle: String? = "marrymyhusband",
        chapterTitle: String? = "bai1",
        createdAt: String = "2026-08-05T10:30:00Z"
    ) -> ComprehensionRecord {
        func quoted(_ value: String?) -> String {
            value.map { "\"\($0)\"" } ?? "null"
        }
        let json = """
        {
            "id": \(id),
            "sourceText": "\(sourceText)",
            "translatedText": "你這家伙，還挺有兩下子的嘛",
            "cloudTranslation": \(quoted(cloudTranslation)),
            "grammarNotes": \(quoted(notes)),
            "contextNotes": \(quoted(notes)),
            "toneRegister": \(quoted(notes)),
            "targetLanguage": "zh-Hant",
            "comicId": "comic-1",
            "chapterId": "chapter-1",
            "pageNumber": 3,
            "comicTitle": \(quoted(comicTitle)),
            "chapterTitle": \(quoted(chapterTitle)),
            "status": "\(status)",
            "isRead": \(isRead),
            "useStrongerModel": false,
            "createdAt": "\(createdAt)"
        }
        """
        return try! APIConfig.iso8601Decoder.decode(
            ComprehensionRecord.self, from: Data(json.utf8)
        )
    }
}

#Preview("Loaded") {
    HistoryView()
        .environment(
            \.comprehensionRepository,
            PreviewComprehensionRepository(listResult: .success([
                .preview(id: 1, status: "ok", notes: "なかなか + 否定形…",
                         cloudTranslation: "你小子，挺有一套的嘛"),
                .preview(id: 2, sourceText: "Cảm ơn bạn", status: "pending",
                         createdAt: "2026-08-04T08:00:00Z"),
                .preview(id: 3, sourceText: "Xin chào", status: "failed",
                         createdAt: "2026-08-03T08:00:00Z"),
                .preview(id: 4, sourceText: "Tạm biệt", status: "declined",
                         comicTitle: nil, chapterTitle: nil,
                         createdAt: "2026-08-02T08:00:00Z"),
            ]))
        )
}

#Preview("Empty") {
    HistoryView()
        .environment(
            \.comprehensionRepository,
            PreviewComprehensionRepository(listResult: .success([]))
        )
}

#Preview("Failed") {
    HistoryView()
        .environment(
            \.comprehensionRepository,
            PreviewComprehensionRepository(
                listResult: .failure(PreviewComprehensionRepository.StubError())
            )
        )
}
