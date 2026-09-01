//
//  PieceTrayTests.swift
//  vista_comicTests
//
//  Moving pieces between the pool and the answer.
//
//  Written because of one complaint from a real session: a rearrangement could
//  only be built left to right, so realising the word you need goes *before*
//  what you have already placed meant taking every piece back one at a time.
//  Everything below is about a piece landing somewhere other than the end.
//

import Foundation
import Testing

@testable import vista_comic

@Suite("Arranging pieces")
struct PieceTrayTests {

    @Test("Placing with no target puts the piece on the end")
    func placingAppendsByDefault() {
        var tray = PieceTray(available: ["MÌNH", "CÒN"])

        tray.place(from: 0)
        tray.place(from: 0)

        #expect(tray.placed == ["MÌNH", "CÒN"])
        #expect(tray.available.isEmpty)
    }

    @Test("A piece can land in front of one already placed")
    func placingCanInsert() {
        // The whole point of the change.
        var tray = PieceTray(available: ["CÒN", "MÌNH"])
        tray.place(from: 0)

        tray.place(from: 0, before: 0)

        #expect(tray.placed == ["MÌNH", "CÒN"])
    }

    @Test("Any placed piece can be taken back, not only the last")
    func anyPieceCanBeTakenBack() {
        var tray = PieceTray(available: ["A", "B", "C"])
        for _ in 0..<3 { tray.place(from: 0) }

        tray.takeBack(at: 0)

        #expect(tray.placed == ["B", "C"])
        #expect(tray.available == ["A"])
    }

    @Test("A placed piece can be moved to a different position")
    func placedPiecesCanBeReordered() {
        var tray = PieceTray(available: ["A", "B", "C"])
        for _ in 0..<3 { tray.place(from: 0) }

        tray.move(from: 2, before: 0)

        #expect(tray.placed == ["C", "A", "B"])
    }

    @Test("Moving a piece rightwards lands where the reader aimed")
    func movingRightwardsAccountsForTheGapItLeaves() {
        // Removing the piece first shifts everything after it, so a naive
        // insert at the target index lands one place early. Off-by-one here
        // would be invisible in code review and obvious on a phone.
        var tray = PieceTray(available: ["A", "B", "C"])
        for _ in 0..<3 { tray.place(from: 0) }

        tray.move(from: 0, before: 2)

        #expect(tray.placed == ["B", "A", "C"])
    }

    @Test("Moving a piece onto itself changes nothing")
    func movingOntoItselfIsANoOp() {
        var tray = PieceTray(available: ["A", "B"])
        for _ in 0..<2 { tray.place(from: 0) }

        tray.move(from: 1, before: 1)

        #expect(tray.placed == ["A", "B"])
    }

    @Test("Identical pieces are addressed by position, never by text")
    func repeatedWordsAreDistinguishedByPosition() {
        // Two of the deck's sentences repeat a word — `CÒN` and `MÌNH` in one,
        // `LỢI` in another — so the screen shows pieces the reader cannot tell
        // apart. Taking back "the CÒN" would be ambiguous; taking back the
        // second one is not.
        var tray = PieceTray(available: ["CÒN", "MÌNH", "CÒN"])
        for _ in 0..<3 { tray.place(from: 0) }

        tray.takeBack(at: 2)

        #expect(tray.placed == ["CÒN", "MÌNH"])
        #expect(tray.available == ["CÒN"])
    }

    @Test("A target past the end lands on the end rather than being refused")
    func anOutOfRangeTargetIsClamped() {
        // A drop lands where the finger was, and the finger is not obliged to
        // be inside the row.
        var tray = PieceTray(available: ["A", "B"])
        tray.place(from: 0)

        tray.place(from: 0, before: 99)

        #expect(tray.placed == ["A", "B"])
    }

    @Test("A source that does not exist is ignored rather than crashing")
    func anOutOfRangeSourceIsIgnored() {
        var tray = PieceTray(available: ["A"])

        tray.place(from: 5)
        tray.takeBack(at: 5)
        tray.move(from: 5, before: 0)

        #expect(tray.placed.isEmpty)
        #expect(tray.available == ["A"])
    }

    @Test("What is judged is the placed pieces, joined")
    func theProducedAnswerIsWhatIsJudged() {
        var tray = PieceTray(available: ["MÌNH", "CÒN"])
        tray.place(from: 1)
        tray.place(from: 0)

        #expect(tray.produced == "CÒN MÌNH")
    }

    @Test("An empty tray produces nothing and knows it")
    func anEmptyTrayIsEmpty() {
        #expect(PieceTray(available: ["A"]).isEmpty)
        #expect(PieceTray(available: ["A"]).produced.isEmpty)
    }
}
