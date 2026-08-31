//
//  StudySettings.swift
//  vista_comic
//
//  The reader's scheduling settings, matching the backend's `StudySettings`
//  (see `backend/app/models.py`).
//
//  They live on the server rather than on the device because the server
//  recomputes schedules when an offline session flushes, and two copies that
//  disagreed would produce two different due times for the same answer.
//

import Foundation

/// How long the learning steps are, and how many new cards a day.
///
/// `Codable` in both directions, unlike most models here: this one is sent as
/// well as received, because the settings screen writes it back.
struct StudySettings: Codable, Hashable, Sendable {
    /// Minutes between learning steps, in order.
    ///
    /// A list rather than three fields because "how many steps" and "how long
    /// each step is" are the same question, and writing three down assumes an
    /// answer to the first.
    let learningSteps: [Int]
    /// How many cards may be met for the first time in one day.
    let newCardsPerDay: Int

    /// What the backend seeds, and what the app assumes when it has never been
    /// able to ask. Kept in step with `scheduler.DEFAULT_LEARNING_STEPS`.
    static let fallback = StudySettings(learningSteps: [5, 7, 10], newCardsPerDay: 15)
}
