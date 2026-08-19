//
//  LearningCard.swift
//  vista_comic
//
//  One entry in 單字庫, matching the backend's `LearningCardResponse` exactly
//  (see `backend/app/models.py`).
//
//  Not a return of 單字本's deleted `SavedTranslation`, despite the shared
//  shape. That model described whatever the app decided to keep; one of these
//  exists only because the reader pressed add, having read the source text and
//  the translation and judged them right. **That press is the quality gate**:
//  the source text is trustworthy because they corrected the OCR before
//  anything else happened, the translation is not, and a deck built
//  automatically would use spaced repetition to reinforce the model's mistakes.
//  See `.scratch/vocabulary-review/prd.md`.
//
//  Kept in `Networking/` beside the seam that fetches it, the same as
//  `ComprehensionRecord`.
//

import Foundation

/// One collected line: what the reader framed, what it meant, and where it was
/// met.
///
/// `Decodable` only, like every other display model here. Nothing in the app
/// re-encodes one — ticket 03's deck snapshot stores the raw response bytes
/// rather than re-serialising these, precisely so this can stay one-way.
struct LearningCard: Decodable, Identifiable, Hashable {
    let id: Int
    /// Exactly what the reader corrected, unnormalised. The server keeps a
    /// normalised key alongside it for identity; that key is deliberately not
    /// in this contract, because the app derives its own from `sourceText` for
    /// the local match (ticket 03) and two sources of one truth would be one
    /// too many.
    let sourceText: String
    /// Whatever wording was on screen when add was tapped — on-device if the
    /// reader added straight after translating, the cloud's if they waited for
    /// an explanation first. Nothing upgrades it afterwards.
    let translation: String
    let targetLanguage: String
    /// Where this line was **first** met. The comic is not part of a card's
    /// identity, so meeting the same word elsewhere does not move these.
    let comicID: String
    let chapterID: String
    let pageNumber: Int
    /// Where the card sits on stage 3's interval ladder. Carried from the first
    /// release even though nothing reads it yet: the deck snapshot caches this
    /// response wholesale, and a field added later would be missing from every
    /// snapshot predating it.
    let ladderStage: Int
    /// The day this card is next due, as an ISO-8601 *date* (`2026-08-19`).
    ///
    /// Kept as a `String` rather than a `Date` because the shared decoder's
    /// strategy parses date-*times*, and a scheduling day is not an instant —
    /// turning it into one would invent a timezone the backend never chose.
    /// Stage 3 is where this stops being opaque.
    let dueOn: String
    /// How many times the reader looked this word up **again** after collecting
    /// it. Only the positive is ever counted: not looking a word up again is no
    /// evidence of knowing it, since the reader may simply not have reached
    /// that page.
    let lookupCount: Int
    let lastLookedUpAt: Date?
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, sourceText, translation, targetLanguage
        case comicID = "comicId"
        case chapterID = "chapterId"
        case pageNumber, ladderStage, dueOn, lookupCount, lastLookedUpAt, createdAt
    }
}
