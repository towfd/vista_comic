//
//  ReaderFlowUITests.swift
//  vista_comicUITests
//
//  Exercises the reader's previous / next chapter controls and first-chapter
//  boundary in the running app.
//

import XCTest

final class ReaderFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testChapterNavigationAndBoundary() throws {
        let app = XCUIApplication()
        app.launch()

        // Library -> chapter list
        let chapterButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'chapter('")
        ).firstMatch
        XCTAssertTrue(chapterButton.waitForExistence(timeout: 10))
        chapterButton.tap()

        // Chapter list -> reader (open Chapter 1)
        let firstChapter = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Chapter 1'")
        ).firstMatch
        XCTAssertTrue(firstChapter.waitForExistence(timeout: 5))
        firstChapter.tap()

        // Reader on Chapter 1: previous is a boundary, next is available
        let previous = app.buttons["上一章"]
        let next = app.buttons["下一章"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        XCTAssertFalse(previous.isEnabled, "Previous should be disabled on the first chapter")
        XCTAssertTrue(next.isEnabled, "Next should be enabled on the first chapter")
        XCTAssertTrue(app.staticTexts["Chapter 1"].exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "reader-chapter-1"
        shot.lifetime = .keepAlways
        add(shot)

        // Next advances to Chapter 2
        next.tap()
        XCTAssertTrue(app.staticTexts["Chapter 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["上一章"].isEnabled, "Previous should be enabled after leaving the first chapter")
    }
}
