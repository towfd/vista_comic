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

/// Where a card is in the scheduling model.
///
/// The four states are Anki's, and they are stored on the card rather than
/// derived from its answers — a learning card's position is *which step, due at
/// what minute*, which no answer has ever carried.
enum CardState: String, Decodable, Hashable, Sendable, CaseIterable {
    /// Never answered. Waits on the day's new-card quota rather than on a due
    /// date.
    case new
    /// Walking the learning steps for the first time.
    case learning
    /// Graduated, on the interval table.
    case review
    /// Graduated once, then missed. Walking the same steps back to its slot.
    case relearning
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
    /// Joined by the backend from its live catalog at read time rather than
    /// stored, exactly as `ComprehensionRecord` does it. The card holds
    /// path-hash ids, which are correct as keys and useless as labels.
    ///
    /// A `nil` comic title is not a missing fetch — it is the backend saying
    /// that comic has left the library, and therefore that jumping back to the
    /// page would fail. See `Shared/SourceReference.swift`.
    let comicTitle: String?
    let chapterTitle: String?
    /// Which of the two the reader said this is, or `nil` for a card collected
    /// before they could say.
    ///
    /// Decoded leniently: a value this build has never heard of becomes `nil`
    /// rather than failing the whole list, following `ComprehensionStatus`'s
    /// precedent. The backend owns this vocabulary, and losing the entire deck
    /// over one unrecognised row would be a poor trade.
    let kind: CardKind?
    /// Where the card is in the scheduling model.
    ///
    /// Decoded leniently, like `kind`: an unrecognised value becomes `.new`
    /// rather than failing the deck. A card wrongly treated as new is asked
    /// again, which is recoverable; an empty deck is not.
    var state: CardState
    /// Which learning step the card is on, or `nil` outside the learning
    /// states.
    var learningStep: Int?
    /// Which slot of the interval table the card holds — 0 to 6, meaning
    /// 1/3/7/21/60/150/365 days. A card still in the learning steps has not
    /// earned this yet; the number is where it *will* land.
    var ladderStage: Int
    /// The slot to return to after relearning, or `nil` when the card has never
    /// lapsed. What makes a lapse cost one slot rather than everything.
    var previousStage: Int?
    /// The reader's day on which this card stopped being new, or `nil` while it
    /// still is. The session counts these against the day's new-card quota,
    /// which it has to be able to do with no network.
    ///
    /// A `String` rather than a `Date` because a scheduling day is not an
    /// instant — turning it into one would invent a timezone the backend never
    /// chose.
    var introducedOn: String?
    /// When this card next comes up.
    ///
    /// **A timestamp, not a day.** It was `dueOn`, an ISO date, until stage 6;
    /// learning steps are minutes apart and a card due at 20:07 cannot be said
    /// as a day.
    var dueAt: Date
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
        case pageNumber, comicTitle, chapterTitle, kind
        case state, learningStep, ladderStage, previousStage, introducedOn
        case dueAt, dueOn, lookupCount, lastLookedUpAt, createdAt
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
        comicTitle = try container.decodeIfPresent(String.self, forKey: .comicTitle)
        chapterTitle = try container.decodeIfPresent(String.self, forKey: .chapterTitle)
        // The lenient step: absent, null, or unrecognised all mean "unanswered".
        kind = (try? container.decodeIfPresent(String.self, forKey: .kind))
            .flatMap { $0 }
            .flatMap(CardKind.init(rawValue:))
        // Lenient for the same reason `kind` is, and for one more: a deck
        // snapshot cached before stage 6 has none of these fields, and the
        // reader who opens the app offline that morning would otherwise find an
        // empty deck. An old snapshot decodes as a deck of new cards, which is
        // exactly what the migration made them anyway.
        state = (try? container.decodeIfPresent(String.self, forKey: .state))
            .flatMap { $0 }
            .flatMap(CardState.init(rawValue:)) ?? .new
        learningStep = try container.decodeIfPresent(Int.self, forKey: .learningStep)
        ladderStage = try container.decode(Int.self, forKey: .ladderStage)
        previousStage = try container.decodeIfPresent(Int.self, forKey: .previousStage)
        introducedOn = try container.decodeIfPresent(String.self, forKey: .introducedOn)
        if let due = try container.decodeIfPresent(Date.self, forKey: .dueAt) {
            dueAt = due
        } else {
            // A pre-stage-6 snapshot, which carried a day. Read as the start of
            // that day in the reader's own timezone — the same timezone the day
            // was written in — so a card due "today" is due now rather than at
            // some hour Greenwich chose.
            let day = try container.decodeIfPresent(String.self, forKey: .dueOn)
            dueAt = day.flatMap(LearningCard.startOfDay(_:)) ?? Date.distantPast
        }
        lookupCount = try container.decode(Int.self, forKey: .lookupCount)
        lastLookedUpAt = try container.decodeIfPresent(Date.self, forKey: .lastLookedUpAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    /// Takes the schedule the backend just returned.
    ///
    /// The six scheduling fields are `var` and nothing else is, which is the
    /// whole rule: identity and provenance are facts about the past and are
    /// read-only, while the schedule is what an answer changes. Applying it
    /// locally rather than refetching the deck is what lets a session keep
    /// going with no network.
    mutating func apply(_ outcome: ReviewOutcome) {
        state = outcome.state
        learningStep = outcome.learningStep
        ladderStage = outcome.ladderStage
        previousStage = outcome.previousStage
        introducedOn = outcome.introducedOn
        dueAt = outcome.dueAt
    }

    /// Midnight of an ISO-8601 day, in the reader's timezone.
    private static func startOfDay(_ iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)
    }
}
