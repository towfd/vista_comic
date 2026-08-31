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
/// A first answer that is wrong still only reaches the first step: there is
/// nothing below the bottom, and inventing a punishment there would charge the
/// reader for meeting a word.
///
/// Graduating returns to `previousStage` when there is one, which is what makes
/// a lapse cost one slot instead of everything — and it is cleared once used,
/// so a second lapse from slot 5 returns to 4 rather than to whatever the first
/// remembered.
func nextSchedule(
    _ current: CardScheduling,
    correct: Bool,
    answeredAt: Date,
    learningSteps: [Int]
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
            dueAt: dueAfter(slot: slot, from: answeredAt)
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
        if correct {
            let slot = clampSlot(current.stage + 1)
            return CardScheduling(
                state: .review,
                learningStep: nil,
                stage: slot,
                previousStage: nil,
                dueAt: dueAfter(slot: slot, from: answeredAt)
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

/// When a card on `slot` answered at `moment` comes back.
///
/// Counted from the answer rather than from the previous due date: a card
/// answered four days late is not owed those four days back.
func dueAfter(slot: Int, from moment: Date) -> Date {
    Calendar(identifier: .gregorian).date(
        byAdding: .day, value: ladderIntervals[clampSlot(slot)], to: moment
    ) ?? moment.addingTimeInterval(TimeInterval(ladderIntervals[clampSlot(slot)]) * 86_400)
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
