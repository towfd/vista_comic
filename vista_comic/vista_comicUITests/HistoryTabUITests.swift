//
//  HistoryTabUITests.swift
//  vista_comicUITests
//
//  Exercises the 歷史紀錄 tab (`comprehension-response-ux` ticket 19): the tab
//  slot 單字本 used to hold, the list, and pushing a record's detail.
//
//  Written and build-verified only. Per CLAUDE.md, this environment's simulator
//  cannot reliably initialize XCUITest's accessibility runner, so running this
//  is handed off to a real device or a normal Xcode session.
//
//  Follows `TabNavigationUITests`' and `ReaderFlowUITests`' conventions: force
//  English so label assertions are locale-stable.
//

import XCTest

final class HistoryTabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// The slot swap itself: History is present, Vocabulary is gone.
    func testHistoryTabReplacesVocabularyInTheTabBar() throws {
        let app = launch()

        let history = app.tabBars.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.tabBars.buttons["Vocabulary"].exists,
            "單字本 should no longer occupy a tab slot"
        )
    }

    /// Opening the tab lands on one of its three legitimate states, and never
    /// on a blank screen. The empty state must read as a feature not yet used
    /// rather than as a failure — which is why it is asserted apart from the
    /// error state.
    func testHistoryTabShowsListEmptyOrErrorButNeverNothing() throws {
        let app = launch()

        let history = app.tabBars.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()

        let list = app.collectionViews.firstMatch
        let empty = app.staticTexts["Nothing here yet"]
        let failed = app.staticTexts["Couldn't connect"]

        // Whichever of the three settles first ends the wait — the loading
        // spinner is the only state that is not an acceptable resting place.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && !(list.exists || empty.exists || failed.exists) {
            _ = list.waitForExistence(timeout: 0.5)
        }

        XCTAssertTrue(
            list.exists || empty.exists || failed.exists,
            "History must render its list, its empty state, or its error state"
        )
        XCTAssertFalse(
            empty.exists && failed.exists,
            "Empty and failed are different facts and must never show together"
        )
    }

    /// Tapping a record pushes the detail, which renders the same vocabulary as
    /// the reader's result sheet.
    func testTappingARecordPushesItsDetail() throws {
        let app = launch()

        let history = app.tabBars.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()

        let firstRow = app.collectionViews.cells.firstMatch
        guard firstRow.waitForExistence(timeout: 10) else {
            // A backend with no records yet is not this test's subject; the
            // empty state has its own assertion above.
            throw XCTSkip("No records in history to open.")
        }
        firstRow.tap()

        XCTAssertTrue(app.navigationBars["Record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Original"].exists)
        XCTAssertTrue(app.staticTexts["Translation"].exists)
        // The shared section renders whatever state the record is in — the
        // heading is present regardless of which one.
        XCTAssertTrue(app.staticTexts["Deeper explanation"].exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "history-record-detail"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
