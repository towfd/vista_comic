//
//  CardReview.swift
//  vista_comic
//
//  What recording an answer changed, matching the backend's `ReviewOutcome`
//  (see `backend/app/models.py`).
//
//  The app is **told** rather than left to derive it. Both sides could compute
//  the step and the rung from the same rules, and a second implementation is
//  exactly how the two come to disagree about whether the reader passed
//  something — the deck's normalisation already carries that risk once, and
//  once is enough.
//

import Foundation

/// How far through today a card has got.
///
/// Decoded leniently, following `ComprehensionStatus`: a value this build has
/// never heard of becomes `unknown` rather than failing the answer the reader
/// just gave.
enum DailyStep: String, Decodable, Hashable {
    /// Not answered yet today. Distinct from `unfamiliar` — a card never asked
    /// is not a card just failed.
    case unseen
    case unfamiliar
    case familiar
    /// Cleared for the day: two correct answers in a row.
    case passed
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DailyStep(rawValue: raw) ?? .unknown
    }
}

/// What one answer did.
struct ReviewOutcome: Decodable, Hashable {
    let step: DailyStep
    let ladderStage: Int
    /// ISO-8601 date. A scheduling day is not an instant, so it stays a string
    /// for the same reason `LearningCard.dueOn` does.
    let dueOn: String
    /// Whether **this** answer was the one that moved the rung.
    ///
    /// False for every answer after the day's first resolution, which is how
    /// "at most once per day" reaches the app as a fact rather than as
    /// something to infer from a rung that did not change.
    let ladderMoved: Bool
}

/// Which question produced an answer.
///
/// Sent rather than inferred: the same card is asked in more than one way, and
/// the difference matters to anything that later weighs difficulty.
enum ReviewQuestionType: String, Encodable {
    case clozeChoice = "cloze_choice"
    case clozeTyped = "cloze_typed"
    case sentenceRearranged = "sentence_rearranged"
    case sentenceTyped = "sentence_typed"
}
