//
//  SelectionSaveFlowTests.swift
//  vista_comicTests
//
//  Exercises `ocr-translation` Ticket 05's wiring: `saveSelection(...)`, the
//  free function `CroppedSelectionPreview` calls from its "Save" action to
//  persist the current original/translated text pair and its source
//  reference through `TranslationRepository`, mapped onto `LoadState`. Uses a
//  stub `TranslationRepository` (mirroring `StubOCRRecognizer`/
//  `StubTranslator`'s pattern) so this suite stays independent of the real
//  backend — it proves the save-button → save → confirm/fail path, not
//  `APITranslationRepository`'s request-building (already covered by
//  `APITranslationRepositoryTests`).
//

import Testing
import Foundation
@testable import vista_comic

/// A stub `TranslationRepository`: returns or throws whatever the test
/// configures for `save`, and records the last arguments it was called with,
/// so tests can assert on the protocol boundary without a real backend.
/// `list()` is unused by this flow but stubbed out to satisfy the protocol.
final class StubTranslationRepository: TranslationRepository {
    struct StubSaveError: Error, Equatable {
        let message: String
    }

    var saveResult: Result<SavedTranslation, StubSaveError> = .failure(StubSaveError(message: "not configured"))
    private(set) var lastOriginalText: String?
    private(set) var lastTranslatedText: String?
    private(set) var lastTargetLanguage: String?
    private(set) var lastComicID: String?
    private(set) var lastChapterID: String?
    private(set) var lastPageNumber: Int?
    private(set) var saveCallCount = 0

    /// `ocr-translation` ticket 08 (delete): configurable result + call
    /// tracking, mirroring `save`'s shape above.
    var deleteResult: Result<Void, StubSaveError> = .success(())
    private(set) var lastDeletedID: Int?
    private(set) var deleteCallCount = 0

    func save(
        originalText: String,
        translatedText: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int
    ) async throws -> SavedTranslation {
        saveCallCount += 1
        lastOriginalText = originalText
        lastTranslatedText = translatedText
        lastTargetLanguage = targetLanguage
        lastComicID = comicID
        lastChapterID = chapterID
        lastPageNumber = pageNumber
        switch saveResult {
        case .success(let saved):
            return saved
        case .failure(let error):
            throw error
        }
    }

    func list() async throws -> [SavedTranslation] {
        []
    }

    func delete(id: Int) async throws {
        deleteCallCount += 1
        lastDeletedID = id
        switch deleteResult {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

@Suite("Selection → save flow")
struct SelectionSaveFlowTests {
    private func makeSavedTranslation(
        id: Int = 1,
        originalText: String = "Xin chào",
        translatedText: String = "你好",
        targetLanguage: String = "zh-Hant",
        comicID: String = "comic-1",
        chapterID: String = "chapter-1",
        pageNumber: Int = 3
    ) -> SavedTranslation {
        // `SavedTranslation` has no memberwise-friendly initializer exposed
        // beyond `Decodable`, mirroring `APITranslationRepositoryTests`'s own
        // approach: decode a small canned JSON payload instead of
        // constructing the struct directly.
        let json = """
        {
            "id": \(id),
            "originalText": "\(originalText)",
            "translatedText": "\(translatedText)",
            "targetLanguage": "\(targetLanguage)",
            "comicId": "\(comicID)",
            "chapterId": "\(chapterID)",
            "pageNumber": \(pageNumber),
            "savedAt": "2026-01-15T10:30:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(SavedTranslation.self, from: Data(json.utf8))
    }

    // MARK: - Success

    @Test func successfulSaveYieldsLoadedSavedTranslation() async throws {
        let stub = StubTranslationRepository()
        stub.saveResult = .success(makeSavedTranslation(id: 42))

        let state = await saveSelection(
            originalText: "Xin chào",
            translatedText: "你好",
            targetLanguage: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 3,
            using: stub
        )

        guard case .loaded(let saved) = state else {
            Issue.record("expected .loaded, got \(state)")
            return
        }
        #expect(saved.id == 42)
    }

    @Test func passesTheOriginalTextTranslatedTextTargetLanguageAndSourceReferenceToTheRepository() async throws {
        let stub = StubTranslationRepository()
        stub.saveResult = .success(makeSavedTranslation())

        _ = await saveSelection(
            originalText: "Xin chào bạn",
            translatedText: "你好朋友",
            targetLanguage: "zh-Hant",
            comicID: "comic-42",
            chapterID: "chapter-7",
            pageNumber: 12,
            using: stub
        )

        #expect(stub.lastOriginalText == "Xin chào bạn")
        #expect(stub.lastTranslatedText == "你好朋友")
        #expect(stub.lastTargetLanguage == "zh-Hant")
        #expect(stub.lastComicID == "comic-42")
        #expect(stub.lastChapterID == "chapter-7")
        #expect(stub.lastPageNumber == 12)
        #expect(stub.saveCallCount == 1)
    }

    // MARK: - Failure

    /// Save failure surfaces as `.failed` (not silently swallowed) so a
    /// caller can show a clear message — the AC's explicit requirement.
    @Test func saveFailureSurfacesAsFailedNotSilently() async throws {
        let stub = StubTranslationRepository()
        stub.saveResult = .failure(.init(message: "network unreachable"))

        let state = await saveSelection(
            originalText: "Xin chào",
            translatedText: "你好",
            targetLanguage: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 1,
            using: stub
        )

        guard case .failed(let error) = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
        #expect((error as? StubTranslationRepository.StubSaveError)?.message == "network unreachable")
    }

    // MARK: - Retry

    /// A retry re-runs save with the same arguments and can succeed after an
    /// earlier failure — the flow a "Retry" button drives.
    @Test func retryingAfterFailureCanSucceed() async throws {
        let stub = StubTranslationRepository()

        stub.saveResult = .failure(.init(message: "temporary"))
        let firstAttempt = await saveSelection(
            originalText: "Xin chào",
            translatedText: "你好",
            targetLanguage: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 1,
            using: stub
        )
        guard case .failed = firstAttempt else {
            Issue.record("expected the first attempt to fail")
            return
        }

        stub.saveResult = .success(makeSavedTranslation(id: 99))
        let retryAttempt = await saveSelection(
            originalText: "Xin chào",
            translatedText: "你好",
            targetLanguage: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 1,
            using: stub
        )
        guard case .loaded(let saved) = retryAttempt else {
            Issue.record("expected the retry to succeed")
            return
        }
        #expect(saved.id == 99)
        #expect(stub.saveCallCount == 2)
    }
}
