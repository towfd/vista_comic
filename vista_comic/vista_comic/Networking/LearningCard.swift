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

/// What the reader said a framed line is, by which save button they pressed.
///
/// **Never inferred.** Which of the two a line is takes a tokeniser and some
/// syntax to guess at — badly, for Japanese especially — and the reader knows
/// instantly. One tap replaces all of it, and the answer decides which
/// questions stage 3 asks and whether stage 4 writes a practice sentence *for*
/// the card or treats the card as one.
///
/// `Codable`, unlike the display models around it, because it is also written
/// to disk: the offline queue persists what the reader chose so a relaunch does
/// not lose the answer along with the word.
enum CardKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// A word or set phrase. Stage 4 generates a sentence containing it, and
    /// it is what the blank replaces.
    case word
    /// A whole line. Already real language, so nothing is generated for it —
    /// it *is* the practice sentence, and the blank comes from a deck word
    /// inside it.
    case sentence
}

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
    /// Which of the two the reader said this is, or `nil` for a card collected
    /// before they could say.
    ///
    /// Decoded leniently: a value this build has never heard of becomes `nil`
    /// rather than failing the whole list, following `ComprehensionStatus`'s
    /// precedent. The backend owns this vocabulary, and losing the entire deck
    /// over one unrecognised row would be a poor trade.
    let kind: CardKind?
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
        case pageNumber, kind, ladderStage, dueOn, lookupCount, lastLookedUpAt, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        sourceText = try container.decode(String.self, forKey: .sourceText)
        translation = try container.decode(String.self, forKey: .translation)
        targetLanguage = try container.decode(String.self, forKey: .targetLanguage)
        comicID = try container.decode(String.self, forKey: .comicID)
        chapterID = try container.decode(String.self, forKey: .chapterID)
        pageNumber = try container.decode(Int.self, forKey: .pageNumber)
        // The lenient step: absent, null, or unrecognised all mean "unanswered".
        kind = (try? container.decodeIfPresent(String.self, forKey: .kind))
            .flatMap { $0 }
            .flatMap(CardKind.init(rawValue:))
        ladderStage = try container.decode(Int.self, forKey: .ladderStage)
        dueOn = try container.decode(String.self, forKey: .dueOn)
        lookupCount = try container.decode(Int.self, forKey: .lookupCount)
        lastLookedUpAt = try container.decodeIfPresent(Date.self, forKey: .lastLookedUpAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}
