//
//  HistoryActionsUITests.swift
//  vista_comicUITests
//
//  Exercises what a reader can do to a 歷史紀錄 record
//  (`comprehension-response-ux` ticket 20): retry from the detail screen only,
//  swipe a row away behind the confirmation, and jump back to the source page.
//
//  Written and build-verified only. Per CLAUDE.md, this environment's simulator
//  cannot reliably initialize XCUITest's accessibility runner, so running this
//  is handed off to a real device or a normal Xcode session.
//
//  Split from `HistoryTabUITests` (ticket 19, browsing and reading) because
//  these tests need a record in a *particular* state and skip otherwise —
//  keeping them apart stops a skipped action test from reading as the tab
//  itself being untested.
//

import XCTest

final class HistoryActionsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// Opens the tab and returns its list, or skips when the backend has no
    /// records to act on — an empty history is ticket 19's subject, not this
    /// file's.
    private func openHistoryList(_ app: XCUIApplication) throws -> XCUIElement {
        let history = app.tabBars.buttons["History"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()

        let firstRow = app.collectionViews.cells.firstMatch
        guard firstRow.waitForExistence(timeout: 10) else {
            throw XCTSkip("No records in history to act on.")
        }
        return firstRow
    }

    /// Retry must be reachable only by opening one record. A row exposing it
    /// would put an expensive call one mis-tap away in a list of many.
    func testRetryIsNeverOfferedOnAListRow() throws {
        let app = launch()
        _ = try openHistoryList(app)

        XCTAssertFalse(
            app.collectionViews.buttons["Retry"].exists,
            "Retry must live on the detail screen only, never on a list row"
        )
    }

    /// The detail screen is where retry lives — offered for a record whose
    /// explanation failed, and withheld from one the model declined, because
    /// retrying that would spend a request to receive the same verdict.
    func testDetailOffersRetryOnlyWhereRetryingCouldHelp() throws {
        let app = launch()
        let firstRow = try openHistoryList(app)
        firstRow.tap()

        XCTAssertTrue(app.navigationBars["Record"].waitForExistence(timeout: 5))

        let declined = app.staticTexts[
            "No explanation was written for this selection. Trying again would return the same answer."
        ]
        let failed = app.staticTexts[
            "The explanation couldn't be written. Your translation above is unaffected."
        ]
        let retry = app.buttons["Retry"]

        if declined.exists {
            XCTAssertFalse(retry.exists, "A declined record must offer no retry")
        } else if failed.exists {
            XCTAssertTrue(retry.exists, "A failed record must offer a retry")
            retry.tap()
            // Retrying re-enqueues on the backend, so the section returns to
            // saying the explanation is being produced.
            XCTAssertTrue(
                app.staticTexts["Being written. You can close this — it'll be waiting in 歷史紀錄."]
                    .waitForExistence(timeout: 10)
            )
        } else {
            throw XCTSkip("Top record is neither failed nor declined.")
        }
    }

    /// The jump opens the page read-only. It is disabled — not hidden — for a
    /// record whose comic has left the library, since that navigation must
    /// fail while the record itself stays readable.
    func testJumpBackOpensTheSourcePageUnlessTheComicIsGone() throws {
        let app = launch()
        let firstRow = try openHistoryList(app)
        firstRow.tap()

        XCTAssertTrue(app.navigationBars["Record"].waitForExistence(timeout: 5))

        let jump = app.buttons["Jump to source page"]
        XCTAssertTrue(jump.exists, "The jump control is present either way")

        if app.staticTexts["No longer in your library"].exists {
            XCTAssertFalse(jump.isEnabled, "A removed comic's record must not offer navigation")
            XCTAssertTrue(app.staticTexts["Original"].exists, "…and stays readable")
            return
        }

        XCTAssertTrue(jump.isEnabled)
        jump.tap()

        // The reader opens on the record's own page; `isPeek` keeps the visit
        // from moving real reading progress, which only the backend can attest.
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 15))

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "history-jump-to-source-page"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Swiping proposes the deletion; the confirmation performs it. Cancelling
    /// must leave the row exactly where it was — deletion is irreversible and
    /// there is no undo.
    func testSwipeAsksBeforeDeletingAndCancelKeepsTheRow() throws {
        let app = launch()
        let firstRow = try openHistoryList(app)
        let rowCountBefore = app.collectionViews.cells.count

        firstRow.swipeLeft()

        let deleteAction = app.collectionViews.buttons["Delete"]
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 5))
        deleteAction.tap()

        XCTAssertTrue(app.alerts["Delete this record?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()

        XCTAssertEqual(
            app.collectionViews.cells.count, rowCountBefore,
            "A cancelled deletion must leave the list untouched"
        )
    }

    /// Confirming removes the row from the list in place — no full reload, so
    /// the rest of the list neither flickers nor scrolls.
    func testConfirmedSwipeDeletesTheRow() throws {
        let app = launch()
        let firstRow = try openHistoryList(app)
        let rowCountBefore = app.collectionViews.cells.count

        firstRow.swipeLeft()

        let deleteAction = app.collectionViews.buttons["Delete"]
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 5))
        deleteAction.tap()

        XCTAssertTrue(app.alerts["Delete this record?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Delete"].tap()

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && app.collectionViews.cells.count == rowCountBefore {
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 0.5)
        }

        // One row fewer, or the empty state where the last record used to be.
        XCTAssertTrue(
            app.collectionViews.cells.count == rowCountBefore - 1
                || app.staticTexts["Nothing here yet"].exists
        )
    }

    /// The detail screen deletes too, and dismisses itself once the backend
    /// confirms — the reader is returned to a list the record has left.
    func testDetailDeletesAndReturnsToTheList() throws {
        let app = launch()
        let firstRow = try openHistoryList(app)
        let rowCountBefore = app.collectionViews.cells.count
        firstRow.tap()

        XCTAssertTrue(app.navigationBars["Record"].waitForExistence(timeout: 5))
        app.buttons["Delete"].tap()

        XCTAssertTrue(app.alerts["Delete this record?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Delete"].tap()

        XCTAssertTrue(
            app.navigationBars["History"].waitForExistence(timeout: 10)
                || app.staticTexts["Nothing here yet"].waitForExistence(timeout: 10),
            "A confirmed delete dismisses the detail screen"
        )
        XCTAssertTrue(
            app.collectionViews.cells.count < rowCountBefore
                || app.staticTexts["Nothing here yet"].exists
        )
    }
}
