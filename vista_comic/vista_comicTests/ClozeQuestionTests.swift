//
//  ClozeQuestionTests.swift
//  vista_comicTests
//
//  Turning a card into a question, or deciding it cannot be one (vocabulary
//  stage 3, ticket 02).
//
//  Two of the cases here are not hypothetical: the developer's own deck holds
//  three near-identical copies of one sentence, which is exactly what breaks a
//  naive builder — a sentence matching itself blanks the whole prompt, and a
//  near-duplicate used as a distractor makes the question unanswerable.
//

import Foundation
import Testing

@testable import vista_comic

private func word(_ id: Int, _ text: String, ladderStage: Int = 0) -> LearningCard {
    .preview(id: id, sourceText: text, kind: "word", ladderStage: ladderStage)
}

private func sentence(_ id: Int, _ text: String) -> LearningCard {
    .preview(id: id, sourceText: text, kind: "sentence")
}

@Suite("Building a cloze")
struct ClozeBuildingTests {

    private let line = sentence(100, "TRONG KHI MÌNH BỊ TẾ BÀO UNG THƯ ĂN MÒN")

    @Test("A sentence containing a deck word becomes a question")
    func aSentenceWithADeckWordBecomesAQuestion() {
        let deck = [line, word(1, "TRONG KHI"), word(2, "ĂN MÒN"), word(3, "XẤU"), word(4, "VÀI")]

        let cloze = makeCloze(from: line, deck: deck)

        #expect(cloze != nil)
        #expect(cloze?.prompt == "____ MÌNH BỊ TẾ BÀO UNG THƯ ĂN MÒN")
        #expect(cloze?.removed == "TRONG KHI")
    }

    @Test("The least familiar word present is the one removed")
    func theLeastFamiliarWordIsRemoved() {
        // Reuses the familiarity the deck already tracks rather than inventing
        // a second idea of what needs practice.
        let deck = [
            line,
            word(1, "TRONG KHI", ladderStage: 3),
            word(2, "ĂN MÒN", ladderStage: 0),
        ]

        #expect(makeCloze(from: line, deck: deck)?.removed == "ĂN MÒN")
    }

    @Test("Equally familiar words break the tie on position, so the choice is stable")
    func tiesBreakOnPosition() {
        // Every card sits on rung 0 until stage 4 ships, so *everything* ties.
        // Without a second key the blank would move between runs and no test
        // could state where it lands.
        let deck = [line, word(1, "TRONG KHI"), word(2, "ĂN MÒN")]

        #expect(makeCloze(from: line, deck: deck)?.removed == "TRONG KHI")
    }

    @Test("A sentence with none of the reader's words yields no question")
    func noDeckWordYieldsNoQuestion() {
        // Not an error: the round takes another card. With a small deck this is
        // ordinary — one of the seven sentence cards in the real deck is like
        // this, because OCR misread a tone.
        #expect(makeCloze(from: line, deck: [line, word(1, "食べる")]) == nil)
    }

    @Test("A word card yields no question")
    func aWordCardYieldsNoQuestion() {
        // It has no sentence to blank. Generating one is a later stage.
        let card = word(1, "TRONG KHI")

        #expect(makeCloze(from: card, deck: [card, sentence(2, "TRONG KHI MÌNH BỊ")]) == nil)
    }

    @Test("An unclassified card yields no question")
    func anUnclassifiedCardYieldsNoQuestion() {
        // Cards predating the two save buttons have no kind. Guessing one here
        // would undo the point of having asked.
        let card = LearningCard.preview(id: 1, sourceText: "TRONG KHI MÌNH BỊ", kind: nil)

        #expect(makeCloze(from: card, deck: [card, word(2, "TRONG KHI")]) == nil)
    }

    @Test("A sentence never blanks itself")
    func aSentenceNeverBlanksItself() {
        // The real deck holds three near-identical copies of one sentence, so
        // without excluding the card itself a question could come out as one
        // enormous blank.
        let deck = [line, sentence(101, "TRONG KHI MÌNH BỊ TẾ BÀO UNG THƯ ĂN MÒN")]

        #expect(makeCloze(from: line, deck: deck) == nil)
    }
}

@Suite("Choosing distractors")
struct ClozeDistractorTests {

    private let answer = word(1, "TRONG KHI")

    @Test("Distractors come from the reader's own cards, and never repeat")
    func distractorsAreOtherCards() {
        let deck = [answer, word(2, "ĂN MÒN"), word(3, "XẤU"), word(4, "VÀI")]

        let options = distractors(for: answer, from: deck, count: 3)

        #expect(options.count == 3)
        #expect(!options.contains { $0.id == answer.id })
        #expect(Set(options.map(\.id)).count == 3)
    }

    @Test("A card equal to the answer after normalisation is never a distractor")
    func aNearDuplicateIsNeverADistractor() {
        // The real deck holds cards differing only in spacing and case. Offered
        // as a distractor, the question would have two right answers.
        let deck = [answer, word(2, "trong  khi"), word(3, "XẤU"), word(4, "VÀI")]

        let options = distractors(for: answer, from: deck, count: 3)

        #expect(options.isEmpty)
    }

    @Test("A whole sentence is never offered as an option")
    func aSentenceIsNeverAnOption() {
        // What the reader actually saw: a two-syllable blank with a
        // ten-syllable line among the four answers. It gives itself away by
        // shape before a word of it has been read, and it reads as a bug.
        let line = sentence(100, "TRONG KHI MÌNH BỊ TẾ BÀO UNG THƯ ĂN MÒN")
        let deck = [answer, line, word(2, "ĂN MÒN"), word(3, "XẤU"), word(4, "VÀI")]

        let options = distractors(for: answer, from: deck, count: 3)

        #expect(options.count == 3)
        #expect(!options.contains { $0.id == line.id })
    }

    @Test("A cloze built from a deck of sentences offers no choices at all")
    func aSentenceOnlyDeckOffersNoChoices() {
        // Rather than falling back to offering them anyway. An unanswerable
        // four-option question is worse than a typed one, and the fallback in
        // `askableModes` already has somewhere to go.
        let line = sentence(100, "TRONG KHI MÌNH BỊ TẾ BÀO UNG THƯ ĂN MÒN")
        let deck = [
            answer, line,
            sentence(101, "TÌNH HÌNH XẤU LẮM"),
            sentence(102, "NGAY CẢ KHI HỌC SINH CÓ HÀNH VI"),
        ]

        #expect(distractors(for: answer, from: deck, count: 3).isEmpty)
    }

    @Test("A one-syllable answer still has a pool to draw from")
    func aShortAnswerStillHasAPool() {
        // Six of the deck's word cards are one syllable. Without the floor, an
        // answer that short would admit only other one-syllable cards and most
        // of its questions would lose their options.
        let short = word(1, "VÀI")
        let deck = [short, word(2, "ĂN MÒN"), word(3, "TÌNH HÌNH"), word(4, "TRONG KHI")]

        #expect(distractors(for: short, from: deck, count: 3).count == 3)
    }

    @Test("Options are counted in pieces, and Vietnamese counts syllables")
    func piecesAreSyllables() {
        #expect(pieceCount("XẤU") == 1)
        #expect(pieceCount("TRONG KHI") == 2)
        #expect(pieceCount("  TÌNH   HÌNH XẤU LẮM ") == 4)
    }

    @Test("Too few cards means no choice question rather than a two-option one")
    func tooFewCardsMeansNoChoiceQuestion() {
        let deck = [answer, word(2, "ĂN MÒN")]

        #expect(distractors(for: answer, from: deck, count: 3).isEmpty)
    }

    @Test("A question with no distractors offers no choices")
    func noDistractorsMeansNoChoices() {
        let line = sentence(100, "TRONG KHI MÌNH BỊ")
        let cloze = makeCloze(from: line, deck: [line, answer])

        #expect(cloze?.choices.isEmpty == true)
    }

    @Test("A full question offers the answer among its choices")
    func aFullQuestionIncludesTheAnswer() {
        let line = sentence(100, "TRONG KHI MÌNH BỊ")
        let deck = [line, answer, word(2, "ĂN MÒN"), word(3, "XẤU"), word(4, "VÀI")]

        let choices = makeCloze(from: line, deck: deck)?.choices ?? []

        #expect(choices.count == 4)
        #expect(choices.contains { $0.id == answer.id })
    }
}

@Suite("Judging a typed answer")
struct ClozeTypedAnswerTests {

    private func question() -> ClozeQuestion {
        let line = sentence(100, "TRONG KHI MÌNH BỊ")
        return makeCloze(from: line, deck: [line, word(1, "TRONG KHI")])!
    }

    @Test("The right word is accepted")
    func theRightWordIsAccepted() {
        #expect(isCorrectClozeAnswer("TRONG KHI", for: question()))
    }

    @Test("Case and spacing do not matter")
    func caseAndSpacingDoNotMatter() {
        // Same normalisation the deck's identity uses, so the reader is never
        // marked wrong for something the app itself treats as the same text.
        #expect(isCorrectClozeAnswer("trong khi", for: question()))
        #expect(isCorrectClozeAnswer("  Trong  Khi ", for: question()))
    }

    @Test("A missing tone counts, and is named")
    func aMissingToneCountsAndIsNamed() {
        // Typing tones on a phone is laborious, and rejecting an otherwise
        // perfect answer over one charges the reader for typing rather than
        // testing recall. It is still called out, so nothing here teaches that
        // Vietnamese tones are decoration.
        let line = sentence(100, "XÂM PHẠM ĐẾN THẨM QUYỀN")
        let q = makeCloze(from: line, deck: [line, word(1, "XÂM PHẠM")])!

        #expect(judgeClozeAnswer("xam pham", for: q) == .correctApartFromTones)
        #expect(isCorrectClozeAnswer("xam pham", for: q))
    }

    @Test("Exact spelling is plain correct, with no hint")
    func exactSpellingIsPlainCorrect() {
        #expect(judgeClozeAnswer("TRONG KHI", for: question()) == .correct)
    }

    @Test("Leniency reaches typing only, never the deck")
    func leniencyReachesTypingOnly() {
        // The rule this guards: two words differing only by tone are two words.
        // Folding tones into identity would collapse cards the deck holds
        // separately, and a card for CẤM matching CÂM inside a sentence would
        // ask the reader to fill in a word that sentence does not contain.
        #expect(normalizedKey("CẤM") != normalizedKey("CÂM"))

        let sentenceWithCam = "ĐẠO LUẬT CÂM TRỪNG PHẠT"
        #expect(deckWords(in: sentenceWithCam, from: [word(1, "CẤM")]).isEmpty)
    }

    @Test("A different word is wrong")
    func aDifferentWordIsWrong() {
        #expect(isCorrectClozeAnswer("ĂN MÒN", for: question()) == false)
    }

    @Test("An empty answer is wrong rather than vacuously right")
    func anEmptyAnswerIsWrong() {
        // Its normalised form is empty, which must not be treated as matching.
        #expect(isCorrectClozeAnswer("", for: question()) == false)
        #expect(isCorrectClozeAnswer("   ", for: question()) == false)
    }
}
