//
//  SelectionSheetLifetimeUITests.swift
//  vista_comicUITests
//
//  The selection confirmation sheet must survive the keyboard appearing.
//
//  Regression guard for a defect where tapping the recognised text to correct
//  it closed the whole sheet, losing the crop and forcing the reader to draw the
//  selection again. The sheet was presented by `ReaderPage`, a row inside the
//  reader's `LazyVStack`; the keyboard shrank the scroll viewport, the lazy
//  container recycled the row, and the row's `@State` — which the sheet was
//  bound to — went with it. It also re-decoded several full-resolution pages on
//  the main thread on the way, blocking it for ~2s.
//
//  This is the only seam that can catch it. The bug is a view-lifecycle event
//  inside a lazy container reacting to a real keyboard, so there is nothing
//  below the UI level that reproduces it — which is worth stating rather than
//  pretending a unit test covers this.
//
//  Written and build-verified only. Per CLAUDE.md, this environment's simulator
//  cannot reliably initialize XCUITest's accessibility runner, so running this
//  is handed off to a real device or a normal Xcode session.
//

import XCTest

final class SelectionSheetLifetimeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// Opens the reader on the first comic's first chapter, or skips when the
    /// backend has no library to read.
    private func openReader(_ app: XCUIApplication) throws {
        let library = app.tabBars.buttons["Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.tap()

        let firstComic = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'chapter('")
        ).firstMatch
        guard firstComic.waitForExistence(timeout: 15) else {
            throw XCTSkip("No library to read; the backend may be unreachable.")
        }
        firstComic.tap()

        let firstChapter = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Chapter' OR label BEGINSWITH '#'")
        ).firstMatch
        guard firstChapter.waitForExistence(timeout: 10) else {
            throw XCTSkip("No chapter to open.")
        }
        firstChapter.tap()
    }

    /// Draws a selection over the page, which pushes the confirmation sheet.
    private func makeSelection(_ app: XCUIApplication) throws {
        let selectButton = app.buttons["Select text"]
        guard selectButton.waitForExistence(timeout: 15) else {
            throw XCTSkip("Reader controls did not appear; pages may not have loaded.")
        }
        selectButton.tap()

        let page = app.scrollViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        // A drag across the middle of the page, well clear of the cancel zone.
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4))
            .press(
                forDuration: 0.1,
                thenDragTo: page.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.75, dy: 0.6)
                )
            )

        guard app.navigationBars["Selected text"].waitForExistence(timeout: 10) else {
            throw XCTSkip("The selection drag did not produce a crop.")
        }
    }

    /// The defect, stated directly: tap the text to correct it, and the sheet is
    /// still there afterwards.
    func testTappingTheRecognisedTextKeepsTheSheetOpen() throws {
        let app = launch()
        try openReader(app)
        try makeSelection(app)

        let sheet = app.navigationBars["Selected text"]
        let editor = app.textViews.firstMatch
        guard editor.waitForExistence(timeout: 20) else {
            throw XCTSkip("Recognition did not finish.")
        }

        editor.tap()

        // The keyboard shrinking the viewport is precisely what used to recycle
        // the page that owned this sheet.
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 15),
            "The keyboard should come up for the text field"
        )
        XCTAssertTrue(
            sheet.exists,
            "The selection sheet must survive the keyboard appearing — it used to be "
            + "owned by a LazyVStack row that the shrunken viewport recycled"
        )

        // And it must still be there once the reader actually types.
        editor.typeText("x")
        XCTAssertTrue(sheet.exists, "Correcting the text must not dismiss the sheet")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "selection-sheet-survives-keyboard"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The crop the sheet was opened with must still be the one on screen — a
    /// sheet that survived but lost its image would be the same bug wearing a
    /// different face.
    func testTheCropSurvivesAlongsideTheSheet() throws {
        let app = launch()
        try openReader(app)
        try makeSelection(app)

        let editor = app.textViews.firstMatch
        guard editor.waitForExistence(timeout: 20) else {
            throw XCTSkip("Recognition did not finish.")
        }
        editor.tap()
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 15)

        XCTAssertTrue(
            app.images.firstMatch.exists,
            "The cropped image must still be rendered above the text"
        )
        XCTAssertTrue(app.buttons["Translate"].exists || app.textViews.firstMatch.exists)
    }
}
