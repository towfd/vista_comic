//
//  ClozeQuestion.swift
//  vista_comic
//
//  Turning a card into a question, or deciding it cannot be one.
//
//  **Question types follow from what a card actually supports.** A card that
//  cannot carry a cloze produces nothing and the round takes another — never a
//  blank punched somewhere arbitrary to fill a slot. With a small deck that
//  happens often, and it is not an error state.
//

import Foundation

/// One cloze: a sentence with one of the reader's own words taken out.
struct ClozeQuestion: Identifiable, Hashable {
    /// The card the sentence came from.
    let card: LearningCard
    /// The card whose word was removed — always one the reader collected,
    /// because blanking a word they never chose tests nothing.
    let answer: LearningCard
    /// The sentence as the reader will see it, blank included.
    let prompt: String
    /// The text that was removed, exactly as it appeared. Kept separately from
    /// `answer.sourceText` because a sentence may hold a different casing of
    /// the same word, and the reader should be shown what was really there.
    let removed: String
    /// Wrong options, drawn from the reader's other cards. Empty when the deck
    /// is too small for a choice question, which is what makes this typed-only.
    let distractors: [LearningCard]

    var id: String { "\(card.id)-\(answer.id)-\(prompt.hashValue)" }

    /// The four options in a stable shuffled order, or empty when there are not
    /// enough cards for a choice question.
    var choices: [LearningCard] {
        distractors.isEmpty ? [] : ([answer] + distractors).shuffled()
    }
}

/// How many options a choice question shows, the answer included.
let clozeChoiceCount = 4

/// Builds a cloze from `card`, or returns `nil` when it cannot carry one.
///
/// A card qualifies when it is a **sentence** and at least one deck word occurs
/// in it. A word card never qualifies here: it has no sentence to blank, and
/// generating one is a later stage.
///
/// **The least familiar deck word present is the one removed.** That is the one
/// worth testing, and it reuses the familiarity the deck already tracks rather
/// than inventing a second idea of what needs practice. Ties break on the
/// earliest occurrence, so the choice is deterministic and a test can state it.
func makeCloze(
    from card: LearningCard,
    deck: [LearningCard],
    choiceCount: Int = clozeChoiceCount
) -> ClozeQuestion? {
    guard card.kind == .sentence else { return nil }

    // **A blank must leave something to read.** Excluding the card itself is
    // not enough: the deck holds several near-identical copies of one sentence,
    // so a *different* card can still match the whole of this one and produce a
    // question that is nothing but a blank. What disqualifies a match is
    // therefore covering the sentence, not being the same row.
    let others = deck.filter { $0.id != card.id }
    let matches = deckWords(in: card.sourceText, from: others)
        .filter { !coversEverything($0.range, of: card.sourceText) }
    guard let chosen = matches.min(by: { lhs, rhs in
        let l = lhs.card.ladderStage, r = rhs.card.ladderStage
        return l == r ? lhs.range.lowerBound < rhs.range.lowerBound : l < r
    }) else { return nil }

    return ClozeQuestion(
        card: card,
        answer: chosen.card,
        prompt: card.sourceText.blanking(chosen.range),
        removed: String(card.sourceText[chosen.range]),
        distractors: distractors(
            for: chosen.card, from: deck, count: choiceCount - 1
        )
    )
}

/// Whether blanking `range` would leave nothing but the blank.
///
/// A cloze with no context is not a question — the reader would be asked to
/// reproduce a whole sentence from a single underscore.
private func coversEverything(_ range: Range<String.Index>, of sentence: String) -> Bool {
    sentence
        .replacingCharacters(in: range, with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
}

/// Wrong options for a question whose answer is `answer`.
///
/// Drawn from the reader's own cards, so no dictionary and no generation is
/// involved — and they are revision in their own right, since choosing
/// correctly means reading all four.
///
/// Returns nothing when the deck cannot supply enough, which is what turns the
/// question typed-only rather than showing two options and calling it a choice.
func distractors(
    for answer: LearningCard,
    from deck: [LearningCard],
    count: Int
) -> [LearningCard] {
    let pool = deck.filter {
        $0.id != answer.id
            // A distractor identical to the answer would make the question
            // unanswerable, and the deck can hold two cards whose text differs
            // only by something normalisation folds away.
            && normalizedKey($0.sourceText) != normalizedKey(answer.sourceText)
    }
    guard pool.count >= count else { return [] }
    return Array(pool.shuffled().prefix(count))
}

/// How a typed answer came out.
enum TypedVerdict: Hashable {
    /// Spelled exactly right.
    case correct
    /// Right word, but the tone marks were missing or wrong. Counted as correct
    /// — the reader knew it — while still naming the spelling, so nothing here
    /// teaches that tones are optional.
    case correctApartFromTones
    case wrong

    var isCorrect: Bool { self != .wrong }
}

/// Judges what the reader typed.
///
/// Punctuation and spacing never matter, because the deck's own normalisation
/// removes them. **Tones are forgiven but named**: typing them on a phone is
/// laborious, and rejecting an otherwise perfect answer over one charges the
/// reader for typing rather than testing recall — but a lesson that silently
/// accepted `xam pham` would be teaching that Vietnamese tones are decoration.
///
/// This leniency lives here and nowhere else. Card identity and the search for
/// deck words inside a sentence stay strict, since two words differing only by
/// tone are two words.
func judgeClozeAnswer(_ typed: String, for question: ClozeQuestion) -> TypedVerdict {
    let given = normalizedKey(typed)
    guard !given.isEmpty else { return .wrong }

    let exact = [normalizedKey(question.removed), normalizedKey(question.answer.sourceText)]
    if exact.contains(given) { return .correct }

    let loose = [
        toneInsensitiveKey(question.removed),
        toneInsensitiveKey(question.answer.sourceText),
    ]
    return loose.contains(toneInsensitiveKey(typed)) ? .correctApartFromTones : .wrong
}

/// Whether a typed answer counts as right.
func isCorrectClozeAnswer(_ typed: String, for question: ClozeQuestion) -> Bool {
    judgeClozeAnswer(typed, for: question).isCorrect
}
