//
//  StudyRepositoryDefaults.swift
//  vista_comicTests
//
//  Neutral behaviour for the parts of `StudyRepository` a given test does not
//  care about.
//
//  Four doubles conform to that protocol, each interested in one or two of its
//  methods, and every time the seam grew all four had to be edited — the fourth
//  time being the one that produced this file. A test that stubs a method it
//  never exercises is stating something it does not mean, and four copies of
//  that statement drift.
//
//  A double that *does* care overrides the method as before. Nothing here
//  records anything, so a test relying on one of these defaults to observe
//  something will see nothing and fail, which is the right way round.
//

import Foundation

@testable import vista_comic

extension StudyRepository {
    @discardableResult
    func recordReview(
        cardID: Int,
        questionType: ReviewQuestionType,
        isCorrect: Bool,
        clientToken: String,
        localDate: Date,
        elapsedMs: Int?
    ) async throws -> ReviewOutcome {
        ReviewOutcome(step: .familiar, ladderStage: 0, dueOn: "2026-08-21", ladderMoved: false)
    }
}
