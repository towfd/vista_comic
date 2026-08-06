//
//  TabNavigationUITests.swift
//  vista_comicUITests
//
//  Covers the tab-bar-navigation restructuring (M4 kickoff): the app now
//  launches into a 書庫/歷史紀錄 TabView instead of a bare NavigationStack.
//  (The second slot held 單字本 when this was written; ticket 21 removed it.)
//  Asserts both tabs are reachable and that switching away and back
//  preserves 書庫's navigation state rather than resetting it.
//
//  Scroll-position preservation (named alongside navigation state in the
//  spec's user stories) is not separately exercised here: the real library
//  behind this test currently has only 2 comics, each a fixed ~147pt row
//  (see `ComicListView`), which fit on screen without scrolling on any
//  current device — a swipe gesture would be a no-op, asserting nothing.
//  Navigation-stack preservation is the stronger proof anyway: SwiftUI's
//  `TabView` keeps each static tab's view hierarchy alive rather than
//  recreating it on switch, and that's the same mechanism a nested
//  `ScrollView`'s offset would rely on — if the pushed chapter list survives
//  the round trip below, scroll position would too, for the same reason.
//

import XCTest

final class TabNavigationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTabsAreReachableAndLibraryStateIsPreserved() throws {
        let app = XCUIApplication()
        // Force English so assertions on visible text are stable regardless of
        // the host locale (the UI is localization-ready with English keys).
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // 書庫 is selected by default: the library loads without an extra tap.
        // Asserts on the real backend's actual library content (2 comics:
        // marrymyhusband / marrymyhusband2), not placeholder sample titles.
        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["marrymyhusband"].exists)

        // Push one level deeper (into a chapter list) so we have navigation
        // state to check for preservation, not just loaded library data.
        let chapterButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'chapter('")
        ).firstMatch
        XCTAssertTrue(chapterButton.waitForExistence(timeout: 5))
        chapterButton.tap()
        XCTAssertTrue(app.staticTexts["Chapter 1"].waitForExistence(timeout: 5))

        // Switch to 歷史紀錄: whichever of its states settles, never blank and
        // never a crash. Which one it lands on is `HistoryTabUITests`' subject;
        // what matters here is that the other tab's content is gone.
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Chapter 1"].exists, "書庫's chapter list should not be visible under 歷史紀錄")

        // Switch back to 書庫: the chapter list should still be on screen —
        // proof the tab's navigation state was preserved, not reset to the
        // library root or reloaded from scratch.
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Chapter 1"].exists, "Returning to 書庫 should preserve the pushed chapter list, not pop back to the library root")
    }
}
