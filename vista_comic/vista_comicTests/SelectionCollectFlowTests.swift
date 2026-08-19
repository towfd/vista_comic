//
//  SelectionCollectFlowTests.swift
//  vista_comicTests
//
//  Exercises `collectSelection(...)`, the free function the result sheet's
//  "加入單字庫" action runs (vocabulary-review stage 1, ticket 02).
//
//  The behaviour worth pinning down here is *what reaches the card*, not
//  whether a POST happens. Two things carry meaning and are easy to get quietly
//  wrong: the source text must be the reader's corrected version rather than the
//  raw recognition, and the translation must be the wording that was on screen
//  when they pressed add — the cloud's if they waited for an explanation, the
//  on-device one if they did not. Both are the reader's judgement, and that
//  judgement is the whole quality gate this feature rests on.
//
//  Stubs `StudyRepository` so nothing touches the network.
//

import Foundation
import Testing

@testable import vista_comic

/// Records what it was asked to collect and returns (or throws) what the test
/// tells it to.
private final class StubStudyRepository: StudyRepository, @unchecked Sendable {
    var collectResult: Result<CollectOutcome, Error> = .success(.collected(.stub()))
    private(set) var collectCallCount = 0
    private(set) var lastSourceText: String?
    private(set) var lastTranslation: String?
    private(set) var lastTargetLanguage: String?
    private(set) var lastComicID: String?
    private(set) var lastChapterID: String?
    private(set) var lastPageNumber: Int?

    func collect(
        sourceText: String,
        translation: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int
    ) async throws -> CollectOutcome {
        collectCallCount += 1
        lastSourceText = sourceText
        lastTranslation = translation
        lastTargetLanguage = targetLanguage
        lastComicID = comicID
        lastChapterID = chapterID
        lastPageNumber = pageNumber
        return try collectResult.get()
    }

    var cardsResult: [LearningCard] = []
    private(set) var cardsCallCount = 0
    func cards() async throws -> [LearningCard] {
        cardsCallCount += 1
        return cardsResult
    }

    var known: [LearningCard] = []
    func knownCards() -> [LearningCard] { known }

    private(set) var recordLookupCallCount = 0
    func recordLookup(id: Int) async throws { recordLookupCallCount += 1 }
}

extension LearningCard {
    /// Built by decoding, so the stub exercises the real `CodingKeys` — which
    /// is where a backend contract drift would actually show up.
    static func stub(
        id: Int = 1,
        sourceText: String = "大丈夫ですか",
        translation: String = "你還好嗎",
        lookupCount: Int = 0
    ) -> LearningCard {
        let json = """
        {
            "id": \(id),
            "sourceText": "\(sourceText)",
            "translation": "\(translation)",
            "targetLanguage": "zh-Hant",
            "comicId": "comic-1",
            "chapterId": "chapter-1",
            "pageNumber": 3,
            "ladderStage": 0,
            "dueOn": "2026-08-19",
            "lookupCount": \(lookupCount),
            "lastLookedUpAt": null,
            "createdAt": "2026-08-19T10:30:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(LearningCard.self, from: Data(json.utf8))
    }
}

@Suite("Selection → add to vocabulary")
struct SelectionCollectFlowTests {

    private func collect(
        repository: StubStudyRepository,
        sourceText: String = "大丈夫ですか",
        translation: String = "你還好嗎"
    ) async -> CollectionOutcome {
        await collectSelection(
            sourceText: sourceText,
            translation: translation,
            targetLanguageCode: "zh-Hant",
            comicID: "comic-1",
            chapterID: "chapter-1",
            pageNumber: 3,
            repository: repository
        )
    }

    @Test("A collected line comes back as a card")
    func collectedLineReturnsACard() async {
        let repository = StubStudyRepository()
        repository.collectResult = .success(.collected(.stub(id: 42)))

        let outcome = await collect(repository: repository)

        #expect(outcome == .collected(.stub(id: 42)))
        #expect(repository.collectCallCount == 1)
    }

    @Test("The card carries the source reference the reader selected from")
    func cardCarriesTheSourceReference() async {
        let repository = StubStudyRepository()

        _ = await collect(repository: repository)

        #expect(repository.lastComicID == "comic-1")
        #expect(repository.lastChapterID == "chapter-1")
        #expect(repository.lastPageNumber == 3)
        #expect(repository.lastTargetLanguage == "zh-Hant")
    }

    @Test("The corrected text is what gets collected, not the raw recognition")
    func correctedTextIsWhatGetsCollected() async {
        let repository = StubStudyRepository()

        _ = await collect(repository: repository, sourceText: "大丈夫ですか")

        // The caller passes `editedText`; there is no path here that could
        // reach the recognition result instead.
        #expect(repository.lastSourceText == "大丈夫ですか")
    }

    @Test("Whatever translation was on screen is the one stored")
    func theOnScreenTranslationIsStored() async {
        let repository = StubStudyRepository()

        // The cloud wording, as it would be after waiting for an explanation.
        _ = await collect(repository: repository, translation: "你還好嗎？")

        #expect(repository.lastTranslation == "你還好嗎？")
    }

    @Test("A line already in the deck is collected, not an error")
    func anAlreadyCollectedLineIsStillCollected() async {
        // The backend answers 200 with the existing card for a duplicate, so
        // the repository returns rather than throws — and from the reader's
        // side "it is in your vocabulary" is the same fact either way.
        let repository = StubStudyRepository()
        repository.collectResult = .success(.collected(.stub(id: 7, lookupCount: 3)))

        let outcome = await collect(repository: repository)

        #expect(outcome == .collected(.stub(id: 7, lookupCount: 3)))
    }

    @Test("A failure leaves nothing collected and is not a thrown error")
    func aFailureIsReportedAsNotCollected() async {
        let repository = StubStudyRepository()
        repository.collectResult = .failure(APIError.httpStatus(500))

        let outcome = await collect(repository: repository)

        #expect(outcome == .notCollected)
    }

    @Test("Collecting never spends a comprehension request")
    func collectingNeverSpendsARequest() async {
        // Structural rather than asserted on a mock: `collectSelection` takes a
        // `StudyRepository` and nothing else, so there is no route from adding
        // a word to the daily Claude budget. This test exists to fail if that
        // signature ever grows a `ComprehensionRepository`.
        let repository = StubStudyRepository()

        _ = await collect(repository: repository)

        #expect(repository.recordLookupCallCount == 0)
    }
}

@Suite("Learning card decoding")
struct LearningCardDecodingTests {

    @Test("The backend's card shape decodes 1:1")
    func decodesTheBackendShape() throws {
        let card = LearningCard.stub(id: 9, sourceText: "食べる", lookupCount: 2)

        #expect(card.id == 9)
        #expect(card.sourceText == "食べる")
        #expect(card.comicID == "comic-1")
        #expect(card.chapterID == "chapter-1")
        #expect(card.pageNumber == 3)
        #expect(card.ladderStage == 0)
        #expect(card.lookupCount == 2)
        #expect(card.lastLookedUpAt == nil)
    }

    @Test("dueOn stays a date string rather than becoming an instant")
    func dueOnStaysADateString() throws {
        // A scheduling day is not a moment; decoding it as a `Date` would
        // invent a timezone the backend never chose. Stage 3 reads this.
        #expect(LearningCard.stub().dueOn == "2026-08-19")
    }
}
