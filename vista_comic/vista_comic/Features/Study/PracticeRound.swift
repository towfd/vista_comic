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

/// What the reader is asked to do.
///
/// Chosen by the card's **ladder rung** — how well it is known over weeks —
/// rather than by its position in today's three steps. Using the day would put
/// every card back to four choices each morning, including words learned months
/// ago, and would make a card's two appearances in one round differ in
/// difficulty purely because the first went well.
///
/// Stage 3 alternated between the first two because nothing then knew how
/// familiar a card was. That was always a placeholder for this.
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

/// The difficulty band a rung falls in.
///
/// Three bands over five rungs, not five: the ladder is an interval schedule and
/// the question types are a difficulty curve, and they do not have to agree on
/// how many steps they have.
///
/// **The whole deck sits on rung 0 today**, so every question will be
/// four-choice until cards start climbing. That is the design working, not a
/// defect — but it is worth expecting rather than reporting.
func askedDifficulty(forRung rung: Int) -> [AnswerMode] {
    switch rung {
    case ..<2: [.choosing]
    case 2...3: [.typing, .rearranging]
    default: [.translating]
    }
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

    // Every card that can be asked *something*. A card unaskable at its own
    // rung falls back rather than being dropped — question types follow from
    // what a card supports, and a card supporting nothing at all is the only
    // reason to leave it out.
    let askable = deck.filter { !askableModes(for: $0, deck: deck).isEmpty }
    guard !askable.isEmpty else {
        return .failure(.noSentencesWithKnownWords)
    }

    // Ties are broken at random, and that matters more than it sounds. On a
    // fresh deck *every* card is due and every card is on rung 0, so the two
    // keys above decide nothing at all and the order falls through to whatever
    // `GET /cards` returned — which is `created_at DESC`. A round would then be
    // the six most recently collected cards, every time, for as long as they
    // stayed unresolved.
    let jitter = Dictionary(
        uniqueKeysWithValues: askable.map { ($0.id, Double.random(in: 0..<1)) }
    )

    // Due first, least familiar first within that — the reader's worst words
    // come up first. A wrong answer is not a dead end here, so the usual
    // argument about discouragement does not apply; and a card at 熟悉 needs
    // one more correct answer where a card at 不熟 needs two, so favouring the
    // nearly-learned would flatter the round's numbers while teaching less.
    let ordered = askable.sorted { lhs, rhs in
        let lhsDue = isDue(lhs, on: today), rhsDue = isDue(rhs, on: today)
        if lhsDue != rhsDue { return lhsDue }
        if lhs.ladderStage != rhs.ladderStage { return lhs.ladderStage < rhs.ladderStage }
        return jitter[lhs.id, default: 0] < jitter[rhs.id, default: 0]
    }

    var items: [PracticeItem] = []
    var appearances: [Int: Int] = [:]
    var lastCardID: Int?

    while items.count < length {
        // Two guards against the deadlock that pure unfamiliarity ordering
        // creates — the least familiar card always wins, and getting it wrong
        // makes it win harder.
        let candidates = ordered.filter {
            $0.id != lastCardID && appearances[$0.id, default: 0] < 2
        }
        // Nothing left that has not already appeared twice: the deck is smaller
        // than the round, so let the limits go rather than cut the round short.
        // A shorter round would quietly hide how little there is to practise.
        let pool = candidates.isEmpty ? ordered.filter { $0.id != lastCardID } : candidates
        guard let card = pool.first ?? ordered.first else { break }

        let modes = askableModes(for: card, deck: deck)
        // A card's two appearances use different modes where its band offers
        // two, so it is asked two ways rather than the same way twice — which
        // is also the only route to 通過 inside one round.
        let mode = modes[appearances[card.id, default: 0] % modes.count]
        items.append(
            PracticeItem(
                card: card,
                question: mode.needsCloze ? makeCloze(from: card, deck: deck) : nil,
                mode: mode,
                isDue: isDue(card, on: today)
            )
        )
        appearances[card.id, default: 0] += 1
        lastCardID = card.id
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


extension AnswerMode {
    /// Whether this mode needs a sentence with a blank in it.
    var needsCloze: Bool { self == .choosing || self == .typing }
}

/// What `card` can actually be asked, at the difficulty its rung calls for.
///
/// The rung decides the band; the card decides what of that band is possible.
/// **A card falls back rather than being dropped**: a word card has no cloze, a
/// sentence with no deck word in it has none either, and a deck too small for
/// four options cannot offer a choice. Question types follow from what a card
/// supports, which is the rule since stage 3 — and it is what lets the eleven
/// word cards that appear in no sentence be asked at all.
///
/// Returns empty only when nothing at all can be asked, which is the one case
/// worth excluding a card for.
func askableModes(for card: LearningCard, deck: [LearningCard]) -> [AnswerMode] {
    let cloze = makeCloze(from: card, deck: deck)
    let possible = askedDifficulty(forRung: card.ladderStage).filter { mode in
        switch mode {
        case .choosing: cloze.map { !$0.choices.isEmpty } ?? false
        case .typing: cloze != nil
        case .rearranging: canRearrange(card)
        case .translating: true
        }
    }
    if !possible.isEmpty { return possible }

    // Nothing in its own band fits, so take whatever the card can do. Typed
    // translation always can — it asks for the card itself — which is why a
    // card is only ever excluded when it has no translation to ask for.
    var fallback: [AnswerMode] = []
    if let cloze, !cloze.choices.isEmpty { fallback.append(.choosing) }
    if canRearrange(card) { fallback.append(.rearranging) }
    fallback.append(.translating)
    return fallback
}
