//
//  PracticeQueueTests.swift
//  vista_comicTests
//
//  What to ask next, and when to stop (vocabulary stage 6, ticket 03).
//
//  The clock is a parameter throughout, which is the point: a session in
//  airplane mode is scheduled from when the reader answered, and a test needs
//  to stand at 20:07 without waiting for it.
//

import Foundation
import Testing

@testable import vista_comic

private let now = Date(timeIntervalSince1970: 1_756_600_000)
private let today = "2026-08-31"
private let settings = StudySettings(learningSteps: [5, 7, 10], newCardsPerDay: 15)

private func iso(_ offset: TimeInterval) -> String {
    let formatter = ISO8601DateFormatter()
    return formatter.string(from: now.addingTimeInterval(offset))
}

private func card(
    _ id: Int,
    state: String,
    dueIn seconds: TimeInterval = -60,
    stage: Int = 0,
    step: Int? = nil,
    introducedOn: String? = nil,
    createdAt: String = "2026-08-01T10:00:00Z"
) -> LearningCard {
    .preview(
        id: id,
        sourceText: "WORD\(id)",
        kind: "word",
        state: state,
        learningStep: step,
        ladderStage: stage,
        introducedOn: introducedOn,
        dueAt: iso(seconds),
        createdAt: createdAt
    )
}

private func pick(_ deck: [LearningCard], avoiding last: Int? = nil) -> Result<LearningCard, QueueEmpty> {
    nextCard(from: deck, settings: settings, now: now, today: today, avoiding: last)
}

@Suite("What the queue offers next")
struct PracticeQueueOrderTests {

    @Test("A learning card that is due comes before a review card that is due")
    func learningLeadsReview() throws {
        // Minutes matter more than days: a card the reader is in the middle of
        // learning is the one they are closest to keeping.
        let deck = [
            card(1, state: "review", dueIn: -3600),
            card(2, state: "learning", dueIn: -60, step: 1),
        ]

        #expect(try pick(deck).get().id == 2)
    }

    @Test("A relearning card counts as learning")
    func relearningLeadsToo() throws {
        let deck = [
            card(1, state: "review", dueIn: -3600),
            card(2, state: "relearning", dueIn: -60, step: 0),
        ]

        #expect(try pick(deck).get().id == 2)
    }

    @Test("Due cards come before new ones")
    func dueBeatsNew() throws {
        let deck = [card(1, state: "new"), card(2, state: "review", dueIn: -60)]

        #expect(try pick(deck).get().id == 2)
    }

    @Test("The card that has been waiting longest comes first")
    func theLongestWaitLeads() throws {
        let deck = [
            card(1, state: "review", dueIn: -60),
            card(2, state: "review", dueIn: -7200),
        ]

        #expect(try pick(deck).get().id == 2)
    }

    @Test("New cards are met in the order they were collected")
    func newCardsFollowCollectionOrder() throws {
        // Anki's default too. Any other order would be inventing a curriculum
        // out of a list the reader built by reading.
        let deck = [
            card(1, state: "new", createdAt: "2026-08-20T10:00:00Z"),
            card(2, state: "new", createdAt: "2026-08-02T10:00:00Z"),
        ]

        #expect(try pick(deck).get().id == 2)
    }

    @Test("The same card is not offered twice in a row when there is a choice")
    func theSameCardIsNotRepeated() throws {
        let deck = [
            card(1, state: "review", dueIn: -7200),
            card(2, state: "review", dueIn: -60),
        ]

        #expect(try pick(deck, avoiding: 1).get().id == 2)
    }

    @Test("A one-card deck offers that card again rather than ending")
    func aSingleCardRepeats() throws {
        // Which is the honest answer: there is something to do, and refusing
        // to offer it would end a session that is not over.
        let deck = [card(1, state: "learning", dueIn: -60, step: 0)]

        #expect(try pick(deck, avoiding: 1).get().id == 1)
    }
}

@Suite("The day's new-card quota")
struct NewCardQuotaTests {

    @Test("Cards met today count against it")
    func introducedCardsCount() {
        let deck = [
            card(1, state: "learning", introducedOn: today),
            card(2, state: "learning", introducedOn: today),
            card(3, state: "learning", introducedOn: "2026-08-30"),
        ]

        #expect(introducedCount(in: deck, on: today) == 2)
    }

    @Test("New cards stop once the quota is spent")
    func theQuotaStopsNewCards() {
        let spent = StudySettings(learningSteps: [5], newCardsPerDay: 1)
        let deck = [
            card(1, state: "learning", dueIn: 3600, introducedOn: today),
            card(2, state: "new"),
        ]

        let result = nextCard(from: deck, settings: spent, now: now, today: today)

        #expect(result == .failure(.dayIsDone))
    }

    @Test("Yesterday's unfinished learning cards do not spend today's quota")
    func yesterdaysLearningCardsAreFree() throws {
        // If they did, a day that went badly would crowd out the next day's new
        // words, and the deck would introduce fewer and fewer of them.
        let spent = StudySettings(learningSteps: [5], newCardsPerDay: 1)
        let deck = [
            card(1, state: "learning", dueIn: 3600, introducedOn: "2026-08-30"),
            card(2, state: "new"),
        ]

        #expect(try nextCard(from: deck, settings: spent, now: now, today: today).get().id == 2)
    }

    @Test("A quota of zero still lets due cards through")
    func zeroNewCardsIsNotAnEmptyDay() throws {
        // Zero is a choice, not a mistake: clear the backlog without meeting
        // more.
        let none = StudySettings(learningSteps: [5], newCardsPerDay: 0)
        let deck = [card(1, state: "new"), card(2, state: "review", dueIn: -60)]

        #expect(try nextCard(from: deck, settings: none, now: now, today: today).get().id == 2)
    }
}

@Suite("Learn-ahead")
struct LearnAheadTests {

    @Test("A card due in three minutes is offered when nothing else is")
    func aSoonCardIsPulledForward() throws {
        // Without this a deck this size would stall: three cards on five-minute
        // timers and nothing else to ask means sitting and waiting.
        let deck = [card(1, state: "learning", dueIn: 180, step: 0)]

        #expect(try pick(deck).get().id == 1)
    }

    @Test("It does not fire while something is actually due")
    func itYieldsToRealWork() throws {
        let deck = [
            card(1, state: "learning", dueIn: 180, step: 0),
            card(2, state: "review", dueIn: -60),
        ]

        #expect(try pick(deck).get().id == 2)
    }

    @Test("A card due in forty minutes is never pulled forward")
    func farFutureCardsStayPut() {
        let deck = [card(1, state: "learning", dueIn: 2400, step: 0)]

        #expect(pick(deck) == .failure(.dayIsDone))
    }

    @Test("It does not reach review cards, only learning ones")
    func reviewCardsAreNotPulledForward() {
        // A card due tomorrow being asked today would be the drilling the
        // scheduler is designed to avoid — and a review card is never minutes
        // away, so pulling one forward could only ever be wrong.
        let deck = [card(1, state: "review", dueIn: 300)]

        #expect(pick(deck) == .failure(.dayIsDone))
    }
}

@Suite("When the session ends")
struct SessionEndTests {

    @Test("An empty deck says so, rather than saying the day is done")
    func anEmptyDeckIsItsOwnCase() {
        // The two send the reader to different places: one means "collect some
        // words", the other means "come back tomorrow".
        #expect(pick([]) == .failure(.deckIsEmpty))
    }

    @Test("Nothing due and no quota left means the day is done")
    func aFinishedDayIsReported() {
        let deck = [
            card(1, state: "review", dueIn: 86_400),
            card(2, state: "new", introducedOn: nil),
        ]
        let spent = StudySettings(learningSteps: [5], newCardsPerDay: 0)

        #expect(nextCard(from: deck, settings: spent, now: now, today: today) == .failure(.dayIsDone))
    }
}

@Suite("Training draws from what has been met")
struct TrainingPoolTests {

    @Test("New cards never appear")
    func newCardsAreExcluded() {
        // A word meeting the reader for the first time in a mode that schedules
        // nothing would be met and then forgotten by the system.
        let deck = [card(1, state: "new"), card(2, state: "review")]

        #expect(trainableCards(in: deck).map(\.id) == [2])
    }

    @Test("Every other state does")
    func everyMetStateIsTrainable() {
        let deck = [
            card(1, state: "learning"),
            card(2, state: "review"),
            card(3, state: "relearning"),
        ]

        #expect(trainableCards(in: deck).count == 3)
    }

    @Test("A deck with nothing met offers no question at all")
    func anUnmetDeckHasNoTraining() {
        #expect(nextTrainingItem(from: [card(1, state: "new")]) == nil)
    }

    @Test("The same card is not asked twice in a row")
    func trainingAvoidsRepeats() throws {
        let deck = [card(1, state: "review"), card(2, state: "review")]

        let item = try #require(nextTrainingItem(from: deck, avoiding: 1))

        #expect(item.card.id == 2)
    }

    @Test("A pool of one repeats rather than ending")
    func aSinglePoolRepeats() throws {
        // Endless means endless. Ending because the only card was just asked
        // would make it the opposite.
        let deck = [card(1, state: "review")]

        let item = try #require(nextTrainingItem(from: deck, avoiding: 1))

        #expect(item.card.id == 1)
    }
}

/// How many cards a scheduled session still has to get through (stage 6,
/// ticket 11).
///
/// The suite exists for its first test. Everything else here describes the
/// count; that one pins it to the queue, so the screen and the session can
/// never disagree about what "finished" means.
@Suite("How many are left")
struct RemainingCardsTests {

    private func left(_ deck: [LearningCard], _ config: StudySettings = settings) -> Int {
        remainingCards(from: deck, settings: config, now: now, today: today)
    }

    @Test("The count is zero exactly when the queue has nothing to offer")
    func zeroMeansFinished() {
        let spent = (1...15).map {
            card($0, state: "review", dueIn: 86_400, introducedOn: today)
        }
        let decks: [[LearningCard]] = [
            // Nothing collected at all.
            [],
            // Everything reviewed; nothing comes back today.
            [card(1, state: "review", dueIn: 86_400)],
            // A learning card, but further out than the learn-ahead window.
            [card(1, state: "learning", dueIn: 40 * 60, step: 1)],
            // New cards left, but the day's quota is spent on other cards.
            spent + [card(99, state: "new")],
            // One due card.
            [card(1, state: "review", dueIn: -60)],
            // One new card and room for it.
            [card(1, state: "new")],
            // A learning card inside the learn-ahead window.
            [card(1, state: "learning", dueIn: 10 * 60, step: 1)],
        ]

        for deck in decks {
            let queueIsEmpty = (try? pick(deck).get()) == nil
            #expect((left(deck) == 0) == queueIsEmpty)
        }
    }

    @Test("New cards count only while the day's quota has room")
    func quotaBoundsTheCount() {
        let deck = (1...5).map { card($0, state: "new") }

        #expect(left(deck) == 5)
        #expect(left(deck, StudySettings(learningSteps: [5, 7, 10], newCardsPerDay: 2)) == 2)
    }

    @Test("The quota never counts more new cards than the deck holds")
    func theDeckBoundsTheQuota() {
        // Room for fifteen, two collected. Counting the room rather than the
        // cards would promise thirteen questions that do not exist.
        #expect(left([card(1, state: "new"), card(2, state: "new")]) == 2)
    }

    @Test("Cards met earlier today have already spent their share of the quota")
    func introducedCardsShrinkTheQuota() {
        let met = (1...14).map {
            card($0, state: "review", dueIn: 86_400, introducedOn: today)
        }
        let deck = met + [card(20, state: "new"), card(21, state: "new")]

        // One slot left in the day, so one of the two new cards.
        #expect(left(deck) == 1)
    }

    @Test("A learning card that is already due is counted once, not twice")
    func noDoubleCountingAcrossTheWindow() {
        // Due now *and* inside the learn-ahead window, which is the overlap the
        // count has to resolve — it is one question either way.
        #expect(left([card(1, state: "learning", dueIn: -60, step: 1)]) == 1)
    }

    @Test("Introducing a new card leaves the count unchanged")
    func introducingMovesRatherThanRemoves() {
        let before = [card(1, state: "new")]
        // The same card after being met: it has spent a quota slot and is now
        // waiting on a five-minute step. It moved between the two things the
        // count adds up, so the total must not move.
        let after = [
            card(1, state: "learning", dueIn: 300, step: 0, introducedOn: today)
        ]

        #expect(left(before) == 1)
        #expect(left(after) == 1)
    }

    @Test("A card answered wrong stays counted; one that graduates leaves")
    func onlyLeavingTodayDropsTheCount() {
        let due = [card(1, state: "review", dueIn: -60)]
        // Wrong: back onto a learning step, still coming back this session.
        let lapsed = [card(1, state: "relearning", dueIn: 300, step: 0)]
        // Right: onto the interval table, gone until tomorrow at the earliest.
        let graduated = [card(1, state: "review", dueIn: 86_400, stage: 1)]

        #expect(left(due) == 1)
        #expect(left(lapsed) == 1)
        #expect(left(graduated) == 0)
    }
}
