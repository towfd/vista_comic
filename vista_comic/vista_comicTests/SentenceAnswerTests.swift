//
//  SentenceAnswerTests.swift
//  vista_comicTests
//
//  Judging a produced sentence (vocabulary stage 5, tickets 01 and 02).
//
//  Two cases here come straight from the deck rather than from imagining edge
//  cases, and both would pass a naive implementation while being wrong on a
//  device: the sentences that repeat a word, and the word cards too short to
//  rearrange.
//

import Foundation
import Testing

@testable import vista_comic

private func sentenceCard(_ text: String) -> LearningCard {
    .preview(id: 1, sourceText: text, translation: "當…的時候", kind: "sentence")
}

private func wordCard(_ text: String) -> LearningCard {
    .preview(id: 2, sourceText: text, translation: "法律", kind: "word")
}

@Suite("Judging a produced sentence")
struct SentenceJudgingTests {

    private let card = sentenceCard("TRONG KHI MÌNH BỊ TẾ BÀO UNG THƯ ĂN MÒN")

    @Test("The exact sentence is correct")
    func theExactSentenceIsCorrect() {
        #expect(judgeSentenceAnswer("TRONG KHI MÌNH BỊ TẾ BÀO UNG THƯ ĂN MÒN", for: card) == .correct)
    }

    @Test("Case, spacing and punctuation do not matter")
    func caseSpacingAndPunctuationDoNotMatter() {
        // Same normalisation the deck's identity uses, so the reader is never
        // marked wrong for something the app itself treats as the same text.
        #expect(judgeSentenceAnswer("trong khi mình bị tế bào ung thư ăn mòn.", for: card) == .correct)
        #expect(judgeSentenceAnswer("  TRONG  KHI MÌNH BỊ TẾ BÀO UNG THƯ ĂN MÒN ", for: card) == .correct)
    }

    @Test("A missing tone counts, and is named")
    func aMissingToneCountsAndIsNamed() {
        // Typing tones across a whole sentence is laborious; rejecting an
        // otherwise perfect answer over one charges for typing rather than
        // testing recall. Naming it stops the leniency teaching that tones are
        // decoration.
        #expect(
            judgeSentenceAnswer("trong khi minh bi te bao ung thu an mon", for: card)
                == .correctApartFromTones
        )
    }

    @Test("The right words in the wrong order are wrong")
    func wrongOrderIsWrong() {
        // The point of the question type. Vietnamese grammar is in the order,
        // and an answer that ignored it would be testing vocabulary recall the
        // cloze already covers.
        #expect(judgeSentenceAnswer("MÌNH TRONG KHI BỊ TẾ BÀO UNG THƯ ĂN MÒN", for: card) == .wrong)
    }

    @Test("A different word is wrong")
    func aDifferentWordIsWrong() {
        #expect(judgeSentenceAnswer("TRONG KHI MÌNH BỊ TẾ BÀO UNG THƯ XẤU", for: card) == .wrong)
    }

    @Test("An empty answer is wrong rather than vacuously right")
    func anEmptyAnswerIsWrong() {
        #expect(judgeSentenceAnswer("", for: card) == .wrong)
        #expect(judgeSentenceAnswer("   ", for: card) == .wrong)
    }

    @Test("A word card is judged by the same function, with no special case")
    func aWordCardUsesTheSameRule() {
        // This is how the eleven orphaned word cards become askable at all.
        let word = wordCard("ĐẠO LUẬT")

        #expect(judgeSentenceAnswer("đạo luật", for: word) == .correct)
        #expect(judgeSentenceAnswer("dao luat", for: word) == .correctApartFromTones)
        #expect(judgeSentenceAnswer("XẤU", for: word) == .wrong)
    }
}

@Suite("Rearranging a sentence")
struct RearrangementTests {

    private let card = sentenceCard("TRONG KHI MÌNH BỊ")

    @Test("The pieces are the answer's own words, all of them")
    func thePiecesAreTheAnswersWords() {
        #expect(sentencePieces(of: card) == ["TRONG", "KHI", "MÌNH", "BỊ"])
    }

    @Test("Splitting is on whitespace, so a two-syllable word becomes two pieces")
    func splittingIsOnWhitespace() {
        // `ĐẠO LUẬT` is one word the reader collected and two pieces here. The
        // alternative — keeping deck words whole — needs the deck as a word
        // list; this rule needs nothing, and is the one thing that changes if
        // fifteen pieces proves miserable on a device.
        #expect(sentencePieces(of: sentenceCard("ĐẠO LUẬT CẤM")) == ["ĐẠO", "LUẬT", "CẤM"])
    }

    @Test("The shuffle never offers them already in order")
    func theShuffleIsNeverTheAnswer() {
        // Otherwise the screen shows a finished sentence and asks the reader to
        // arrange it, which is not a question.
        for _ in 0..<50 {
            #expect(shuffledPieces(of: card) != sentencePieces(of: card))
        }
    }

    @Test("Assembling them correctly is correct")
    func assemblingCorrectlyIsCorrect() {
        #expect(judgeArrangement(["TRONG", "KHI", "MÌNH", "BỊ"], for: card) == .correct)
    }

    @Test("Any other order is wrong")
    func anyOtherOrderIsWrong() {
        #expect(judgeArrangement(["KHI", "TRONG", "MÌNH", "BỊ"], for: card) == .wrong)
    }

    @Test("A repeated word gives identical pieces, and either placement is accepted")
    func aRepeatedWordAcceptsEitherPlacement() {
        // Straight from the deck: one sentence repeats CÒN and MÌNH, another
        // repeats LỢI. The screen shows pieces the reader cannot tell apart, so
        // checking which tile went where would mark a right answer wrong.
        let real = sentenceCard("CHÚNG BIẾT CÁCH LỢI DỤNG LUẬT ĐÊ MANG LẠI LỢI ÍCH")
        let pieces = sentencePieces(of: real)

        #expect(pieces.filter { $0 == "LỢI" }.count == 2)
        #expect(judgeArrangement(pieces, for: real) == .correct)
    }

    @Test("A word card is never rearranged")
    func aWordCardIsNeverRearranged() {
        // Six word cards in the deck are a single syllable — one piece, nothing
        // to arrange — and most of the rest are two, where guessing is right
        // half the time.
        #expect(canRearrange(wordCard("ĐẠO LUẬT")) == false)
        #expect(canRearrange(wordCard("XẤU")) == false)
    }

    @Test("A one-word sentence card is not rearranged either")
    func aOneWordSentenceIsNotRearranged() {
        #expect(canRearrange(sentenceCard("XẤU")) == false)
        #expect(canRearrange(card))
    }

    @Test("Pieces that are all identical still terminate")
    func identicalPiecesTerminate() {
        // A shuffle that can never differ from the original would loop forever
        // if it retried until it did. No arrangement of these changes the
        // answer, so any of them will do.
        let repeated = sentenceCard("LỢI LỢI")

        #expect(shuffledPieces(of: repeated).count == 2)
        #expect(judgeArrangement(shuffledPieces(of: repeated), for: repeated) == .correct)
    }
}
