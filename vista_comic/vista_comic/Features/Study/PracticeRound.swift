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
///
/// **Ten, not five.** A card appears at most once per answer mode, so five
/// questions would let at most two cards pass the day — and with a deck sitting
/// on the first rung, that is fifteen rounds to get through thirty cards once.
/// Ten lets four or five pass while staying inside the two-or-three minutes the
/// PRD asks for.
let practiceRoundLength = 10

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
    /// Whether this card was actually due.
    ///
    /// A round tops itself up when too few are, and **a topped-up card's answer
    /// moves no rung** in either direction. The reader cannot tell them apart,
    /// and that is fine: the difference is about scheduling correctness, not
    /// about their experience.
    let isDue: Bool
    /// Generated once, when the item is built, so a resubmission of the same
    /// answer carries the same token and cannot count twice.
    let token = UUID().uuidString

    var id: String { "\(question.id)-\(mode)-\(token)" }

    var questionType: ReviewQuestionType {
        mode == .choosing ? .clozeChoice : .clozeTyped
    }
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
    today: String = "",
    length: Int = practiceRoundLength
) -> Result<[PracticeItem], RoundUnavailable> {
    guard deck.count >= 2 else {
        return .failure(.tooFewCards(needed: 2 - deck.count))
    }

    let questions = deck.compactMap { makeCloze(from: $0, deck: deck) }
    guard !questions.isEmpty else {
        return .failure(.noSentencesWithKnownWords)
    }

    // Due first, least familiar first within that — the reader's worst words
    // come up first. A wrong answer is not a dead end here, so the usual
    // argument about discouragement does not apply; and a card at 熟悉 needs
    // one more correct answer where a card at 不熟 needs two, so favouring the
    // nearly-learned would flatter the round's numbers while teaching less.
    let ordered = questions.sorted { lhs, rhs in
        let lhsDue = isDue(lhs.card, on: today), rhsDue = isDue(rhs.card, on: today)
        if lhsDue != rhsDue { return lhsDue }
        return lhs.card.ladderStage < rhs.card.ladderStage
    }

    var items: [PracticeItem] = []
    var appearances: [Int: Int] = [:]
    var lastCardID: Int?

    while items.count < length {
        // Two guards against the deadlock that pure unfamiliarity ordering
        // creates — the least familiar card always wins, and getting it wrong
        // makes it win harder.
        let candidates = ordered.filter {
            $0.card.id != lastCardID && appearances[$0.card.id, default: 0] < 2
        }
        // Nothing left that has not already appeared twice: the deck is smaller
        // than the round, so let the limits go rather than cut the round short.
        // A shorter round would quietly hide how little there is to practise.
        let pool = candidates.isEmpty
            ? ordered.filter { $0.card.id != lastCardID }
            : candidates
        guard let question = pool.first ?? ordered.first else { break }

        let seen = appearances[question.card.id, default: 0]
        // A card's second appearance uses the other mode, so it is asked two
        // different ways — which is also the only route to 通過 inside one
        // round, since passing needs two correct answers.
        let mode: AnswerMode = seen.isMultiple(of: 2) ? .choosing : .typing
        items.append(
            PracticeItem(
                question: question,
                // A deck too small for four options cannot offer a choice, so
                // it is typed whatever the alternation says.
                mode: question.choices.isEmpty ? .typing : mode,
                isDue: isDue(question.card, on: today)
            )
        )
        appearances[question.card.id, default: 0] += 1
        lastCardID = question.card.id
    }
    return .success(items)
}

/// Whether `card` is due on or before `today`.
///
/// An empty `today` means "do not distinguish" — which is what the stage 3
/// callers and the previews want, and keeps a date out of code that has no
/// business knowing one.
func isDue(_ card: LearningCard, on today: String) -> Bool {
    today.isEmpty || card.dueOn <= today
}

/// What the reader has, and what a round would be made of.
///
/// Real counts only. Nothing here is a streak, a score, or a daily goal —
/// this stage records nothing, so anything of that sort would be decoration
/// dressed as progress.
struct DeckSummary: Hashable {
    let words: Int
    let sentences: Int
    /// Sentence cards that actually contain a word the reader has collected,
    /// which is what decides whether a round can be built at all.
    let usableSentences: Int
    /// Every blank that could be asked, across those sentences.
    let availableBlanks: Int

    init(deck: [LearningCard]) {
        words = deck.filter { $0.kind == .word }.count
        sentences = deck.filter { $0.kind == .sentence }.count

        let usable = deck.filter { card in
            card.kind == .sentence && makeCloze(from: card, deck: deck) != nil
        }
        usableSentences = usable.count
        availableBlanks = usable.reduce(0) { total, card in
            let others = deck.filter { $0.id != card.id }
            return total + deckWords(in: card.sourceText, from: others).count
        }
    }
}

/// How a round went, for the summary at the end.
///
/// The answers themselves are recorded on the backend as they happen; this is
/// only what the summary screen reads, and it dies with the screen.
struct RoundOutcome: Hashable {
    private(set) var correct = 0
    private(set) var wrong = 0
    /// Cards that reached 通過 during the round.
    ///
    /// Reported instead of — not as well as — a score, because it is the figure
    /// that means something: a round can be all-correct while passing nothing,
    /// if every card was seen once. **"Two of your words are done for today"**
    /// is a fact about learning; "8 / 10" is a fact about tapping.
    private(set) var passed: Set<Int> = []

    var total: Int { correct + wrong }
    var allCorrect: Bool { wrong == 0 && correct > 0 }

    mutating func record(correct isCorrect: Bool, cardID: Int, step: DailyStep) {
        if isCorrect { correct += 1 } else { wrong += 1 }
        if step == .passed {
            passed.insert(cardID)
        } else {
            // A card can fall back out of 通過 by being answered wrong later in
            // the same round, and the summary should not still be claiming it.
            passed.remove(cardID)
        }
    }
}
