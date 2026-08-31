//
//  PendingAnswerTests.swift
//  vista_comicTests
//
//  Answering with no network (vocabulary stage 6, ticket 07).
//
//  The property under test is the one the whole design rests on: scheduling is
//  a pure function of a card's state and the answers against it, so replaying
//  the queue over the last good snapshot lands where the server will land when
//  the queue reaches it. Nothing is reconciled — the server recomputes from the
//  same answers and its result simply replaces this.
//

import Foundation
import Testing

@testable import vista_comic

private let day = "2026-08-31"
private let noon = Date(timeIntervalSince1970: 1_756_670_400)

private func card(_ id: Int, state: String = "new", dueIn seconds: TimeInterval = -60) -> LearningCard {
    .preview(
        id: id,
        sourceText: "WORD\(id)",
        kind: "word",
        state: state,
        dueAt: ISO8601DateFormatter().string(from: noon.addingTimeInterval(seconds))
    )
}

private func answer(
    _ cardID: Int,
    correct: Bool,
    at offset: TimeInterval = 0,
    context: ReviewContext = .review,
    token: String = UUID().uuidString
) -> PendingAnswer {
    PendingAnswer(
        cardID: cardID,
        questionType: .clozeTyped,
        isCorrect: correct,
        clientToken: token,
        localDate: day,
        answeredAt: noon.addingTimeInterval(offset),
        context: context
    )
}

@Suite("Replaying what could not be sent")
struct PendingAnswerReplayTests {

    @Test("A queued answer moves the card the same way the server would")
    func aQueuedAnswerMovesTheCard() throws {
        let deck = replaying([answer(1, correct: true)], over: [card(1)], learningSteps: [5, 7, 10])

        let moved = try #require(deck.first)
        #expect(moved.state == .learning)
        #expect(moved.learningStep == 0)
        #expect(moved.dueAt == noon.addingTimeInterval(5 * 60))
    }

    @Test("A wrong answer puts the card back within minutes, so the queue offers it again")
    func aWrongAnswerBringsTheCardBack() throws {
        // The whole of why 錯題區 was cancelled, working with no network.
        let deck = replaying(
            [answer(1, correct: true), answer(1, correct: false, at: 60)],
            over: [card(1)],
            learningSteps: [5, 7, 10]
        )

        let moved = try #require(deck.first)
        #expect(moved.learningStep == 0)
        #expect(moved.dueAt == noon.addingTimeInterval(60 + 5 * 60))
    }

    @Test("Answers are replayed in the order they were given, not the order they were stored")
    func replayFollowsTheAnswerTime() throws {
        // Each answer's effect depends on where the previous one left the card,
        // so the order is load-bearing — and the order that matters is when the
        // reader answered, which is the only thing a flush cannot change.
        let later = answer(1, correct: false, at: 600)
        let earlier = answer(1, correct: true, at: 0)

        let deck = replaying([later, earlier], over: [card(1)], learningSteps: [5, 7, 10])

        let moved = try #require(deck.first)
        #expect(moved.dueAt == noon.addingTimeInterval(600 + 5 * 60))
    }

    @Test("Four correct answers graduate a card offline, exactly as online")
    func aCardCanGraduateOffline() throws {
        let answers = (0..<4).map { answer(1, correct: true, at: TimeInterval($0) * 600) }

        let deck = replaying(answers, over: [card(1)], learningSteps: [5, 7, 10])

        let moved = try #require(deck.first)
        #expect(moved.state == .review)
        #expect(moved.ladderStage == 0)
    }

    @Test("A training answer changes nothing, here as on the server")
    func trainingChangesNothing() throws {
        let deck = replaying(
            [answer(1, correct: false, context: .training)],
            over: [card(1, state: "review")],
            learningSteps: [5, 7, 10]
        )

        let untouched = try #require(deck.first)
        #expect(untouched.state == .review)
        #expect(untouched.dueAt == noon.addingTimeInterval(-60))
    }

    @Test("Meeting a card offline records the day it was met")
    func offlineIntroductionCountsAgainstTheQuota() throws {
        // Otherwise a flight would introduce the whole deck: the quota counts
        // cards met today, and a card met with no network would not be one.
        let deck = replaying([answer(1, correct: true)], over: [card(1)], learningSteps: [5])

        #expect(try #require(deck.first).introducedOn == day)
        #expect(introducedCount(in: deck, on: day) == 1)
    }

    @Test("An answer for a card the snapshot has never heard of is skipped, not fatal")
    func anUnknownCardIsSkipped() {
        let deck = replaying([answer(99, correct: true)], over: [card(1)], learningSteps: [5])

        #expect(deck.count == 1)
        #expect(deck.first?.state == .new)
    }

    @Test("Replaying does not reshuffle the deck")
    func theDeckKeepsItsOrder() {
        let deck = replaying(
            [answer(3, correct: true)],
            over: [card(1), card(2), card(3)],
            learningSteps: [5]
        )

        #expect(deck.map(\.id) == [1, 2, 3])
    }

    @Test("An empty queue changes nothing at all")
    func anEmptyQueueIsATransparentReplay() {
        let deck = [card(1), card(2)]

        #expect(replaying([], over: deck, learningSteps: [5]) == deck)
    }
}

@Suite("The queue itself")
struct PendingAnswerStoreTests {

    @Test("Entries come back oldest first, whatever order they went in")
    func entriesAreOrderedByAnswerTime() {
        let store = InMemoryPendingAnswerStore()
        store.enqueue(answer(1, correct: true, at: 600))
        store.enqueue(answer(2, correct: true, at: 0))

        #expect(store.queued().map(\.cardID) == [2, 1])
    }

    @Test("Two answers to the same card are two entries")
    func nothingIsDeduplicated() {
        // Unlike the card queue, where two taps mean one word. Here the second
        // answer is usually the interesting one: the card came back because the
        // first was wrong.
        let store = InMemoryPendingAnswerStore()
        store.enqueue(answer(1, correct: false))
        store.enqueue(answer(1, correct: true, at: 300))

        #expect(store.queued().count == 2)
    }

    @Test("The oldest go first when the queue is full")
    func theQueueIsBounded() {
        let store = InMemoryPendingAnswerStore(limit: 2)
        store.enqueue(answer(1, correct: true, at: 0))
        store.enqueue(answer(2, correct: true, at: 60))
        store.enqueue(answer(3, correct: true, at: 120))

        #expect(store.queued().map(\.cardID) == [2, 3])
    }

    @Test("Removing takes one entry and leaves the rest")
    func removingIsPrecise() {
        let store = InMemoryPendingAnswerStore()
        let first = answer(1, correct: true, at: 0)
        store.enqueue(first)
        store.enqueue(answer(2, correct: true, at: 60))

        store.remove(first.id)

        #expect(store.queued().map(\.cardID) == [2])
    }

    @Test("An answer survives being written and read back")
    func anAnswerRoundTripsThroughDisk() throws {
        // It is written the moment it is given, so a force-quit mid-session
        // must not lose it — which means every field has to survive `Codable`,
        // including the two enums.
        let original = answer(7, correct: false, context: .training, token: "tok")

        let data = try JSONEncoder().encode([original])
        let restored = try JSONDecoder().decode([PendingAnswer].self, from: data)

        #expect(restored == [original])
        #expect(restored.first?.context == .training)
        #expect(restored.first?.questionType == .clozeTyped)
    }
}
