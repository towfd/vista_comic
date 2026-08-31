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

/// What one answer did.
///
/// The card's whole scheduling block, so the caller can write it into its deck
/// snapshot rather than refetch — which is what makes a session keep working
/// with no network.
struct ReviewOutcome: Decodable, Hashable {
    let state: CardState
    let learningStep: Int?
    let ladderStage: Int
    let previousStage: Int?
    /// ISO-8601 date, or `nil` while the card is still new. A scheduling day is
    /// not an instant, so it stays a string.
    let introducedOn: String?
    let dueAt: Date
    /// Whether this answer changed **which interval the card is on**, where a
    /// card still in the learning steps is on none.
    ///
    /// So graduating counts (no interval, then one day) and so does a lapse,
    /// while the answers between the learning steps do not. Comparing the slot
    /// number instead would report nothing at the moment a card graduates,
    /// because graduating lands on slot 0 — which its column already said.
    let intervalChanged: Bool
}

/// Which mode asked the question.
///
/// `Codable` rather than `Encodable`, unlike most of what is sent from here:
/// stage 6's offline queue writes answers to disk and reads them back, and an
/// answer that could not say which mode asked it would flush as a `review`.
///
/// Sent with every answer because the log cannot otherwise tell an answer that
/// was meant to count from one that deliberately did not — and 永無止盡的訓練
/// records everything while scheduling nothing.
enum ReviewContext: String, Codable {
    /// The scheduled session. Moves the card.
    case review
    /// 永無止盡的訓練. Recorded, and changes no schedule in either direction.
    case training
}

/// Which question produced an answer.
///
/// Sent rather than inferred: the same card is asked in more than one way, and
/// the difference matters to anything that later weighs difficulty.
enum ReviewQuestionType: String, Codable {
    case clozeChoice = "cloze_choice"
    case clozeTyped = "cloze_typed"
    case sentenceRearranged = "sentence_rearranged"
    case sentenceTyped = "sentence_typed"
}
