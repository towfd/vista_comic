//
//  PracticeQueue.swift
//  vista_comic
//
//  What to ask next, and when there is nothing left to ask.
//
//  A session is no longer ten questions. It runs until its queue is empty,
//  which is the only end that means anything — a fixed count cannot tell the
//  reader they are finished, because it does not know what "finished" was.
//
//  Pure functions over the deck, the settings and a clock passed in. Nothing
//  here reads `Date()` on its own, for the same reason the backend's scheduler
//  does not: a session in airplane mode is scheduled from when the reader
//  answered, and a test needs to stand at 20:07 without waiting for it.
//

import Foundation

/// How far ahead a learning card may be pulled forward when nothing else is
/// due.
///
/// Anki's default, and it exists because of decks this size. Three cards on
/// five-minute timers and nothing else to ask would otherwise mean sitting and
/// waiting — so the soonest one is offered early rather than the session
/// stalling on a clock.
let learnAheadWindow: TimeInterval = 20 * 60

/// Why the queue had nothing to offer.
///
/// Two cases and they send the reader to different places: an empty deck means
/// "go and collect some words", and a finished day means "come back tomorrow".
/// Telling them the wrong one wastes their evening.
enum QueueEmpty: Hashable, Error {
    /// Nothing collected at all.
    case deckIsEmpty
    /// Everything due has been answered and the day's new cards are spent.
    case dayIsDone
}

/// The cards the reader has met — everything past `new`.
///
/// What 永無止盡的訓練 draws from, and deliberately not the whole deck: a card
/// meeting the reader for the first time in a mode that schedules nothing would
/// be a word met and then forgotten by the system.
func trainableCards(in deck: [LearningCard]) -> [LearningCard] {
    deck.filter { $0.state != .new }
}

/// How many cards were met for the first time on `day`.
///
/// Counted off the cards themselves rather than kept as a tally, so it survives
/// a relaunch and stays right with no network. `day` is the reader's local day,
/// formatted as the backend writes it.
func introducedCount(in deck: [LearningCard], on day: String) -> Int {
    deck.filter { $0.introducedOn == day }.count
}

/// Whether a card is waiting on minutes rather than days.
func isInLearning(_ card: LearningCard) -> Bool {
    card.state == .learning || card.state == .relearning
}

/// The next card to ask, or why there is none.
///
/// Order of preference, and each line of it is a decision:
///
/// 1. **Learning cards that are due** — minutes matter more than days, and a
///    card the reader is in the middle of learning is the one they are closest
///    to keeping.
/// 2. **Review cards that are due.**
/// 3. **New cards**, up to what is left of the day's quota.
/// 4. **Learn-ahead**: only if learning cards exist and none is due yet.
///
/// `avoiding` keeps the same card off the screen twice in a row, which matters
/// most in exactly the case the learn-ahead exists for — a deck small enough
/// that one card is the whole queue.
func nextCard(
    from deck: [LearningCard],
    settings: StudySettings,
    now: Date,
    today: String,
    avoiding lastCardID: Int? = nil
) -> Result<LearningCard, QueueEmpty> {
    guard !deck.isEmpty else { return .failure(.deckIsEmpty) }

    func pick(_ candidates: [LearningCard]) -> LearningCard? {
        let others = candidates.filter { $0.id != lastCardID }
        return (others.isEmpty ? candidates : others).first
    }

    let dueNow = deck.filter { $0.state != .new && $0.dueAt <= now }
        .sorted { $0.dueAt < $1.dueAt }
    if let card = pick(dueNow.filter(isInLearning)) { return .success(card) }
    if let card = pick(dueNow.filter { !isInLearning($0) }) { return .success(card) }

    let remainingQuota = settings.newCardsPerDay - introducedCount(in: deck, on: today)
    if remainingQuota > 0 {
        // Oldest first, which is the order they were collected in — Anki's
        // default too. Any other order would be inventing a curriculum out of
        // a list the reader built by reading.
        let fresh = deck.filter { $0.state == .new }.sorted { $0.createdAt < $1.createdAt }
        if let card = pick(fresh) { return .success(card) }
    }

    // Nothing is due and nothing new is left, but a learning card is coming.
    // Offer it early rather than let the session stall on a five-minute timer.
    let soon = deck.filter { isInLearning($0) && $0.dueAt <= now.addingTimeInterval(learnAheadWindow) }
        .sorted { $0.dueAt < $1.dueAt }
    if let card = pick(soon) { return .success(card) }

    return .failure(.dayIsDone)
}

/// The next question, built from the next card.
///
/// The mode is drawn **at random** from everything the card supports, with no
/// difficulty curve. That was the reader's decision, taken knowingly: a card
/// they have never seen can be asked to be typed out whole. Tones are forgiven
/// (`SentenceAnswer.swift`), so that is hard rather than impossible, and a card
/// that cannot be produced yet will draw a four-choice or a rearrangement often
/// enough to get through.
func nextItem(
    from deck: [LearningCard],
    settings: StudySettings,
    now: Date,
    today: String,
    avoiding lastCardID: Int? = nil
) -> Result<PracticeItem, QueueEmpty> {
    nextCard(
        from: deck, settings: settings, now: now, today: today, avoiding: lastCardID
    ).map { card in
        let mode = askableModes(for: card, deck: deck).randomElement() ?? .translating
        return PracticeItem(
            card: card,
            question: mode.needsCloze ? makeCloze(from: card, deck: deck) : nil,
            mode: mode
        )
    }
}

/// One question drawn from the training pool, which schedules nothing.
///
/// No due dates and no quota — every card the reader has met, at random. The
/// weighting the PRD once specified (unfamiliarity raising a card's chance,
/// recent appearances suppressing it) was dropped rather than built: it was the
/// most complicated rule in the document, and it was serving the one mode whose
/// answers change nothing.
func nextTrainingItem(
    from deck: [LearningCard],
    avoiding lastCardID: Int? = nil
) -> PracticeItem? {
    let pool = trainableCards(in: deck)
    guard !pool.isEmpty else { return nil }
    let others = pool.filter { $0.id != lastCardID }
    guard let card = (others.isEmpty ? pool : others).randomElement() else { return nil }

    let mode = askableModes(for: card, deck: deck).randomElement() ?? .translating
    return PracticeItem(
        card: card,
        question: mode.needsCloze ? makeCloze(from: card, deck: deck) : nil,
        mode: mode
    )
}

/// How many cards a scheduled session still has to get through.
///
/// The same three sources `nextCard` draws from, counted instead of picked:
/// what is due, what is left of the day's new quota, and the learning cards
/// coming back inside the learn-ahead window. Pinned by the invariant that
/// makes it worth having — **this is `0` if and only if `nextCard` fails**, for
/// the same deck, settings, clock and day. Two implementations of "finished"
/// disagreeing is how the three-step day's "I have practised this and it still
/// says New" happened, so the parity is asserted rather than assumed.
///
/// Learning cards not yet due are counted for the same reason `nextCard` offers
/// them: a card on a five-minute step *is* coming back in this session, so
/// leaving it out would read `0` while the session kept asking questions.
///
/// **This counts cards, not questions.** A wrong answer sends a card back to
/// the first learning step, so how many questions remain is unknowable — which
/// is why a session has no fixed length in the first place. It also means the
/// figure can rise: answering a review card wrong puts it into relearning and
/// adds one. That is a fact about the deck rather than a punishment, and it is
/// the reason this is a number on screen and not a progress bar.
func remainingCards(
    from deck: [LearningCard],
    settings: StudySettings,
    now: Date,
    today: String
) -> Int {
    let met = deck.filter { $0.state != .new }
    let dueNow = met.filter { $0.dueAt <= now }

    // Capped by the deck as well as by the quota: a reader with room for
    // twenty new cards and three left uncollected has three.
    let quotaLeft = max(settings.newCardsPerDay - introducedCount(in: deck, on: today), 0)
    let newCounted = min(quotaLeft, deck.filter { $0.state == .new }.count)

    // Strictly after `now`, so a learning card already due is counted once by
    // `dueNow` rather than twice here.
    let soon = met.filter {
        isInLearning($0) && $0.dueAt > now && $0.dueAt <= now.addingTimeInterval(learnAheadWindow)
    }

    return dueNow.count + newCounted + soon.count
}
