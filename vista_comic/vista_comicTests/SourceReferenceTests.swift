//
//  SourceReferenceTests.swift
//  vista_comicTests
//
//  The jump-back-to-the-page rules, after they were lifted out of
//  `Features/History/` (vocabulary stage 2, ticket 02).
//
//  These assertions are the point of moving rather than rewriting. They already
//  existed against `ComprehensionRecord` in `HistoryActionsTests`; the same
//  facts are asserted here against the shared type, so that when 歷史紀錄 and
//  its tests are deleted in ticket 03, nothing they were protecting goes with
//  them.
//

import Foundation
import Testing

@testable import vista_comic

@Suite("Jumping back to where a line was read")
struct SourceReferenceTests {

    private let inLibrary = SourceReference(
        comicID: "comic-1",
        chapterID: "chapter-1",
        pageNumber: 12,
        comicTitle: "marrymyhusband"
    )

    @Test("A source still in the library can be jumped to")
    func aSourceStillInTheLibraryCanBeJumpedTo() {
        #expect(inLibrary.canJumpToSource)
    }

    @Test("A comic that has left the library withdraws the jump, not the card")
    func aMissingComicWithdrawsOnlyTheJump() {
        // The title is joined from the live catalog at read time, so nil is not
        // "we didn't fetch it" — it is "this comic is gone". The stored ids
        // would still build a route, and that route would fail.
        var orphan = inLibrary
        orphan = SourceReference(
            comicID: orphan.comicID,
            chapterID: orphan.chapterID,
            pageNumber: orphan.pageNumber,
            comicTitle: nil
        )

        #expect(orphan.canJumpToSource == false)
    }

    @Test("The route points at the exact page")
    func theRoutePointsAtTheExactPage() {
        let route = inLibrary.peekRoute

        #expect(route.comicID == "comic-1")
        #expect(route.chapterID == "chapter-1")
        #expect(route.targetPage == 12)
    }

    @Test("The route is a peek, so re-reading cannot move real progress")
    func theRouteIsAPeek() {
        // The whole reason this is not an ordinary reader route: going back to
        // look at an old bubble must never rewrite where the reader actually
        // is.
        #expect(inLibrary.peekRoute.isPeek)
    }
}
