//
//  PracticeRoundTests.swift
//  vista_comicTests
//
//  What a card can be asked, and how a session reports itself.
//
//  **Rewritten for stage 6.** What used to be here tested `makeRound` — ten
//  questions, a difficulty band per rung, and two refusal cases. A session has
//  no length now and no difficulty curve, so those suites did not survive; what
//  they were really protecting, that a card is only ever asked something it can
//  actually carry, is below and is unchanged.
//

import Foundation
import Testing

@testable import vista_comic

private func word(_ id: Int, _ text: String) -> LearningCard {
    .preview(id: id, sourceText: text, kind: "word")
}

private func sentence(_ id: Int, _ text: String) -> LearningCard {
    .preview(id: id, sourceText: text, kind: "sentence")
}

/// A deck big enough to build four-choice questions from.
private let usableDeck: [LearningCard] = [
    sentence(100, "TRONG KHI MÌNH BỊ TẾ BÀO UNG THƯ ĂN MÒN"),
    sentence(101, "TÌNH HÌNH XẤU LẮM"),
    word(1, "TRONG KHI"), word(2, "ĂN MÒN"), word(3, "TÌNH HÌNH"),
    word(4, "XẤU"), word(5, "VÀI"), word(6, "CHỊU"),
]

@Suite("What a card can be asked")
struct AskableModeTests {

    @Test("A word card in no sentence is still askable — it is translated")
    func anOrphanWordCardIsAskable() {
        // Eleven of the deck's twenty-two word cards are like this. Before
        // stage 5 they were collected, listed, counted on the practice card,
        // and never asked about.
        let orphan = word(1, "QUỐC HỘI")
        let deck = [orphan, sentence(100, "TRONG KHI MÌNH BỊ"), word(2, "TRONG KHI")]

        #expect(askableModes(for: orphan, deck: deck) == [.translating])
    }

    @Test("A word card never gets a cloze, whatever its slot", arguments: [0, 2, 6])
    func aWordCardNeverGetsACloze(_ slot: Int) {
        // The slot used to decide the band and therefore the modes. It decides
        // nothing here now, which is what this argument list is checking.
        let card = LearningCard.preview(
            id: 1, sourceText: "QUỐC HỘI", kind: "word", ladderStage: slot
        )

        let modes = askableModes(for: card, deck: [card])

        #expect(!modes.contains(.choosing))
        #expect(!modes.contains(.typing))
    }

    @Test("A sentence with no deck word in it falls back rather than vanishing")
    func anUnmatchedSentenceFallsBack() {
        // The real deck's one dud: OCR read `XÂM PHẠM` as `XÂM PHAM`, so no
        // card matches inside it and it can carry no cloze. It can still be
        // produced, which is what keeps it askable.
        let lonely = sentence(100, "NGAY CẢ KHI HỌC SINH XÂM PHAM")
        let deck = [lonely, word(1, "XÂM PHẠM")]

        let modes = askableModes(for: lonely, deck: deck)

        #expect(modes == [.rearranging, .translating])
    }

    @Test("A sentence carrying a deck word offers all four")
    func aUsableSentenceOffersEverything() throws {
        let card = try #require(usableDeck.first { $0.id == 100 })

        let modes = askableModes(for: card, deck: usableDeck)

        #expect(modes == [.choosing, .typing, .rearranging, .translating])
    }

    @Test("A card's slot changes nothing about what it can be asked")
    func theSlotDoesNotFilterAnything() {
        // The whole of what stage 6 removed here, pinned so it cannot creep
        // back: the reader asked for random question types precisely because a
        // curve kept the harder ones out of reach.
        let low = LearningCard.preview(
            id: 100, sourceText: "TRONG KHI MÌNH BỊ", kind: "sentence", ladderStage: 0
        )
        let high = LearningCard.preview(
            id: 100, sourceText: "TRONG KHI MÌNH BỊ", kind: "sentence", ladderStage: 6
        )
        let deck = [low, word(1, "TRONG KHI"), word(2, "XẤU"), word(3, "VÀI"), word(4, "CHỊU")]

        #expect(askableModes(for: low, deck: deck) == askableModes(for: high, deck: deck))
    }

    @Test("Every card can be asked something, so none is ever skipped")
    func nothingIsUnaskable() {
        // Typed translation asks for the card itself, so the list is never
        // empty — which is what lets the queue treat every card as fair game
        // instead of having to filter first.
        let blank = LearningCard.preview(id: 1, sourceText: "   ", kind: "word")

        #expect(!askableModes(for: blank, deck: [blank]).isEmpty)
        #expect(usableDeck.allSatisfy { !askableModes(for: $0, deck: usableDeck).isEmpty })
    }
}

@Suite("How a session went")
struct RoundOutcomeTests {

    @Test("It reports cards learned, not answers right")
    func itReportsCardsLearned() {
        // The figure that means something. A session can be answered perfectly
        // and graduate nothing — if every card was met once — and a reader told
        // "10 / 10" would reasonably think they had finished something.
        var outcome = RoundOutcome()
        outcome.record(correct: true, cardID: 1, state: .learning)
        outcome.record(correct: true, cardID: 2, state: .learning)

        #expect(outcome.correct == 2)
        #expect(outcome.graduated.isEmpty)
    }

    @Test("A card that graduates is counted once, however many answers it took")
    func aGraduatedCardIsCountedOnce() {
        var outcome = RoundOutcome()
        outcome.record(correct: true, cardID: 1, state: .learning)
        outcome.record(correct: true, cardID: 1, state: .review)
        outcome.record(correct: true, cardID: 1, state: .review)

        #expect(outcome.graduated == [1])
    }

    @Test("A card that lapses is no longer claimed")
    func aLapsedCardIsNotClaimed() {
        // It can happen inside one session, now that learn-ahead can bring a
        // card back within twenty minutes. The summary must not still be saying
        // it is done.
        var outcome = RoundOutcome()
        outcome.record(correct: true, cardID: 1, state: .review)
        outcome.record(correct: false, cardID: 1, state: .relearning)

        #expect(outcome.graduated.isEmpty)
    }

    @Test("An unreachable backend leaves the count honest rather than optimistic")
    func anUnrecordedAnswerClaimsNothing() {
        // A failed submission falls back to the state the card already had.
        // Counting it as a graduation would tell the reader they finished
        // something the server never heard about.
        var outcome = RoundOutcome()
        outcome.record(correct: true, cardID: 1, state: .new)

        #expect(outcome.correct == 1)
        #expect(outcome.graduated.isEmpty)
    }

    @Test("Wrong answers are still counted as answers")
    func wrongAnswersAreCounted() {
        var outcome = RoundOutcome()
        outcome.record(correct: true, cardID: 1, state: .learning)
        outcome.record(correct: false, cardID: 2, state: .learning)

        #expect(outcome.total == 2)
        #expect(outcome.allCorrect == false)
    }

    @Test("An untouched session claims nothing")
    func anUntouchedSessionClaimsNothing() {
        // Zero wrong out of zero answered is easy to write as a perfect score,
        // and the reader would open the tab to be congratulated for nothing.
        #expect(RoundOutcome().allCorrect == false)
        #expect(RoundOutcome().graduated.isEmpty)
    }
}

@Suite("What the entry card says")
struct DeckSummaryTests {

    @Test("It counts words and sentences separately")
    func itCountsWordsAndSentencesSeparately() {
        let deck = [
            sentence(100, "TRONG KHI MÌNH BỊ"), sentence(101, "TÌNH HÌNH XẤU"),
            word(1, "TRONG KHI"), word(2, "XẤU"), word(3, "VÀI"),
        ]

        let summary = DeckSummary(deck: deck)

        #expect(summary.words == 3)
        #expect(summary.sentences == 2)
    }

    @Test("Only sentences that can carry a blank count as ready")
    func onlyUsableSentencesCountAsReady() {
        // The figure on the card has to mean "you can practise this many",
        // not "you own this many" — the real deck holds a sentence card OCR
        // mangled beyond matching, and counting it would promise a question
        // that never appears.
        let deck = [
            sentence(100, "TRONG KHI MÌNH BỊ"),
            sentence(101, "NGAY CẢ KHI HỌC SINH XÂM PHAM"),
            word(1, "TRONG KHI"),
            word(2, "XÂM PHẠM"),
        ]

        let summary = DeckSummary(deck: deck)

        #expect(summary.sentences == 2)
        #expect(summary.usableSentences == 1)
    }

    @Test("Blanks are counted across every usable sentence")
    func blanksAreCountedAcrossSentences() {
        let deck = [
            sentence(100, "TRONG KHI MÌNH BỊ TẾ BÀO UNG THƯ ĂN MÒN"),
            word(1, "TRONG KHI"), word(2, "ĂN MÒN"),
        ]

        #expect(DeckSummary(deck: deck).availableBlanks == 2)
    }

    @Test("An empty deck reports zeroes rather than crashing")
    func anEmptyDeckReportsZeroes() {
        let summary = DeckSummary(deck: [])

        #expect(summary.words == 0)
        #expect(summary.usableSentences == 0)
        #expect(summary.availableBlanks == 0)
    }

    @Test("Unclassified cards are counted as neither")
    func unclassifiedCardsAreCountedAsNeither() {
        // Cards predating the two save buttons have no kind, and guessing one
        // for a figure on a card would be the same invention the buttons exist
        // to avoid.
        let deck = [LearningCard.preview(id: 1, sourceText: "SAU KHI", kind: nil)]

        let summary = DeckSummary(deck: deck)

        #expect(summary.words == 0)
        #expect(summary.sentences == 0)
    }
}
