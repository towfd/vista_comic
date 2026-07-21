//
//  LibraryFlowUITests.swift
//  vista_comicUITests
//
//  Interactive smoke test for the library -> chapter list -> reader flow.
//  Drives the real app in the simulator and asserts each destination renders,
//  which also exercises M2 read-state presentation and M3 reader controls.
//

import XCTest

final class LibraryFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testLibraryToChapterToReader() throws {
        let app = XCUIApplication()
        // Force English so assertions on visible text are stable regardless of
        // the host locale (the UI is localization-ready with English keys).
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        // Library
        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Frieren"].exists)
        XCTAssertTrue(app.staticTexts["not started yet"].exists, "Unstarted comic should read 'not started yet'")
        attach(app, "01-library")

        // Open the first comic's chapter list
        let chapterButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'chapter('")
        ).firstMatch
        XCTAssertTrue(chapterButton.waitForExistence(timeout: 5))
        chapterButton.tap()

        // Chapter list: read-state presentation should be visible
        XCTAssertTrue(app.staticTexts["Chapter 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["read"].exists, "Chapter 1 should show read state")
        XCTAssertTrue(app.staticTexts["reading"].exists, "Chapter 2 should show reading state")
        attach(app, "02-chapters")

        // Open a chapter -> reader
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Chapter 1'")
        ).firstMatch.tap()

        // Reader: immersive controls (custom back + chapter list) prove we arrived
        XCTAssertTrue(app.buttons["Chapter list"].waitForExistence(timeout: 5), "Reader chapter-list control should exist")
        XCTAssertTrue(app.buttons["Back"].exists, "Reader back control should exist")
        attach(app, "03-reader")

        // Custom back returns to the chapter list
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["Chapter 1"].waitForExistence(timeout: 5))
    }
}
