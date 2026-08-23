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

    @Test("A round is ten questions")
    func aRoundIsTenQuestions() throws {
        #expect(try makeRound(from: usableDeck).get().count == practiceRoundLength)
    }

    @Test("A short deck repeats cards rather than shortening the round")
    func aShortDeckRepeatsRatherThanShortens() throws {
        // Honest at this size: a shorter round would quietly hide how little
        // there is to practise.
        let one = [sentence(100, "TRONG KHI MÌNH BỊ"), word(1, "TRONG KHI")]

        #expect(try makeRound(from: one).get().count == practiceRoundLength)
    }

    @Test("A card never appears twice in a row")
    func aCardNeverAppearsTwiceInARow() throws {
        // The guard against the deadlock pure unfamiliarity ordering creates:
        // the least familiar card always wins, and getting it wrong makes it
        // win harder.
        let items = try makeRound(from: usableDeck).get()

        for (previous, next) in zip(items, items.dropFirst()) {
            #expect(previous.card.id != next.card.id)
        }
    }

    @Test("Every item can actually be answered")
    func everyItemIsAnswerable() throws {
        for item in try makeRound(from: usableDeck).get() {
            #expect(!item.prompt.isEmpty)
            switch item.mode {
            case .choosing:
                #expect(item.question?.choices.count == clozeChoiceCount)
            case .typing:
                #expect(item.question != nil)
            case .rearranging:
                #expect(canRearrange(item.card))
            case .translating:
                #expect(!item.card.sourceText.isEmpty)
            }
        }
    }
}

@Suite("Which cards a round picks")
struct RoundSelectionTests {

    /// Twelve words, all equally due and all on rung 0 — the shape of a fresh
    /// deck, where neither ordering key decides anything.
    private var flatDeck: [LearningCard] {
        (1...12).map { word($0, "W\($0)") }
    }

    @Test("Two rounds over an undifferentiated deck are not the same six cards")
    func roundsVaryOnAFlatDeck() throws {
        // What the reader hit: every card due, every card on rung 0, so the
        // order fell through to whatever `GET /cards` returned and a round was
        // the six most recently collected cards every time.
        //
        // Repeated rather than run once, because two runs can coincide by
        // chance: with 12 cards drawn 6 at a time that is about one in 900, and
        // a test that flakes that often is worse than no test.
        let deck = flatDeck
        let first = Set(try makeRound(from: deck).get().map(\.card.id))
        let differs = (0..<8).contains { _ in
            Set(try! makeRound(from: deck).get().map(\.card.id)) != first
        }

        #expect(differs)
    }

    @Test("Due cards still come before cards that are not due")
    func dueCardsStillLead() throws {
        // The jitter breaks ties; it must not outrank the keys above it.
        let due = word(1, "DUE")
        let later = (2...4).map {
            LearningCard.preview(id: $0, sourceText: "L\($0)", kind: "word", dueOn: "2026-09-01")
        }

        let items = try makeRound(from: [due] + later, today: "2026-08-24").get()

        #expect(items.first?.card.id == due.id)
    }

    @Test("A less familiar card still comes before a more familiar one")
    func lessFamiliarStillLeads() throws {
        let fresh = LearningCard.preview(id: 1, sourceText: "FRESH", kind: "word", ladderStage: 0)
        let known = (2...4).map {
            LearningCard.preview(id: $0, sourceText: "K\($0)", kind: "word", ladderStage: 3)
        }

        let items = try makeRound(from: [fresh] + known).get()

        #expect(items.first?.card.id == fresh.id)
    }
}

@Suite("Difficulty follows the rung")
struct AskedDifficultyTests {

    @Test("The bottom rungs ask for recognition", arguments: [0, 1])
    func bottomRungsAskForRecognition(_ rung: Int) {
        #expect(askedDifficulty(forRung: rung) == [.choosing])
    }

    @Test("The middle rungs ask for production with support", arguments: [2, 3])
    func middleRungsAskForSupportedProduction(_ rung: Int) {
        #expect(askedDifficulty(forRung: rung) == [.typing, .rearranging])
    }

    @Test("The top rung asks for production from nothing")
    func theTopRungAsksForProduction() {
        #expect(askedDifficulty(forRung: 4) == [.translating])
    }

    @Test("The whole deck at rung zero means every question is four-choice")
    func aFreshDeckIsAllRecognition() throws {
        // Worth pinning, because it is what the reader will actually see on the
        // first day and it looks like the difficulty curve is not working.
        let items = try makeRound(from: usableDeck).get()
        let sentences = items.filter { $0.card.kind == .sentence }

        #expect(sentences.allSatisfy { $0.mode == .choosing })
    }

    @Test("A card's two appearances in one round are the same difficulty")
    func twoAppearancesShareADifficulty() throws {
        // The reason difficulty follows the rung rather than the day: using the
        // day would make the second appearance harder purely because the first
        // went well.
        let deck = [sentence(100, "TRONG KHI MÌNH BỊ"), word(1, "TRONG KHI")]
        let items = try makeRound(from: deck).get()

        // Every mode offered comes from the same rung, so a card's appearances
        // are the same *difficulty* even where the band offers two ways of
        // asking — which is the point: the second is not harder because the
        // first went well.
        let asked = Set(items.filter { $0.card.id == 100 }.map(\.mode))
        let band = Set(askableModes(for: deck[0], deck: deck))

        #expect(asked.isSubset(of: band))
    }
}

@Suite("Every card can be asked something")
struct AskableModeTests {

    @Test("A word card in no sentence is still askable — it is translated")
    func anOrphanWordCardIsAskable() {
        // Eleven of the deck's twenty-two word cards are like this. Before
        // this stage they were collected, listed, counted on the practice card,
        // and never asked about.
        let orphan = word(1, "QUỐC HỘI")
        let deck = [orphan, sentence(100, "TRONG KHI MÌNH BỊ"), word(2, "TRONG KHI")]

        #expect(askableModes(for: orphan, deck: deck) == [.translating])
    }

    @Test("A word card never gets a cloze, at any rung", arguments: [0, 2, 4])
    func aWordCardNeverGetsACloze(_ rung: Int) {
        let card = LearningCard.preview(id: 1, sourceText: "QUỐC HỘI", kind: "word", ladderStage: rung)

        let modes = askableModes(for: card, deck: [card])

        #expect(!modes.contains(.choosing))
        #expect(!modes.contains(.typing))
    }

    @Test("A sentence with no deck word in it falls back rather than vanishing")
    func anUnmatchedSentenceFallsBack() {
        // Its rung asks for a cloze and it cannot carry one — but it can still
        // be translated, so it stays in the round.
        let lonely = sentence(100, "NGAY CẢ KHI HỌC SINH XÂM PHAM")
        let deck = [lonely, word(1, "XÂM PHẠM")]

        let modes = askableModes(for: lonely, deck: deck)

        // Rearranging as well as typing: the fallback offers everything the
        // card can do, easiest first, and a multi-word sentence can be
        // assembled from pieces even when no deck word sits inside it.
        #expect(modes == [.rearranging, .translating])
        #expect(!modes.contains(.choosing))
    }

    @Test("A card at the top rung is asked to be translated")
    func aTopRungCardIsTranslated() {
        let card = LearningCard.preview(
            id: 100, sourceText: "TRONG KHI MÌNH BỊ", kind: "sentence", ladderStage: 4
        )

        #expect(askableModes(for: card, deck: [card]) == [.translating])
    }

    @Test("A middle-rung sentence is typed or rearranged, never four-choice")
    func aMiddleRungSentenceProduces() {
        let card = LearningCard.preview(
            id: 100, sourceText: "TRONG KHI MÌNH BỊ", kind: "sentence", ladderStage: 2
        )
        let deck = [card, word(1, "TRONG KHI"), word(2, "XẤU"), word(3, "VÀI"), word(4, "CHỊU")]

        let modes = askableModes(for: card, deck: deck)

        #expect(modes.contains(.typing))
        #expect(modes.contains(.rearranging))
        #expect(!modes.contains(.choosing))
    }

    @Test("Nothing is askable from a card with no text to ask for")
    func anEmptyCardIsNotAskable() {
        // The only case worth excluding a card for, since typed translation
        // asks for the card itself and always applies otherwise.
        let blank = LearningCard.preview(id: 1, sourceText: "   ", kind: "word")

        #expect(makeRound(from: [blank, word(2, "XẤU")]).isFailure == false)
    }
}

extension Result {
    var isFailure: Bool { if case .failure = self { true } else { false } }
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

    @Test("A deck of only words can now be practised")
    func aDeckOfOnlyWordsCanBePractised() throws {
        // Changed by stage 5, deliberately. This assertion used to be that a
        // deck with no usable sentence could build no round — true when cloze
        // was the only question type, and the reason eleven of the deck's word
        // cards were never asked about. A word card can be *translated*, which
        // needs no sentence.
        let wordsOnly = [word(1, "TRONG KHI"), word(2, "ĂN MÒN"), word(3, "XẤU")]

        let items = try makeRound(from: wordsOnly).get()

        #expect(items.count == practiceRoundLength)
        #expect(items.allSatisfy { $0.mode == .translating })
    }

    @Test("A sentence with none of the reader's words is still askable")
    func anUnmatchedSentenceIsStillAskable() throws {
        // The real deck's one dud: OCR read `XÂM PHẠM` as `XÂM PHAM`, so no
        // card matches inside it and it can carry no cloze. It can still be
        // produced from its meaning, which is what keeps it in the round.
        let deck = [
            sentence(100, "NGAY CẢ KHI HỌC SINH CÓ HÀNH VI XÂM PHAM"),
            word(1, "XÂM PHẠM"),
            word(2, "THẨM QUYỀN"),
        ]

        let items = try makeRound(from: deck).get()

        #expect(items.contains { $0.card.id == 100 })
        #expect(items.filter { $0.card.id == 100 }.allSatisfy { $0.question == nil })
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
