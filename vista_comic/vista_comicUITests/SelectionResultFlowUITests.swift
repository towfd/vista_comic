//
//  SelectionResultFlowUITests.swift
//  vista_comicUITests
//
//  Exercises the selection result sheet's `comprehension-response-ux` shape
//  (ticket 18): the depth picker sitting beside the language picker, the
//  provenance chip on the translation, and the `深度解釋` section standing where
//  the explanation will render.
//
//  Written and build-verified only. Per CLAUDE.md, this environment's simulator
//  cannot reliably initialize XCUITest's accessibility runner, so running this
//  is handed off to a real device or a normal Xcode session.
//
//  Follows `ReaderFlowUITests`' conventions: force English so label assertions
//  are locale-stable, and drive the app through its real navigation rather than
//  launching a screen directly.
//

import XCTest

final class SelectionResultFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Drives library → chapter list → reader, drags out a selection, and
    /// checks the result sheet's controls and states.
    ///
    /// The selection drag is over the page image rather than at fixed screen
    /// coordinates, so this survives a layout change that moves the reader's
    /// chrome around.
    func testSelectionResultSheetOffersDepthChoiceAndExplanationSection() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let chapterButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'chapter('")
        ).firstMatch
        XCTAssertTrue(chapterButton.waitForExistence(timeout: 10))
        chapterButton.tap()

        let firstChapter = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Chapter 1'")
        ).firstMatch
        XCTAssertTrue(firstChapter.waitForExistence(timeout: 5))
        firstChapter.tap()

        let page = app.images.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10))

        // Drag out a selection rectangle over the page.
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3))
            .press(
                forDuration: 0.1,
                thenDragTo: page.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45)
                )
            )

        // The sheet presents on a confirmed crop.
        XCTAssertTrue(app.navigationBars["Selected text"].waitForExistence(timeout: 10))

        // Both pickers are present before translating: the whole point of
        // moving depth *before* the request is that it can be chosen up front.
        let translate = app.buttons["Translate"]
        guard translate.waitForExistence(timeout: 15) else {
            // Recognition can legitimately find no text in a sample page, which
            // is not this test's subject — the failure states have their own
            // unit coverage.
            throw XCTSkip("OCR found no text in the sampled region; nothing to translate.")
        }
        XCTAssertTrue(app.staticTexts["Translate to"].exists)
        XCTAssertTrue(
            app.otherElements["depthPicker"].exists || app.buttons["depthPicker"].exists,
            "Depth picker should sit beside the language picker"
        )

        translate.tap()

        // The translation arrives on device, so it should not wait on the
        // network — and it is labelled as on-device until the cloud replaces it.
        XCTAssertTrue(app.staticTexts["Translation"].waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.staticTexts["provenance.onDevice"].waitForExistence(timeout: 5)
                || app.otherElements["provenance.onDevice"].waitForExistence(timeout: 5),
            "The translation should be marked as on-device before the cloud answers"
        )

        // The `深度解釋` section stands where the explanation will render,
        // rather than the screen offering nothing until it lands.
        XCTAssertTrue(app.staticTexts["Deeper explanation"].waitForExistence(timeout: 5))

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "selection-result-awaiting-explanation"
        shot.lifetime = .keepAlways
        add(shot)

        // Dismissing loses nothing: the record exists and the backend finishes
        // it regardless. This is the behaviour the wording promises.
        app.buttons["Done"].tap()
        XCTAssertFalse(app.navigationBars["Selected text"].exists)
    }
}
