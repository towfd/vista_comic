//
//  SchedulerParityTests.swift
//  vista_comicTests
//
//  The Swift scheduler against the same table the Python one is tested with
//  (vocabulary stage 6, ticket 07).
//
//  There are deliberately two implementations of this state machine — offline
//  practice cannot ask the server what an answer did — and two implementations
//  is exactly how the sides come to disagree. **Every case below has a twin in
//  `backend/tests/test_scheduler.py`**, with the same shape and the same
//  numbers, so a change made to one and not the other fails a test rather than
//  a reader's schedule.
//

import Foundation
import Testing

@testable import vista_comic

private let answered = Date(timeIntervalSince1970: 1_756_670_400)
private let steps = [5, 7, 10]

private func schedule(
    _ state: CardState,
    step: Int? = nil,
    stage: Int = 0,
    previous: Int? = nil
) -> CardScheduling {
    CardScheduling(
        state: state,
        learningStep: step,
        stage: stage,
        previousStage: previous,
        dueAt: answered.addingTimeInterval(-86_400)
    )
}

private func answer(
    _ current: CardScheduling,
    _ correct: Bool,
    steps list: [Int] = steps,
    at moment: Date = answered
) -> CardScheduling {
    nextSchedule(current, correct: correct, answeredAt: moment, learningSteps: list)
}

private func minutes(_ count: Int) -> Date {
    answered.addingTimeInterval(TimeInterval(count) * 60)
}

private func days(_ count: Int) -> Date {
    Calendar(identifier: .gregorian).date(byAdding: .day, value: count, to: answered)!
}

@Suite("The Swift scheduler matches the backend's")
struct SchedulerParityTests {

    @Test("A new card enters the learning steps")
    func aNewCardEntersTheLearningSteps() {
        let landed = answer(schedule(.new), true)

        #expect(landed.state == .learning)
        #expect(landed.learningStep == 0)
        #expect(landed.dueAt == minutes(5))
    }

    @Test("A first answer that is wrong still only reaches the first step")
    func aWrongFirstAnswerReachesTheFirstStep() {
        let landed = answer(schedule(.new), false)

        #expect(landed.state == .learning)
        #expect(landed.learningStep == 0)
        #expect(landed.dueAt == minutes(5))
    }

    @Test("A correct answer advances one step", arguments: [(0, 1, 7), (1, 2, 10)])
    func aCorrectAnswerAdvancesOneStep(_ move: (Int, Int, Int)) {
        let landed = answer(schedule(.learning, step: move.0), true)

        #expect(landed.state == .learning)
        #expect(landed.learningStep == move.1)
        #expect(landed.dueAt == minutes(move.2))
    }

    @Test("A wrong answer restarts the steps", arguments: [0, 1, 2])
    func aWrongAnswerRestartsTheSteps(_ step: Int) {
        let landed = answer(schedule(.learning, step: step), false)

        #expect(landed.learningStep == 0)
        #expect(landed.dueAt == minutes(5))
    }

    @Test("Clearing the last step graduates to the first slot")
    func clearingTheLastStepGraduates() {
        let landed = answer(schedule(.learning, step: 2), true)

        #expect(landed.state == .review)
        #expect(landed.learningStep == nil)
        #expect(landed.stage == 0)
        #expect(landed.dueAt == days(1))
    }

    @Test("A correct answer climbs one slot")
    func aCorrectAnswerClimbsOneSlot() {
        let landed = answer(schedule(.review, stage: 2), true)

        #expect(landed.stage == 3)
        #expect(landed.dueAt == days(21))
    }

    @Test("The top slot clamps rather than overflowing")
    func theTopSlotClamps() {
        let landed = answer(schedule(.review, stage: ladderTopRung), true)

        #expect(landed.stage == ladderTopRung)
        #expect(landed.dueAt == days(365))
    }

    @Test("A wrong answer starts relearning and remembers one slot down")
    func aLapseRemembersOneSlotDown() {
        let landed = answer(schedule(.review, stage: 4), false)

        #expect(landed.state == .relearning)
        #expect(landed.learningStep == 0)
        #expect(landed.previousStage == 3)
        #expect(landed.dueAt == minutes(5))
    }

    @Test("A lapse from the top returns to the slot below it")
    func aLapseFromTheTopReturnsOneSlotDown() {
        // Sixty days does not become one. Judging is an exact match on
        // production, so a wrong answer is often a slip.
        var card = answer(schedule(.review, stage: 6), false)
        #expect(card.previousStage == 5)

        for _ in 0..<3 { card = answer(card, true) }

        #expect(card.state == .review)
        #expect(card.stage == 5)
        #expect(card.dueAt == days(150))
    }

    @Test("A lapse from the bottom slot stays at the bottom")
    func aLapseFromTheBottomStays() {
        #expect(answer(schedule(.review, stage: 0), false).previousStage == 0)
    }

    @Test("The remembered slot is cleared once it is used")
    func theRememberedSlotIsCleared() {
        let graduated = answer(schedule(.relearning, step: 2, previous: 5), true)
        #expect(graduated.stage == 5)
        #expect(graduated.previousStage == nil)

        // A hundred and fifty days later, which is when it is next asked.
        // Answering it at the instant it graduated would now change nothing,
        // and it is the honest reading of the story anyway.
        #expect(answer(graduated, false, at: graduated.dueAt).previousStage == 4)
    }

    @Test("A review card answered early does not move", arguments: [true, false])
    func anEarlyAnswerDoesNotMove(_ correct: Bool) {
        // The fifth answer in the bug report: a card graduated onto one day,
        // was asked again in the same session because this app's deck had not
        // heard about it, and was promoted to three days. Nothing had happened
        // in between that three days could be a measurement of.
        //
        // Wrong answers are covered by the same rule for symmetry: an answer
        // that cannot earn a slot must not be able to cost one.
        var subject = schedule(.review, stage: 2)
        subject.dueAt = days(1)

        #expect(answer(subject, correct) == subject)
    }

    @Test("The moment it is due, it moves again")
    func onTheDueMomentItMovesAgain() {
        // The boundary is `answeredAt < dueAt`, not a grace period. A card due
        // at eight answered at eight is being answered on time.
        var subject = schedule(.review, stage: 2)
        subject.dueAt = days(1)

        #expect(answer(subject, true, at: subject.dueAt).stage == 3)
    }

    @Test("A learning card answered early still advances")
    func anEarlyLearningAnswerStillAdvances() {
        // `learnAheadWindow` offers a learning card up to twenty minutes early
        // on purpose, so the rule above must not reach it — a session with
        // three cards on five-minute timers could otherwise never move.
        var subject = schedule(.learning, step: 0)
        subject.dueAt = minutes(4)

        #expect(answer(subject, true).learningStep == 1)
    }

    @Test("The scheduler reads no clock of its own")
    func theSchedulerReadsNoClock() {
        // What offline practice rests on: an answer given this morning is
        // scheduled from this morning, however late it is processed.
        let longAgo = Date(timeIntervalSince1970: 1_735_000_000)

        let landed = answer(schedule(.learning, step: 0), true, at: longAgo)

        #expect(landed.dueAt == longAgo.addingTimeInterval(7 * 60))
    }

    @Test("A different step list schedules differently")
    func adifferentStepListSchedules() {
        let landed = answer(schedule(.learning, step: 0), true, steps: [1, 20])

        #expect(landed.dueAt == minutes(20))
        #expect(answer(landed, true, steps: [1, 20]).state == .review)
    }

    @Test("A single step graduates on the first correct answer")
    func aSingleStepGraduates() {
        #expect(answer(schedule(.learning, step: 0), true, steps: [3]).state == .review)
    }

    @Test("A card past the end of a shortened list is clamped, not lost")
    func aShortenedListClamps() {
        let landed = answer(schedule(.learning, step: 2), true, steps: [5, 7])

        #expect(landed.state == .review)
        #expect(landed.dueAt == days(1))
    }

    @Test("An unusable step list falls back rather than stranding the card")
    func anUnusableListFallsBack() {
        // **The one place the two implementations differ, on purpose.** The
        // backend raises, because a route can answer 422 and a caller can be
        // told. Here there is nobody to tell, and refusing to schedule would
        // leave the card with a due date in the past forever.
        let landed = answer(schedule(.new), true, steps: [])

        #expect(landed.state == .learning)
        #expect(landed.dueAt == minutes(5))
    }
}
