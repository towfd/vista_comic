//
//  PracticeRoundTests.swift
//  vista_comicTests
//
//  Building a round (vocabulary stage 3, ticket 03).
//
//  The interesting assertions here are about **refusals**: a round that cannot
//  be built has to say which of two problems the reader has, because "collect
//  more words" and "collect a sentence" send them to different actions, and the
//  wrong one wastes their time. With a 30-card deck holding 7 sentences, only
//  one of which OCR mangled, both cases are live.
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

@Suite("Building a round")
struct PracticeRoundTests {

    @Test("A round is five questions")
    func aRoundIsFiveQuestions() throws {
        let items = try makeRound(from: usableDeck).get()

        #expect(items.count == practiceRoundLength)
    }

    @Test("A round exercises both ways of answering")
    func aRoundUsesBothAnswerModes() throws {
        // Alternating rather than random: nothing yet knows how familiar a card
        // is, so nothing can choose — and a random pick would sometimes give
        // five of one, leaving an interface untested.
        let items = try makeRound(from: usableDeck).get()

        #expect(items.contains { $0.mode == .choosing })
        #expect(items.contains { $0.mode == .typing })
    }

    @Test("A question with too small a deck behind it is typed, whatever the alternation says")
    func aQuestionWithoutChoicesIsTyped() throws {
        // Two cards can make a question but not four options. Showing two and
        // calling it a choice would be worse than asking them to type.
        let small = [sentence(100, "TRONG KHI MÌNH BỊ"), word(1, "TRONG KHI")]

        let items = try makeRound(from: small).get()

        #expect(items.allSatisfy { $0.mode == .typing })
    }

    @Test("A short deck repeats cards rather than shortening the round")
    func aShortDeckRepeatsRatherThanShortens() throws {
        // Honest at this size: a shorter round would quietly hide how little
        // there is to practise.
        let one = [sentence(100, "TRONG KHI MÌNH BỊ"), word(1, "TRONG KHI")]

        let items = try makeRound(from: one).get()

        #expect(items.count == practiceRoundLength)
        #expect(Set(items.map(\.question.card.id)) == [100])
    }

    @Test("Every item is answerable")
    func everyItemIsAnswerable() throws {
        let items = try makeRound(from: usableDeck).get()

        for item in items {
            #expect(!item.question.prompt.isEmpty)
            #expect(!item.question.removed.isEmpty)
            // A blank must actually be a blank — the prompt cannot still
            // contain the word it is asking for.
            #expect(item.question.prompt.contains("____"))
            if item.mode == .choosing {
                #expect(item.question.choices.count == clozeChoiceCount)
            }
        }
    }
}

@Suite("When a round cannot be built")
struct RoundUnavailableTests {

    @Test("An empty deck asks for words, and says how many")
    func anEmptyDeckAsksForWords() {
        #expect(makeRound(from: []) == .failure(.tooFewCards(needed: 2)))
    }

    @Test("One card asks for one more")
    func oneCardAsksForOneMore() {
        #expect(makeRound(from: [word(1, "TRONG KHI")]) == .failure(.tooFewCards(needed: 1)))
    }

    @Test("Cards but no usable sentence is a different problem, worded differently")
    func noUsableSentenceIsItsOwnProblem() {
        // This reader has plenty of words. Telling them to collect more would
        // send them to the wrong action — what they lack is a sentence holding
        // a word they already have.
        let wordsOnly = [word(1, "TRONG KHI"), word(2, "ĂN MÒN"), word(3, "XẤU")]

        #expect(makeRound(from: wordsOnly) == .failure(.noSentencesWithKnownWords))
    }

    @Test("A sentence with none of the reader's words is not usable")
    func anUnrelatedSentenceIsNotUsable() {
        // Exactly the real deck's one dud: OCR read `XÂM PHẠM` as `XÂM PHAM`,
        // so nothing in it matches a card.
        let deck = [
            sentence(100, "NGAY CẢ KHI HỌC SINH CÓ HÀNH VI XÂM PHAM"),
            word(1, "XÂM PHẠM"),
            word(2, "THẨM QUYỀN"),
        ]

        #expect(makeRound(from: deck) == .failure(.noSentencesWithKnownWords))
    }
}

@Suite("How a round went")
struct RoundOutcomeTests {

    @Test("It reports cards passed, not answers right")
    func itReportsCardsPassed() {
        // The figure that means something. A round can be answered perfectly
        // and pass nothing — if every card was seen once — and a reader told
        // "10 / 10" would reasonably think they had finished something.
        var outcome = RoundOutcome()
        outcome.record(correct: true, cardID: 1, step: .familiar)
        outcome.record(correct: true, cardID: 2, step: .familiar)

        #expect(outcome.correct == 2)
        #expect(outcome.passed.isEmpty)
    }

    @Test("A card that reaches 通過 is counted once, however many answers it took")
    func aPassedCardIsCountedOnce() {
        var outcome = RoundOutcome()
        outcome.record(correct: true, cardID: 1, step: .familiar)
        outcome.record(correct: true, cardID: 1, step: .passed)
        outcome.record(correct: true, cardID: 1, step: .passed)

        #expect(outcome.passed == [1])
    }

    @Test("A card that falls back out of 通過 is no longer claimed")
    func aCardThatFallsBackIsNotClaimed() {
        // It can happen inside one round: pass a card, then meet it again in
        // the other answer mode and miss it. The summary must not still be
        // saying it is done.
        var outcome = RoundOutcome()
        outcome.record(correct: true, cardID: 1, step: .familiar)
        outcome.record(correct: true, cardID: 1, step: .passed)
        outcome.record(correct: false, cardID: 1, step: .unfamiliar)

        #expect(outcome.passed.isEmpty)
    }

    @Test("An unreachable backend leaves the count honest rather than optimistic")
    func anUnknownStepCountsNothing() {
        // A failed submission yields `.unknown`. Counting it as a pass would
        // tell the reader they finished something the server never heard about.
        var outcome = RoundOutcome()
        outcome.record(correct: true, cardID: 1, step: .unknown)

        #expect(outcome.correct == 1)
        #expect(outcome.passed.isEmpty)
    }

    @Test("Wrong answers are still counted as answers")
    func wrongAnswersAreCounted() {
        var outcome = RoundOutcome()
        outcome.record(correct: true, cardID: 1, step: .familiar)
        outcome.record(correct: false, cardID: 2, step: .unfamiliar)

        #expect(outcome.total == 2)
        #expect(outcome.allCorrect == false)
    }

    @Test("An untouched round claims nothing")
    func anUntouchedRoundClaimsNothing() {
        // Zero wrong out of zero answered is easy to write as a perfect score,
        // and the reader would open the tab to be congratulated for nothing.
        #expect(RoundOutcome().allCorrect == false)
        #expect(RoundOutcome().passed.isEmpty)
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
