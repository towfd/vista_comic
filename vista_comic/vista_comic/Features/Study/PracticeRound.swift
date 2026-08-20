//
//  PracticeRound.swift
//  vista_comic
//
//  One round of practice, as data.
//
//  Built as a value rather than assembled inside the view, for the reason
//  `SelectionActions.swift` gives: the rules worth testing are the ones about
//  what the reader is asked, and they must be testable without rendering
//  anything.
//
//  **Nothing here is recorded.** No reviews, no ladder, no mistakes area — that
//  is the next stage. This round exists to find out whether answering is worth
//  doing before building the machinery that remembers it.
//

import Foundation

/// How many questions a round asks.
let practiceRoundLength = 5

/// How the reader answers one question.
///
/// Which one appears is **alternated**, not chosen: nothing yet knows how
/// familiar a card is, so nothing can decide. Stage 4 replaces the alternation
/// with a real difficulty ladder; until then alternating at least gets both
/// interfaces exercised.
enum AnswerMode: Hashable {
    case choosing
    case typing
}

/// One question, and how it is to be answered.
struct PracticeItem: Identifiable, Hashable {
    let question: ClozeQuestion
    let mode: AnswerMode

    var id: String { "\(question.id)-\(mode)" }
}

/// Why a round could not be built.
///
/// Two separate cases, deliberately: "collect more words" and "collect a
/// sentence" send the reader to different actions, and telling them the wrong
/// one wastes their time.
enum RoundUnavailable: Hashable, Error {
    /// Not enough cards to build a question at all.
    case tooFewCards(needed: Int)
    /// Cards, but nothing that can carry a blank.
    case noSentencesWithKnownWords
}

/// Builds a round from the deck, or explains why it cannot.
///
/// Cards that cannot carry a cloze are skipped rather than forced — question
/// types follow from what a card actually supports. With a small deck that
/// happens often and is not an error.
///
/// A round can repeat a card when the deck has fewer usable sentences than the
/// round is long. That is honest at this size: the alternative is a shorter
/// round that quietly hides how little there is to practise.
func makeRound(
    from deck: [LearningCard],
    length: Int = practiceRoundLength
) -> Result<[PracticeItem], RoundUnavailable> {
    guard deck.count >= 2 else {
        return .failure(.tooFewCards(needed: 2 - deck.count))
    }

    let questions = deck.compactMap { makeCloze(from: $0, deck: deck) }
    guard !questions.isEmpty else {
        return .failure(.noSentencesWithKnownWords)
    }

    var items: [PracticeItem] = []
    var pool: [ClozeQuestion] = []
    while items.count < length {
        if pool.isEmpty { pool = questions.shuffled() }
        let question = pool.removeFirst()
        // Alternating rather than random, so a round always exercises both
        // interfaces instead of occasionally showing five of one.
        let mode: AnswerMode = items.count.isMultiple(of: 2) ? .choosing : .typing
        // A question with too small a deck behind it cannot offer choices, so
        // it is typed whatever the alternation says.
        items.append(
            PracticeItem(
                question: question,
                mode: question.choices.isEmpty ? .typing : mode
            )
        )
    }
    return .success(items)
}

/// How a round went, for the summary at the end.
///
/// Counts only — nothing is written anywhere, and this value dies with the
/// screen.
struct RoundOutcome: Hashable {
    private(set) var correct = 0
    private(set) var wrong = 0

    var total: Int { correct + wrong }
    var allCorrect: Bool { wrong == 0 && correct > 0 }

    mutating func record(correct isCorrect: Bool) {
        if isCorrect { correct += 1 } else { wrong += 1 }
    }
}
