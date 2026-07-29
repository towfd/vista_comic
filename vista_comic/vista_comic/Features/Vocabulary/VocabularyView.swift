//
//  VocabularyView.swift
//  vista_comic
//
//  單字本 tab content (ocr-translation ticket 06): drives the real
//  saved-translation list from `TranslationRepository.list()` instead of the
//  earlier standing placeholder, mirroring `HomeView`'s
//  `LoadState`-driven loading/loaded/failed wiring and `.task` load.
//
//  Owns its own `NavigationStack` (ticket 07), independent of the 書庫 tab's
//  — each tab is its own navigation context, so jumping to a saved
//  translation's source page (via `SavedTranslationRow`'s trailing
//  `NavigationLink(value: ReaderRoute)`) never touches 書庫's stack.
//

import SwiftUI

struct VocabularyView: View {
    @Environment(\.translationRepository) private var repository
    @State private var state: LoadState<[SavedTranslation]> = .loading

    var body: some View {
        NavigationStack {
            content
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
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let translations):
            if translations.isEmpty {
                emptyState
            } else {
                populatedList(translations)
            }
        case .failed:
            ErrorStateView { Task { await load() } }
        }
    }

    private func populatedList(_ translations: [SavedTranslation]) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Vocabulary")
                    .font(AppFont.title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(translations) { translation in
                    SavedTranslationRow(translation: translation)
                }
            }
            .padding()
        }
    }

    /// Keeps the placeholder's original copy/icon (per the ticket) instead of
    /// showing an empty list once there really is nothing saved.
    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing saved yet",
            systemImage: "text.book.closed",
            description: Text("Words and sentences you save while reading will appear here.")
        )
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await repository.list())
        } catch {
            state = .failed(error)
        }
    }
}

// MARK: - Preview support

/// Preview-only `TranslationRepository` stub, mirroring `PreviewComicRepository`'s
/// role for `ComicRepository` — keeps `#Preview`s (and the SwiftUI canvas)
/// off the network. `translationRepository`'s environment default is the
/// live `APITranslationRepository` (see that file's doc comment), so
/// previews below inject this explicitly instead of relying on the default.
private struct PreviewTranslationRepository: TranslationRepository {
    struct StubError: Error {}

    var listResult: Result<[SavedTranslation], StubError> = .success([])

    func save(
        originalText: String,
        translatedText: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int
    ) async throws -> SavedTranslation {
        .preview()
    }

    func list() async throws -> [SavedTranslation] {
        switch listResult {
        case .success(let translations):
            return translations
        case .failure(let error):
            throw error
        }
    }
}

extension SavedTranslation {
    /// Preview/sample-only factory: `SavedTranslation` exposes no
    /// memberwise initializer beyond `Decodable`, so this decodes a small
    /// canned payload instead — mirroring `SelectionSaveFlowTests`'s own
    /// `makeSavedTranslation` helper. Not marked `fileprivate` because
    /// `SavedTranslationRow.swift`'s own `#Preview` also uses it.
    static func preview(
        id: Int = 1,
        originalText: String = "Xin chào",
        translatedText: String = "你好",
        comicID: String = "comic-1",
        chapterID: String = "chapter-1",
        pageNumber: Int = 3,
        savedAt: String = "2026-01-15T10:30:00Z"
    ) -> SavedTranslation {
        let json = """
        {
            "id": \(id),
            "originalText": "\(originalText)",
            "translatedText": "\(translatedText)",
            "targetLanguage": "zh-Hant",
            "comicId": "\(comicID)",
            "chapterId": "\(chapterID)",
            "pageNumber": \(pageNumber),
            "savedAt": "\(savedAt)"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(SavedTranslation.self, from: Data(json.utf8))
    }
}

#Preview("Loaded") {
    VocabularyView()
        .environment(
            \.translationRepository,
            PreviewTranslationRepository(listResult: .success([
                .preview(
                    id: 1,
                    originalText: "Xin chào",
                    translatedText: "你好",
                    comicID: "comic-1",
                    chapterID: "chapter-1",
                    pageNumber: 3
                ),
                .preview(
                    id: 2,
                    originalText: "Cảm ơn bạn",
                    translatedText: "謝謝你",
                    comicID: "comic-2",
                    chapterID: "chapter-4",
                    pageNumber: 12,
                    savedAt: "2026-01-20T08:00:00Z"
                ),
            ]))
        )
}

#Preview("Empty") {
    VocabularyView()
        .environment(
            \.translationRepository,
            PreviewTranslationRepository(listResult: .success([]))
        )
}

#Preview("Failed") {
    VocabularyView()
        .environment(
            \.translationRepository,
            PreviewTranslationRepository(listResult: .failure(PreviewTranslationRepository.StubError()))
        )
}
