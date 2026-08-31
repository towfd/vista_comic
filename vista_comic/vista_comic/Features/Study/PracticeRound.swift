//
//  PracticeRound.swift
//  vista_comic
//
//  A question, as data.
//
//  Built as a value rather than assembled inside the view, for the reason
//  `SelectionActions.swift` gives: the rules worth testing are the ones about
//  what the reader is asked, and they must be testable without rendering
//  anything.
//
//  **What used to be here was a round of ten.** Choosing the cards moved to
//  `PracticeQueue.swift` when a session stopped having a length; what is left
//  is what a question *is*, and what a card can be asked.
//

import Foundation

/// What the reader is asked to do.
///
/// **Drawn at random** since stage 6, from whatever the card supports. It used
/// to be chosen by the card's rung, on the argument that recognition should
/// come before production — the reader removed that, wanting the difficulty,
/// and `askedDifficulty(forRung:)` went with it.
enum AnswerMode: Hashable {
    /// Cloze, four choices. Recognition.
    case choosing
    /// Cloze, typed. Production with the sentence still in front of the reader.
    case typing
    /// The whole sentence, from scrambled pieces. Production with support.
    case rearranging
    /// The whole sentence, typed, from the meaning alone.
    case translating
}

/// One question, and how it is to be answered.
///
/// `question` is `nil` for the two whole-sentence modes: they ask for the card
/// itself, so there is no blank and nothing to build. That is also how a **word
/// card** enters a round at all — eleven of the deck's twenty-two appear in no
/// sentence, so no cloze can ever be made from them, and before this they were
/// collected and counted and never asked about.
struct PracticeItem: Identifiable, Hashable {
    let card: LearningCard
    let question: ClozeQuestion?
    let mode: AnswerMode
    /// Generated once, when the item is built, so a resubmission of the same
    /// answer carries the same token and cannot count twice.
    let token = UUID().uuidString

    /// What the reader is shown to work from.
    var prompt: String {
        question?.prompt ?? card.translation
    }

    var id: String { "\(card.id)-\(mode)-\(token)" }

    var questionType: ReviewQuestionType {
        switch mode {
        case .choosing: .clozeChoice
        case .typing: .clozeTyped
        case .rearranging: .sentenceRearranged
        case .translating: .sentenceTyped
        }
    }
}

/// What the reader has, and what a session can be made of.
///
/// Real counts only. Nothing here is a streak, a score, or a daily goal —
/// those are stage 7, and anything of the sort now would be decoration dressed
/// as progress.
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
    /// Cards that graduated onto the interval table during the session.
    ///
    /// Reported instead of — not as well as — a score, because it is the figure
    /// that means something: a session can be all-correct while graduating
    /// nothing, if every card was seen once. **"Two of your words are done"** is
    /// a fact about learning; "8 / 10" is a fact about tapping.
    private(set) var graduated: Set<Int> = []

    var total: Int { correct + wrong }
    var allCorrect: Bool { wrong == 0 && correct > 0 }

    mutating func record(correct isCorrect: Bool, cardID: Int, state: CardState) {
        if isCorrect { correct += 1 } else { wrong += 1 }
        if state == .review {
            graduated.insert(cardID)
        } else {
            // A card can fall back out of review by being missed later in the
            // same session, and the summary should not still be claiming it.
            graduated.remove(cardID)
        }
    }
}


extension AnswerMode {
    /// Whether this mode needs a sentence with a blank in it.
    var needsCloze: Bool { self == .choosing || self == .typing }
}

/// Everything `card` can be asked, in any order.
///
/// **The card decides, and nothing else does.** The rung used to pick a
/// difficulty band and this filtered it down; stage 6 removed the band, so what
/// is left is the question that always mattered — what can this card actually
/// carry? A word card has no cloze, a sentence with no deck word in it has none
/// either, and a deck too small for four options cannot offer a choice.
///
/// Never empty: typed translation always works, because it asks for the card
/// itself. That is also how the eleven word cards appearing in no sentence get
/// asked at all.
func askableModes(for card: LearningCard, deck: [LearningCard]) -> [AnswerMode] {
    var modes: [AnswerMode] = []
    let cloze = makeCloze(from: card, deck: deck)
    if let cloze, !cloze.choices.isEmpty { modes.append(.choosing) }
    if cloze != nil { modes.append(.typing) }
    if canRearrange(card) { modes.append(.rearranging) }
    modes.append(.translating)
    return modes
}
