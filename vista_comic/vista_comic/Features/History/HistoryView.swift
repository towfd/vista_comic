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
//  The badge count is computed here, from the fetched list, because there is no
//  count endpoint and no shared client store. That makes this view the owner of
//  both the list and the number derived from it, which is why marking one
//  record read has to come back up (`onMarkedRead`) rather than being re-fetched.
//

import SwiftUI

struct HistoryView: View {
    @Environment(\.comprehensionRepository) private var repository
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: LoadState<[ComprehensionRecord]> = .loading

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: ComprehensionRecord.self) { record in
                    ComprehensionDetailView(record: record) { updated in
                        replace(updated)
                    }
                }
        }
        .task { await load() }
        // Explanations land while the app is elsewhere — that is the whole
        // point of enqueueing them — so coming back to the foreground is
        // exactly when the list is most likely to be stale.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
        .badge(unreadCount)
    }

    /// `0` renders no badge, so an empty or failed load simply shows nothing
    /// rather than a misleading zero.
    private var unreadCount: Int {
        guard case .loaded(let records) = state else { return 0 }
        return unreadExplanationCount(in: records)
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
    }

    /// Swaps one record in place after the detail screen marked it read, so the
    /// badge drops by exactly one without a round trip — and without the list
    /// reordering or scrolling under the reader on their way back.
    private func replace(_ updated: ComprehensionRecord) {
        guard case .loaded(var records) = state,
              let index = records.firstIndex(where: { $0.id == updated.id })
        else { return }
        records[index] = updated
        state = .loaded(records)
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
