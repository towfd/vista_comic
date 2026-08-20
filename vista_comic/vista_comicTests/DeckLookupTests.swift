//
//  DeckLookupTests.swift
//  vista_comicTests
//
//  The already-collected marker (vocabulary-review stage 1, ticket 03).
//
//  Two things are under test, and the first matters far more than it looks.
//
//  **The normalisation vector table is shared verbatim with the backend suite**
//  (`backend/tests/test_learning_cards.py`) and with
//  `.scratch/vocabulary-review/01-card-storage/spec.md`. The rule is
//  implemented twice — once here, once in Python — because the marker has to
//  work with no connection, and the price of that is drift. If the two sides
//  disagree, the app says "not collected" while the server says "duplicate",
//  and the reader sees an add button that never seems to finish. Changing the
//  rule in one place has to fail here.
//
//  The second is the matching itself, which is pure and takes cards, so none of
//  this needs a network seam.
//

import Foundation
import Testing

@testable import vista_comic

@Suite("Normalisation agrees with the backend")
struct TextNormalizationTests {

    /// Input -> expected key. **Copied verbatim** from
    /// `backend/tests/test_learning_cards.py`'s `NORMALISATION_VECTORS`.
    /// Change all three copies together or not at all.
    static let vectors: [(String, String)] = [
        ("大丈夫\nですか", "大丈夫ですか"),
        ("　大丈夫ですか　", "大丈夫ですか"),
        ("ﾀﾞｲｼﾞｮｳﾌﾞ", "ダイジョウブ"),
        ("Good  Morning", "goodmorning"),
        ("good morning", "goodmorning"),
        ("食べた", "食べた"),
        ("食べる", "食べる"),
        ("   ", ""),
    ]

    @Test("Every shared vector produces the key the backend produces", arguments: vectors)
    func sharedVectors(_ vector: (String, String)) {
        #expect(normalizedKey(vector.0) == vector.1)
    }

    @Test("Inflected forms stay distinct")
    func inflectedFormsStayDistinct() {
        // Not a limitation waiting to be fixed. A form the reader can already
        // read is never collected again, so a form that keeps coming back is
        // one they keep failing — and that repetition is the signal worth
        // keeping per form.
        #expect(normalizedKey("食べた") != normalizedKey("食べる"))
    }
}

@Suite("Finding what the reader already collected")
struct DeckLookupTests {

    private let deck = [
        LearningCard.stub(id: 1, sourceText: "大丈夫ですか", translation: "你還好嗎"),
        LearningCard.stub(id: 2, sourceText: "SAU KHI", translation: "之後"),
    ]

    @Test("An exact line is found")
    func exactLineIsFound() {
        let hit = alreadyCollected("大丈夫ですか", targetLanguage: "zh-Hant", in: deck)

        #expect(hit?.id == 1)
    }

    @Test("The line breaks OCR adds do not hide a collected word")
    func lineBreaksDoNotHideAMatch() {
        // The reader framed the same bubble again; the OCR split it differently
        // this time. Same word, and the marker has to say so.
        let hit = alreadyCollected("大丈夫\nですか", targetLanguage: "zh-Hant", in: deck)

        #expect(hit?.id == 1)
    }

    @Test("Half-width and spacing differences do not hide a collected word")
    func widthAndSpacingDoNotHideAMatch() {
        #expect(alreadyCollected("　大丈夫ですか　", targetLanguage: "zh-Hant", in: deck)?.id == 1)
        #expect(alreadyCollected("sau  khi", targetLanguage: "zh-Hant", in: deck)?.id == 2)
    }

    @Test("A word collected for another language is not a match")
    func anotherLanguageIsNotAMatch() {
        // Identity is the key *and* the target language, exactly as the backend
        // enforces it. Claiming a match here would tell the reader they know a
        // card they do not have.
        #expect(alreadyCollected("大丈夫ですか", targetLanguage: "en", in: deck) == nil)
    }

    @Test("A word that was never collected is not a match")
    func anUncollectedWordIsNotAMatch() {
        #expect(alreadyCollected("食べる", targetLanguage: "zh-Hant", in: deck) == nil)
    }

    @Test("An empty deck answers no, rather than anything worse")
    func anEmptyDeckAnswersNo() {
        // The snapshot may be absent, stale, or predate the word. None of that
        // is worth telling the reader about.
        #expect(alreadyCollected("大丈夫ですか", targetLanguage: "zh-Hant", in: []) == nil)
    }

    @Test("Whitespace alone matches nothing")
    func whitespaceMatchesNothing() {
        // Its key is empty, and an empty key must not collide with anything.
        #expect(alreadyCollected("   ", targetLanguage: "zh-Hant", in: deck) == nil)
    }
}

@Suite("The deck snapshot")
struct DeckSnapshotStoreTests {

    private let payload = Data(#"[{"id":1}]"#.utf8)

    @Test("What was stored is what comes back")
    func storedBytesRoundTrip() {
        let store = InMemoryDeckSnapshotStore()

        store.store(payload)

        #expect(store.data() == payload)
    }

    @Test("An empty store answers nil")
    func emptyStoreAnswersNil() {
        #expect(InMemoryDeckSnapshotStore().data() == nil)
    }

    @Test("A later response replaces the earlier one")
    func laterResponseReplacesEarlier() {
        let store = InMemoryDeckSnapshotStore(seed: payload)
        let newer = Data("[]".utf8)

        store.store(newer)

        #expect(store.data() == newer)
    }

    @Test("A file store survives being rebuilt over the same directory")
    func fileStoreSurvivesRebuild() throws {
        // What a relaunch does: a new process, the same directory on disk.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("deck-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileDeckSnapshotStore(root: root).store(payload)

        #expect(try FileDeckSnapshotStore(root: root).data() == payload)
    }

    @Test("Unreadable bytes decode to an empty deck rather than crashing")
    func unreadableBytesAreAnEmptyDeck() {
        // The snapshot is bytes the app cannot vouch for after an upgrade. A
        // marker is never worth a crash, so this degrades to "nothing known".
        let repository = APIStudyRepository(
            snapshots: InMemoryDeckSnapshotStore(seed: Data("not json".utf8))
        )

        #expect(repository.knownCards().isEmpty)
    }

    @Test("An absent snapshot is an empty deck")
    func absentSnapshotIsAnEmptyDeck() {
        #expect(APIStudyRepository(snapshots: InMemoryDeckSnapshotStore()).knownCards().isEmpty)
    }
}
