//
//  StudySettingsTests.swift
//  vista_comicTests
//
//  Reading the reader's learning steps back out of a text field
//  (vocabulary stage 6, ticket 06).
//
//  The field is text because a half-typed list is a state the screen has to be
//  able to be in — parsing on every keystroke and snapping the field back would
//  fight the reader mid-edit. Which makes the parser the place where every bad
//  value has to be caught.
//

import Foundation
import Testing

@testable import vista_comic

@Suite("Reading learning steps")
struct LearningStepParsingTests {

    @Test("A plain list reads back as minutes")
    func aPlainListParses() {
        #expect(parseLearningSteps("5, 7, 10") == [5, 7, 10])
    }

    @Test("Separators are lenient, because the reader is typing a list not a syntax",
          arguments: ["5,7,10", "5 7 10", "5,  7 ,10", " 5, 7, 10 "])
    func separatorsAreLenient(_ text: String) {
        #expect(parseLearningSteps(text) == [5, 7, 10])
    }

    @Test("One step is a real choice")
    func oneStepIsAllowed() {
        // It means a card graduates on its second correct answer. Shorter than
        // the default, and nothing about it is invalid.
        #expect(parseLearningSteps("3") == [3])
    }

    @Test("Nothing at all is refused rather than read as no steps")
    func anEmptyListIsRefused() {
        // An empty list has no first step for a wrong answer to send a card
        // back to, so there would be nowhere for a lapse to go.
        #expect(parseLearningSteps("") == nil)
        #expect(parseLearningSteps("   ") == nil)
        #expect(parseLearningSteps(" , , ") == nil)
    }

    @Test("A zero or negative step is refused", arguments: ["0", "5, 0, 10", "5, -1"])
    func nonPositiveStepsAreRefused(_ text: String) {
        // It would schedule a card to be due before it was answered.
        #expect(parseLearningSteps(text) == nil)
    }

    @Test("Anything that is not a number is refused", arguments: ["5, x", "five", "5.5"])
    func nonNumbersAreRefused(_ text: String) {
        // Including `5.5`: the backend stores whole minutes, and rounding the
        // reader's number without saying so is the kind of quiet disagreement
        // this whole stage exists to remove.
        #expect(parseLearningSteps(text) == nil)
    }

    @Test("Nothing partial is ever returned")
    func aBadEntryDiscardsTheWholeList() {
        // Returning `[5, 7]` from `5, 7, x` would silently drop a step the
        // reader can see on screen.
        #expect(parseLearningSteps("5, 7, x") == nil)
    }

    @Test("Steps round-trip through the field")
    func stepsRoundTrip() {
        let steps = [1, 20, 45]

        #expect(parseLearningSteps(formatLearningSteps(steps)) == steps)
    }

    @Test("The app's fallback matches what the backend seeds")
    func theFallbackMatchesTheBackend() {
        // Two constants, one fact — the app assumes these before the first
        // fetch answers, and a drift would schedule a session differently from
        // the server that later recomputes it.
        #expect(StudySettings.fallback.learningSteps == [5, 7, 10])
        #expect(StudySettings.fallback.newCardsPerDay == 15)
    }
}
