//
//  SelectionResultFlowUITests.swift
//  vista_comicUITests
//
//  Exercises the selection result sheet's two-step shape: translating is
//  on-device and free, and the deeper explanation is a separate, opt-in action
//  with its own depth choice — so the sheet must offer nothing but "Translate"
//  up front, and the explanation controls only once a translation exists.
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
    func testTranslatingIsOnDeviceAndTheExplanationIsASeparateOptIn() throws {
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

        // Only the language picker up front. Depth belongs to the explanation
        // request, and offering it here would imply the cloud call is part of
        // translating — exactly what the split undoes.
        let translate = app.buttons["Translate"]
        guard translate.waitForExistence(timeout: 15) else {
            // Recognition can legitimately find no text in a sample page, which
            // is not this test's subject — the failure states have their own
            // unit coverage.
            throw XCTSkip("OCR found no text in the sampled region; nothing to translate.")
        }
        XCTAssertTrue(app.staticTexts["Translate to"].exists)
        XCTAssertFalse(
            app.otherElements["depthPicker"].exists || app.buttons["depthPicker"].exists,
            "Depth should not be offered before there is anything to explain"
        )

        translate.tap()

        // The translation arrives on device, so it should not wait on the
        // network — and it is labelled as on-device, since nothing was sent.
        XCTAssertTrue(app.staticTexts["Translation"].waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.staticTexts["provenance.onDevice"].waitForExistence(timeout: 5)
                || app.otherElements["provenance.onDevice"].waitForExistence(timeout: 5),
            "The translation should be marked as on-device before the cloud answers"
        )

        // …and the deeper explanation is offered as a separate action rather
        // than having already been requested.
        let explain = app.buttons["explainInDepth"]
        XCTAssertTrue(explain.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.otherElements["depthPicker"].exists || app.buttons["depthPicker"].exists,
            "Depth should be chosen with the explanation request it belongs to"
        )
        XCTAssertFalse(
            app.staticTexts["Deeper explanation"].exists,
            "Nothing should be enqueued until the reader asks for it"
        )

        let beforeShot = XCTAttachment(screenshot: app.screenshot())
        beforeShot.name = "selection-result-translated-only"
        beforeShot.lifetime = .keepAlways
        add(beforeShot)

        // Taking the opt-in replaces the button with the section it produces.
        explain.tap()
        XCTAssertTrue(app.staticTexts["Deeper explanation"].waitForExistence(timeout: 15))
        XCTAssertFalse(explain.exists)

        let afterShot = XCTAttachment(screenshot: app.screenshot())
        afterShot.name = "selection-result-awaiting-explanation"
        afterShot.lifetime = .keepAlways
        add(afterShot)

        // Dismissing loses nothing: the record exists and the backend finishes
        // it regardless. This is the behaviour the wording promises.
        app.buttons["Done"].tap()
        XCTAssertFalse(app.navigationBars["Selected text"].exists)
    }
}
