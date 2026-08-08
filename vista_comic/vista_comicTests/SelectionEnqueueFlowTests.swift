//
//  SelectionEnqueueFlowTests.swift
//  vista_comicTests
//
//  Exercises `requestExplanation(...)`, the free function
//  `CroppedSelectionPreview`'s opt-in "深入解釋" action runs — the *only* thing
//  in the selection flow that reaches the backend, spends a Claude request, or
//  creates a 歷史紀錄 row. Tapping "Translate" runs `translateSelection` alone
//  (covered by `SelectionTranslationFlowTests`) and touches none of this.
//
//  That separation is structural rather than asserted: `translateSelection`
//  takes no repository, so there is no way for a plain translate to enqueue
//  anything. What remains testable here is the enqueue's own boundaries.
//
//  Stubs `ComprehensionRepository` so nothing touches the network.
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

    /// Consumed one per `record(id:)` call, so a test can script a poll that
    /// sees `pending` a few times before the explanation lands. The last entry
    /// repeats once exhausted, so a poll that over-runs doesn't crash.
    var recordResults: [Result<ComprehensionRecord, Error>] = []
    private(set) var recordCallCount = 0
    private(set) var setReadCallCount = 0
    private(set) var lastSetReadValue: Bool?
    private(set) var retryCallCount = 0

    func list() async throws -> [ComprehensionRecord] { [] }

    func record(id: Int) async throws -> ComprehensionRecord {
        defer { recordCallCount += 1 }
        guard !recordResults.isEmpty else { return try enqueueResult.get() }
        return try recordResults[min(recordCallCount, recordResults.count - 1)].get()
    }

    func setRead(id: Int, isRead: Bool) async throws -> ComprehensionRecord {
        setReadCallCount += 1
        lastSetReadValue = isRead
        return try enqueueResult.get()
    }

    func retry(id: Int) async throws -> ComprehensionRecord {
        retryCallCount += 1
        return try enqueueResult.get()
    }

    func delete(id: Int) async throws {}
}

extension ComprehensionRecord {
    /// Decodes a canned payload, since this type exposes no memberwise
    /// initializer beyond `Decodable` — mirroring `SavedTranslation.preview()`'s
    /// own reasoning.
    static func stub(
        id: Int = 1,
        status: String = "pending",
        cloudTranslation: String? = nil,
        notes: String? = nil
    ) -> ComprehensionRecord {
        func quoted(_ value: String?) -> String {
            value.map { "\"\($0)\"" } ?? "null"
        }
        let json = """
        {
            "id": \(id),
            "sourceText": "Xin chào",
            "translatedText": "你好",
            "cloudTranslation": \(quoted(cloudTranslation)),
            "grammarNotes": \(quoted(notes)),
            "contextNotes": \(quoted(notes)),
            "toneRegister": \(quoted(notes)),
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

@Suite("Selection → request a deeper explanation")
struct SelectionEnqueueFlowTests {
    private func run(
        text: String = "Xin chào",
        translation: String = "你好",
        repository: StubComprehensionRepository,
        useStrongerModel: Bool = false
    ) async -> ExplanationRequestOutcome {
        await requestExplanation(
            sourceText: text,
            translation: translation,
            targetLanguageCode: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 3,
            useStrongerModel: useStrongerModel,
            repository: repository
        )
    }

    // MARK: - The happy path

    @Test func aSuccessfulRequestReturnsTheCreatedRecord() async throws {
        let repository = StubComprehensionRepository()

        let outcome = await run(repository: repository)

        guard case .recorded(let record) = outcome else {
            Issue.record("expected .recorded, got \(outcome)")
            return
        }
        #expect(record.id == 1)
    }

    /// What goes to the backend is the text plus the translation the reader is
    /// already looking at, and a source reference — never an image.
    @Test func enqueuesTheOnDeviceTranslationWithItsSourceReference() async throws {
        let repository = StubComprehensionRepository()

        _ = await run(text: "Xin chào", translation: "你好", repository: repository)

        #expect(repository.lastSourceText == "Xin chào")
        #expect(repository.lastTranslatedText == "你好")
        #expect(repository.lastTargetLanguage == "zh-Hant")
        #expect(repository.lastComicID == "comic-1")
        #expect(repository.lastChapterID == "chapter-1")
        #expect(repository.lastPageNumber == 3)
    }

    @Test func passesTheRequestedModelTierThrough() async throws {
        let repository = StubComprehensionRepository()

        _ = await run(repository: repository, useStrongerModel: true)

        #expect(repository.lastUseStrongerModel == true)
    }

    // MARK: - A refused enqueue still leaves the translation standing

    /// The reader keeps the translation on screen either way, so what a refusal
    /// costs them is the explanation and the 歷史紀錄 row — which is what these
    /// reasons distinguish, rather than success from failure.
    @Test func aQuotaRefusalIsReportedAsPermanent() async throws {
        let repository = StubComprehensionRepository()
        repository.enqueueResult = .failure(ComprehensionEnqueueError.dailyCapReached)

        let outcome = await run(repository: repository)

        #expect(outcome == .notRecorded(.quotaExhausted))
        #expect(outcome.record == nil)
    }

    /// Split by whether retrying can possibly help — the same rule the screen
    /// applies to a declined versus a failed explanation.
    @Test func aTransientEnqueueFailureIsDistinguishedFromTheQuotaCase() async throws {
        let repository = StubComprehensionRepository()
        repository.enqueueResult = .failure(APIError.httpStatus(503))

        let outcome = await run(repository: repository)

        #expect(outcome == .notRecorded(.transient))
    }

    /// A conformer throwing something this flow has never heard of is still
    /// transient — it must not be mistaken for the one permanent case.
    @Test func anUnexpectedEnqueueErrorIsTreatedAsTransient() async throws {
        struct Unexpected: Error {}
        let repository = StubComprehensionRepository()
        repository.enqueueResult = .failure(Unexpected())

        let outcome = await run(repository: repository)

        #expect(outcome == .notRecorded(.transient))
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

/// `comprehension-response-ux` ticket 18: what the reader sees while — and
/// after — the backend produces the explanation.
@Suite("Explanation arriving while the reader watches")
struct AwaitExplanationTests {
    /// Never actually waits, so a poll that would take minutes in production
    /// takes microseconds here. Injecting this is the whole reason
    /// `awaitExplanation` takes a `sleep` parameter.
    private let noWait: (Duration) async throws -> Void = { _ in }

    private func poll(
        _ repository: StubComprehensionRepository
    ) async -> ComprehensionRecord? {
        await awaitExplanation(for: 1, using: repository, sleep: noWait)
    }

    // MARK: - Polling until the backend is done

    @Test func keepsPollingWhileTheRecordIsUnfinishedAndReturnsTheFinishedOne() async throws {
        let repository = StubComprehensionRepository()
        repository.recordResults = [
            .success(.stub(status: "pending")),
            .success(.stub(status: "running")),
            .success(.stub(status: "ok", cloudTranslation: "您好", notes: "…")),
        ]

        let finished = await poll(repository)

        #expect(finished?.status == .ok)
        #expect(repository.recordCallCount == 3)
    }

    /// A dropped connection mid-wait is exactly the case worth surviving: the
    /// explanation is still coming, and giving up would strand the reader in
    /// front of a spinner that never resolves.
    @Test func aTransientFetchFailureDoesNotEndThePoll() async throws {
        let repository = StubComprehensionRepository()
        repository.recordResults = [
            .failure(APIError.httpStatus(503)),
            .success(.stub(status: "ok", notes: "…")),
        ]

        let finished = await poll(repository)

        #expect(finished?.status == .ok)
    }

    // MARK: - Marking read

    /// "Read" means the reader saw it arrive, which is only knowable here.
    @Test func marksTheRecordReadWhenTheExplanationLands() async throws {
        let repository = StubComprehensionRepository()
        repository.recordResults = [.success(.stub(status: "ok", notes: "…"))]

        _ = await poll(repository)

        #expect(repository.setReadCallCount == 1)
        #expect(repository.lastSetReadValue == true)
    }

    /// Nothing arrived, so there is nothing the reader can have read — leaving
    /// it unread is what makes 歷史紀錄's unread state mean anything.
    @Test func doesNotMarkReadWhenTheRecordFinishedWithoutAnExplanation() async throws {
        for status in ["failed", "declined"] {
            let repository = StubComprehensionRepository()
            repository.recordResults = [.success(.stub(status: status))]

            _ = await poll(repository)

            #expect(repository.setReadCallCount == 0)
        }
    }

    /// A failed `PATCH` must never cost the reader the explanation itself.
    @Test func aFailedMarkReadStillReturnsTheExplanation() async throws {
        let repository = StubComprehensionRepository()
        repository.recordResults = [.success(.stub(status: "ok", notes: "…"))]
        repository.enqueueResult = .failure(APIError.httpStatus(500))

        let finished = await poll(repository)

        #expect(finished?.status == .ok)
    }

    // MARK: - What the section shows for a record

    /// `pending` and `running` are deliberately not distinguished: a queue
    /// position is not something the reader can act on.
    @Test func pendingAndRunningBothReadAsOneInProgressState() async throws {
        for status in ["pending", "running", "something-new"] {
            let state = ComprehensionSectionState(record: .stub(status: status))
            #expect(state == .inProgress)
        }
    }

    @Test func okWithNotesShowsTheThreeFields() async throws {
        let state = ComprehensionSectionState(
            record: .stub(status: "ok", notes: "note")
        )

        #expect(
            state == .explained(
                grammarNotes: "note", contextNotes: "note", toneRegister: "note"
            )
        )
    }

    /// A heading with nothing under it is worse than an honest failure, and a
    /// retry is the honest offer.
    @Test func okWithoutAnyNotesIsTreatedAsAFailure() async throws {
        let state = ComprehensionSectionState(record: .stub(status: "ok"))

        #expect(state == .unavailable(.failed))
    }

    /// The split that decides whether a retry appears at all.
    @Test func onlyTheFixableReasonsOfferARetry() async throws {
        #expect(ComprehensionSectionState(record: .stub(status: "failed"))
            == .unavailable(.failed))
        #expect(ComprehensionSectionState(record: .stub(status: "declined"))
            == .unavailable(.declined))

        #expect(ComprehensionSectionState.Reason.failed.allowsRetry)
        #expect(ComprehensionSectionState.Reason.enqueueFailed.allowsRetry)
        #expect(ComprehensionSectionState.Reason.declined.allowsRetry == false)
        #expect(ComprehensionSectionState.Reason.quotaExhausted.allowsRetry == false)
    }

    // MARK: - Display precedence

    @Test func theCloudWordingReplacesTheOnDeviceOneOnceItArrives() async throws {
        let landed = ComprehensionRecord.stub(
            status: "ok", cloudTranslation: "您好", notes: "…"
        )

        #expect(landed.displayedTranslation == "您好")
        #expect(ComprehensionRecord.stub().displayedTranslation == "你好")
    }
}
