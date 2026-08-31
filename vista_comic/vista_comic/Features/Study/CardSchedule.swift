//
//  CardSchedule.swift
//  vista_comic
//
//  What a card says about itself: where it is, and when it is next up.
//
//  This replaces `Familiarity`'s adjectives — New, 認識, 熟悉 — which were an
//  alias for the rung. A screen full of "Familiarity New" is what provoked the
//  stage 6 rewrite: the word looked like a verdict on the reader while
//  describing a column that had not moved. What is here says only what the
//  system actually knows.
//

import Foundation

/// Where the card is, in words. "New", "Learning 2/3", "21 days".
///
/// The slot is rendered as its **interval** rather than its number, because
/// "21 days" is a fact about the reader's memory and "slot 3" is a fact about
/// an array.
func scheduleState(of card: LearningCard, steps: [Int]) -> String {
    switch card.state {
    case .new:
        return String(localized: "New")
    case .learning, .relearning:
        let total = max(steps.count, 1)
        let step = min((card.learningStep ?? 0) + 1, total)
        let name = card.state == .learning
            ? String(localized: "Learning")
            : String(localized: "Relearning")
        return "\(name) \(step)/\(total)"
    case .review:
        let days = ladderIntervals[min(max(card.ladderStage, 0), ladderTopRung)]
        return String(localized: "\(days) days")
    }
}

/// When the card is next up, relative to now — "in 7 min", "in 3 days".
///
/// Relative rather than absolute because the two scales this has to cover are
/// minutes and a year, and no single date format reads well across both. A card
/// already due says so rather than counting backwards.
func scheduleDue(of card: LearningCard, now: Date = Date()) -> String {
    if card.dueAt <= now { return String(localized: "due now") }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: card.dueAt, relativeTo: now)
}

/// Both halves, for a row or a question header. A new card has no due time
/// worth showing — it waits on the day's quota, not on a clock.
func scheduleSummary(of card: LearningCard, steps: [Int], now: Date = Date()) -> String {
    guard card.state != .new else { return scheduleState(of: card, steps: steps) }
    return "\(scheduleState(of: card, steps: steps)) · \(scheduleDue(of: card, now: now))"
}
