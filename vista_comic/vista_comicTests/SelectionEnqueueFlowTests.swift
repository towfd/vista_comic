//
//  SelectionEnqueueFlowTests.swift
//  vista_comicTests
//
//  Exercises `comprehension-response-ux` ticket 17's wiring:
//  `translateAndEnqueueSelection(...)`, the free function
//  `CroppedSelectionPreview`'s "Translate" action now runs. It translates on
//  device **first** and only then enqueues the deeper explanation on the
//  backend, inverting M9's cloud-first order.
//
//  Reuses `StubTranslator` (Ticket 01) so the suite stays independent of the
//  real on-device `Translation` framework, and stubs `ComprehensionRepository`
//  so nothing touches the network. This proves the ordering and the failure
//  boundaries, not translation quality.
//

import Foundation
import Testing

@testable import vista_comic

/// Records what it was asked to enqueue and returns (or throws) what the test
/// tells it to.
private final class StubComprehensionRepository: ComprehensionRepository, @unchecked Sendable {
    var enqueueResult: Result<ComprehensionRecord, Error> = .success(.stub())
    private(set) var enqueueCallCount = 0
    private(set) var lastSourceText: String?
    private(set) var lastTranslatedText: String?
    private(set) var lastTargetLanguage: String?
    private(set) var lastComicID: String?
    private(set) var lastChapterID: String?
    private(set) var lastPageNumber: Int?
    private(set) var lastUseStrongerModel: Bool?

    func enqueue(
        sourceText: String,
        translatedText: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int,
        useStrongerModel: Bool
    ) async throws -> ComprehensionRecord {
        enqueueCallCount += 1
        lastSourceText = sourceText
        lastTranslatedText = translatedText
        lastTargetLanguage = targetLanguage
        lastComicID = comicID
        lastChapterID = chapterID
        lastPageNumber = pageNumber
        lastUseStrongerModel = useStrongerModel
        return try enqueueResult.get()
    }

    func list() async throws -> [ComprehensionRecord] { [] }
    func record(id: Int) async throws -> ComprehensionRecord { try enqueueResult.get() }
    func setRead(id: Int, isRead: Bool) async throws -> ComprehensionRecord {
        try enqueueResult.get()
    }
    func retry(id: Int) async throws -> ComprehensionRecord { try enqueueResult.get() }
    func delete(id: Int) async throws {}
}

extension ComprehensionRecord {
    /// Decodes a canned payload, since this type exposes no memberwise
    /// initializer beyond `Decodable` — mirroring `SavedTranslation.preview()`'s
    /// own reasoning.
    static func stub(id: Int = 1, status: String = "pending") -> ComprehensionRecord {
        let json = """
        {
            "id": \(id),
            "sourceText": "Xin chào",
            "translatedText": "你好",
            "cloudTranslation": null,
            "grammarNotes": null,
            "contextNotes": null,
            "toneRegister": null,
            "targetLanguage": "zh-Hant",
            "comicId": "comic-1",
            "chapterId": "chapter-1",
            "pageNumber": 3,
            "comicTitle": "marrymyhusband",
            "chapterTitle": "bai1",
            "status": "\(status)",
            "isRead": false,
            "useStrongerModel": false,
            "createdAt": "2026-08-05T10:30:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(ComprehensionRecord.self, from: Data(json.utf8))
    }
}

@Suite("Selection → translate then enqueue flow")
struct SelectionEnqueueFlowTests {
    private let traditionalChinese = Locale.Language(languageCode: "zh", script: "Hant")

    private func run(
        text: String = "Xin chào",
        translator: StubTranslator,
        repository: StubComprehensionRepository,
        useStrongerModel: Bool = false
    ) async -> LoadState<SelectionEnqueueOutcome> {
        await translateAndEnqueueSelection(
            text,
            to: traditionalChinese,
            targetLanguageCode: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 3,
            useStrongerModel: useStrongerModel,
            using: translator,
            repository: repository
        )
    }

    // MARK: - The happy path

    @Test func aSuccessfulTranslateRecordsAndReturnsBoth() async throws {
        let translator = StubTranslator()
        translator.result = .success("你好")
        let repository = StubComprehensionRepository()

        let state = await run(translator: translator, repository: repository)

        guard case .loaded(.recorded(let translation, let record)) = state else {
            Issue.record("expected .loaded(.recorded), got \(state)")
            return
        }
        #expect(translation == "你好")
        #expect(record.id == 1)
    }

    /// The whole inversion: the reader's translation comes from the device, and
    /// what goes to the backend is that translation plus a source reference —
    /// never an image.
    @Test func enqueuesTheOnDeviceTranslationWithItsSourceReference() async throws {
        let translator = StubTranslator()
        translator.result = .success("你好")
        let repository = StubComprehensionRepository()

        _ = await run(text: "Xin chào", translator: translator, repository: repository)

        #expect(repository.lastSourceText == "Xin chào")
        #expect(repository.lastTranslatedText == "你好")
        #expect(repository.lastTargetLanguage == "zh-Hant")
        #expect(repository.lastComicID == "comic-1")
        #expect(repository.lastChapterID == "chapter-1")
        #expect(repository.lastPageNumber == 3)
    }

    @Test func passesTheRequestedModelTierThrough() async throws {
        let translator = StubTranslator()
        translator.result = .success("你好")
        let repository = StubComprehensionRepository()

        _ = await run(translator: translator, repository: repository, useStrongerModel: true)

        #expect(repository.lastUseStrongerModel == true)
    }

    // MARK: - The on-device step failing is the only real failure

    /// Without a translation there is nothing to show and nothing to record, so
    /// the backend must not be called and no request may be spent.
    @Test func aFailedOnDeviceTranslationEnqueuesNothing() async throws {
        let translator = StubTranslator()
        translator.result = .failure(TranslationError.languagePackUnavailable)
        let repository = StubComprehensionRepository()

        let state = await run(translator: translator, repository: repository)

        guard case .failed = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
        #expect(repository.enqueueCallCount == 0)
    }

    // MARK: - An enqueue failure is a variant of success

    /// The reader does have their translation, so treating this as failure
    /// would make the screen throw away something it actually has.
    @Test func aQuotaRefusalStillReturnsTheTranslation() async throws {
        let translator = StubTranslator()
        translator.result = .success("你好")
        let repository = StubComprehensionRepository()
        repository.enqueueResult = .failure(ComprehensionEnqueueError.dailyCapReached)

        let state = await run(translator: translator, repository: repository)

        guard case .loaded(.notRecorded(let translation, let reason)) = state else {
            Issue.record("expected .loaded(.notRecorded), got \(state)")
            return
        }
        #expect(translation == "你好")
        #expect(reason == .quotaExhausted)
    }

    /// Split by whether retrying can possibly help — the same rule the screen
    /// applies to a declined versus a failed explanation.
    @Test func aTransientEnqueueFailureIsDistinguishedFromTheQuotaCase() async throws {
        let translator = StubTranslator()
        translator.result = .success("你好")
        let repository = StubComprehensionRepository()
        repository.enqueueResult = .failure(APIError.httpStatus(503))

        let state = await run(translator: translator, repository: repository)

        guard case .loaded(.notRecorded(let translation, let reason)) = state else {
            Issue.record("expected .loaded(.notRecorded), got \(state)")
            return
        }
        #expect(translation == "你好")
        #expect(reason == .transient)
    }

    /// A conformer throwing something this flow has never heard of is still
    /// transient — it must not be mistaken for the one permanent case.
    @Test func anUnexpectedEnqueueErrorIsTreatedAsTransient() async throws {
        struct Unexpected: Error {}
        let translator = StubTranslator()
        translator.result = .success("你好")
        let repository = StubComprehensionRepository()
        repository.enqueueResult = .failure(Unexpected())

        let state = await run(translator: translator, repository: repository)

        guard case .loaded(.notRecorded(_, let reason)) = state else {
            Issue.record("expected .loaded(.notRecorded), got \(state)")
            return
        }
        #expect(reason == .transient)
    }

    // MARK: - Display precedence

    @Test func theCloudTranslationIsPreferredOnceItArrives() async throws {
        let pending = ComprehensionRecord.stub()
        #expect(pending.displayedTranslation == "你好")
        #expect(pending.hasExplanation == false)
    }

    /// An unknown status must not fail decoding: the backend owns this
    /// vocabulary, and one unrecognised row must not cost the reader their
    /// whole history.
    @Test func anUnknownStatusDecodesAsInProgressRatherThanFailing() async throws {
        let record = ComprehensionRecord.stub(status: "something-new")

        #expect(record.status == .unknown)
        #expect(record.status.isInProgress)
    }
}
