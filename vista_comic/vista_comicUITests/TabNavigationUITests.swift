//
//  TabNavigationUITests.swift
//  vista_comicUITests
//
//  Covers the tab-bar-navigation restructuring (M4 kickoff): the app now
//  launches into a 書庫/單字本 TabView instead of a bare NavigationStack.
//  Asserts both tabs are reachable and that switching away and back
//  preserves 書庫's navigation state rather than resetting it.
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
        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Frieren"].exists)

        // Push one level deeper (into a chapter list) so we have navigation
        // state to check for preservation, not just loaded library data.
        let chapterButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'chapter('")
        ).firstMatch
        XCTAssertTrue(chapterButton.waitForExistence(timeout: 5))
        chapterButton.tap()
        XCTAssertTrue(app.staticTexts["Chapter 1"].waitForExistence(timeout: 5))

        // Switch to 單字本: a clear placeholder, not blank and not a crash.
        app.tabBars.buttons["Learning Record"].tap()
        XCTAssertTrue(app.staticTexts["Nothing saved yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Chapter 1"].exists, "書庫's chapter list should not be visible under 單字本")

        // Switch back to 書庫: the chapter list should still be on screen —
        // proof the tab's navigation state was preserved, not reset to the
        // library root or reloaded from scratch.
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Chapter 1"].exists, "Returning to 書庫 should preserve the pushed chapter list, not pop back to the library root")
    }
}
