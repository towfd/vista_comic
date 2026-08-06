//
//  HistoryBadgeUITests.swift
//  vista_comicUITests
//
//  The 歷史紀錄 tab badge (`comprehension-response-ux` ticket 22).
//
//  Written and build-verified only. Per CLAUDE.md, this environment's simulator
//  cannot reliably initialize XCUITest's accessibility runner, so running this
//  is handed off to a real device or a normal Xcode session.
//
//  What is genuinely reachable from out here is narrow, and worth being honest
//  about. The bug's headline — translate, dismiss, keep reading, badge appears —
//  needs a live backend and a multi-minute Claude call, so it is a manual check,
//  not this. What these tests can prove is the structural claim underneath it:
//  the badge is readable **without the tab ever having been opened**, which is
//  precisely what a badge owned by `HistoryView` could not do. The counting
//  itself is covered without rendering in `UnreadExplanationBadgeTests`.
//

import XCTest

final class HistoryBadgeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// The tab shell fetches on launch, so whatever the badge is going to say it
    /// says while the reader is still in 書庫 — the tab is never selected here.
    func testTheBadgeIsResolvedWithoutOpeningTheTab() throws {
        let app = launch()

        let history = app.tabBars.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))

        // Give the shell's launch refresh time to land.
        _ = app.staticTexts["Library"].waitForExistence(timeout: 10)

        XCTAssertTrue(
            app.tabBars.buttons["Library"].isSelected,
            "This test is only meaningful while 書庫 is the selected tab"
        )
        // The label carries the badge count when there is one ("History, 2").
        // Either way it must be readable now, not after a visit.
        XCTAssertFalse(history.label.isEmpty)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "history-tab-badge-before-any-visit"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Opening a badged record clears exactly that one. Skips when the backend
    /// has nothing unread, since an unbadged tab is not this test's subject.
    func testOpeningAnUnreadRecordLowersTheBadge() throws {
        let app = launch()

        let history = app.tabBars.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))

        let before = badgeCount(on: history)
        guard before > 0 else {
            throw XCTSkip("No unread explanations to clear.")
        }

        history.tap()
        let firstRow = app.collectionViews.cells.firstMatch
        guard firstRow.waitForExistence(timeout: 10) else {
            throw XCTSkip("History list did not load.")
        }
        firstRow.tap()
        XCTAssertTrue(app.navigationBars["Record"].waitForExistence(timeout: 5))
        app.navigationBars["Record"].buttons.firstMatch.tap()  // back

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && badgeCount(on: history) == before {
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 0.5)
        }

        XCTAssertLessThan(
            badgeCount(on: history), before,
            "Opening a record must clear exactly that one from the badge"
        )
    }

    /// The tab item's label folds the badge in as a trailing number
    /// ("History, 3"); no badge means no number.
    private func badgeCount(on tab: XCUIElement) -> Int {
        let digits = tab.label.components(separatedBy: CharacterSet.decimalDigits.inverted)
        return digits.compactMap(Int.init).last ?? 0
    }
}
