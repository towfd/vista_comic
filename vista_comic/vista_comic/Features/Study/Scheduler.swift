//
//  Scheduler.swift
//  vista_comic
//
//  What one answer does to a card — the same state machine the backend runs,
//  in Swift.
//
//  **A deliberate second implementation.** Everywhere else in this app the rule
//  is that the backend decides and the app is told, precisely so the two cannot
//  come to disagree. Offline practice cannot ask, so this exists, and the cost
//  is paid down two ways: the transition table below is the same table
//  `backend/app/scheduler.py` documents, and `SchedulerParityTests` asserts the
//  same cases against both wordings so a change to one that is not made to the
//  other fails a test rather than a reader's schedule.
//
//  When an answer does reach the server, the server's result **wins** — this is
//  what the app runs on until then, not a second opinion to reconcile.
//

import Foundation

/// Everything scheduling knows about one card, as a value.
struct CardScheduling: Hashable {
    var state: CardState
    var learningStep: Int?
    var stage: Int
    var previousStage: Int?
    var dueAt: Date
}

/// Where `current` goes after one answer.
///
/// | From | Correct | Wrong |
/// |---|---|---|
/// | `new` | learning, step 0 | learning, step 0 |
/// | learning step *i* | step *i+1* | step 0 |
/// | learning, last step | graduates | step 0 |
/// | `review` slot *n* | slot *n+1*, clamped | relearning, keeping *n−1* |
/// | `relearning` | as learning | step 0 |
///
/// A `review` card answered **before** its due date is returned unchanged in
/// either direction — see the comment on that branch.
///
/// A first answer that is wrong still only reaches the first step: there is
/// nothing below the bottom, and inventing a punishment there would charge the
/// reader for meeting a word.
///
/// **The learning steps land on a minute; the slots land on a day.** A step
/// means its minutes literally. A slot means a *day* rather than a block of
/// twenty-four hours, so those due dates are rounded to the start of a
/// scheduling day (`dueAfter`) — which is what stops a card finished at
/// 23:59 from coming back at 23:59 the following night.
///
/// `timeZone` decides whose day that is. It defaults to the phone's, which is
/// the right answer for every caller here: all three are "this reader, on this
/// device, now". The backend is configured with a fixed zone instead
/// (`config.get_scheduling_timezone`), and the two agree at home; where they
/// do not, the server's result wins on sync, as it does for everything else.
///
/// Graduating returns to `previousStage` when there is one, which is what makes
/// a lapse cost one slot instead of everything — and it is cleared once used,
/// so a second lapse from slot 5 returns to 4 rather than to whatever the first
/// remembered.
func nextSchedule(
    _ current: CardScheduling,
    correct: Bool,
    answeredAt: Date,
    learningSteps: [Int],
    timeZone: TimeZone = .current
) -> CardScheduling {
    let steps = learningSteps.filter { $0 > 0 }
    // The backend raises on an unusable list because a route can answer 422.
    // Here there is nobody to tell, and refusing to schedule would strand the
    // card — so the defaults stand in.
    let usable = steps.isEmpty ? StudySettings.fallback.learningSteps : steps

    func atStep(_ state: CardState, _ index: Int) -> CardScheduling {
        // Clamped, because the reader may have shortened the list under a card
        // already past the new end of it.
        let bounded = max(0, min(index, usable.count - 1))
        var moved = current
        moved.state = state
        moved.learningStep = bounded
        moved.dueAt = answeredAt.addingTimeInterval(TimeInterval(usable[bounded]) * 60)
        return moved
    }

    func graduated() -> CardScheduling {
        let slot = clampSlot(current.previousStage ?? 0)
        return CardScheduling(
            state: .review,
            learningStep: nil,
            stage: slot,
            previousStage: nil,
            dueAt: dueAfter(slot: slot, from: answeredAt, in: timeZone)
        )
    }

    switch current.state {
    case .new:
        return atStep(.learning, 0)

    case .learning, .relearning:
        if !correct { return atStep(current.state, 0) }
        let index = max(0, min(current.learningStep ?? 0, usable.count - 1))
        return index >= usable.count - 1 ? graduated() : atStep(current.state, index + 1)

    case .review:
        // **An answer that arrives before the card is due moves nothing** —
        // not up, and by the same sentence not down either. The interval is
        // the claim being tested, and a card that graduated onto one day an
        // hour ago has not survived a day, so nothing it can be answered with
        // now is a measurement of three.
        //
        // It is also what stops a card being asked twice from counting twice.
        // The queue is built from a deck this app holds, and a deck can be
        // stale; the card's own due date cannot.
        //
        // The learning steps are deliberately outside this: `learnAheadWindow`
        // offers a learning card up to twenty minutes early on purpose.
        if answeredAt < current.dueAt { return current }

        if correct {
            let slot = clampSlot(current.stage + 1)
            return CardScheduling(
                state: .review,
                learningStep: nil,
                stage: slot,
                previousStage: nil,
                dueAt: dueAfter(slot: slot, from: answeredAt, in: timeZone)
            )
        }
        var lapsed = atStep(.relearning, 0)
        lapsed.previousStage = clampSlot(current.stage - 1)
        return lapsed
    }
}

/// A slot brought inside the interval table.
func clampSlot(_ slot: Int) -> Int {
    max(0, min(slot, ladderTopRung))
}

/// The hour a scheduling day begins, in the reader's own timezone.
///
/// Four in the morning rather than midnight — Anki's default, for Anki's
/// reason. This reader reads comics at night, and under a midnight rollover a
/// card finished at 23:59 would come back **one minute later**, in the same
/// sitting. A day that ends when the reader goes to sleep is the day they
/// actually live.
///
/// Mirrored in `backend/app/ladder.py` as `DAY_ROLLOVER_HOUR`.
let ladderDayRolloverHour = 4

/// The start of the scheduling day `moment` falls in.
///
/// A scheduling day runs from `ladderDayRolloverHour` to the same hour the
/// next calendar day, so an answer given in the small hours belongs to the day
/// the reader still thinks of as in progress — 02:00 on Tuesday is Monday
/// night.
func schedulingDayStart(of moment: Date, in timeZone: TimeZone = .current) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    guard let rollover = calendar.date(
        bySettingHour: ladderDayRolloverHour, minute: 0, second: 0, of: moment
    ) else {
        // Only reachable if the zone has no such hour on this date at all.
        // Falling back to the calendar day keeps a schedule rather than
        // refusing one, which is the same stance `nextSchedule` takes on an
        // unusable list of steps.
        return calendar.startOfDay(for: moment)
    }
    guard moment < rollover else { return rollover }
    return calendar.date(byAdding: .day, value: -1, to: rollover) ?? rollover
}

/// When a card on `slot` answered at `moment` comes back.
///
/// Counted from the answer rather than from the previous due date: a card
/// answered four days late is not owed those four days back.
///
/// **Measured in days, not in multiples of 24 hours.** The answer is rounded
/// down to the start of its scheduling day and the interval added to that, so
/// "one day" means "next day" whether the answer came at breakfast or at
/// 23:59. Added with `Calendar` rather than as seconds so a zone that observes
/// DST still lands on the rollover hour on the far side of a clock change.
func dueAfter(slot: Int, from moment: Date, in timeZone: TimeZone = .current) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let start = schedulingDayStart(of: moment, in: timeZone)
    let days = ladderIntervals[clampSlot(slot)]
    return calendar.date(byAdding: .day, value: days, to: start)
        ?? start.addingTimeInterval(TimeInterval(days) * 86_400)
}

extension LearningCard {
    /// This card's schedule, as a value the transition function can take.
    var scheduling: CardScheduling {
        CardScheduling(
            state: state,
            learningStep: learningStep,
            stage: ladderStage,
            previousStage: previousStage,
            dueAt: dueAt
        )
    }

    /// Takes a locally computed schedule, exactly as `apply(_:)` takes the
    /// server's. `introducedOn` is set here rather than sent, because the day a
    /// card was met is the reader's day and the app is the side that knows it.
    mutating func apply(_ scheduling: CardScheduling, introducedOn day: String) {
        if state == .new && scheduling.state != .new { introducedOn = day }
        state = scheduling.state
        learningStep = scheduling.learningStep
        ladderStage = scheduling.stage
        previousStage = scheduling.previousStage
        dueAt = scheduling.dueAt
    }
}
