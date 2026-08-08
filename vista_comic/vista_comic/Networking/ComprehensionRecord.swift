//
//  ComprehensionRecord.swift
//  vista_comic
//
//  One 歷史紀錄 entry, matching the backend's `ComprehensionRecordResponse`
//  exactly (see `backend/app/models.py`). It replaced 單字本's saved-translation
//  model, which described something different: a pair the reader chose to keep.
//  One of these is written whenever the reader asks for a deeper explanation —
//  never for a plain on-device translation — so this is a history of what was
//  studied rather than a curated vocabulary book.
//
//  Kept in `Networking/` alongside the seam that fetches it, deliberately
//  separate from `Shared/Models.swift`'s `Comic`/`Chapter`, which are catalog
//  types rather than things this app creates.
//

import Foundation

/// The lifecycle of one record, and the only thing that describes it.
///
/// M9 inferred "translation only" from all three explanation fields being
/// `nil`; that cannot tell "still being produced" from "failed", which is
/// exactly the distinction this feature exists to make, so provenance is now
/// an explicit status.
///
/// Decoded leniently via `unknown`: the backend owns this vocabulary, and a
/// value this build has never heard of must not fail the whole list — the
/// reader would lose their history over one unrecognised row.
enum ComprehensionStatus: String, Hashable, Decodable {
    /// Enqueued, not yet picked up.
    case pending
    /// The backend worker is running it now.
    case running
    /// An explanation arrived.
    case ok
    /// The model declined to explain this selection. Retrying would spend
    /// another request to receive the same verdict, so no retry is offered.
    case declined
    /// A network/server/API failure. Retrying may well work.
    case failed
    /// A status this build does not know. Rendered as "being produced" rather
    /// than as an error, since an unknown state is more likely a newer
    /// in-progress step than a failure.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ComprehensionStatus(rawValue: raw) ?? .unknown
    }

    /// Whether the backend is still working on this record, so a screen
    /// showing it should keep polling.
    var isInProgress: Bool {
        self == .pending || self == .running || self == .unknown
    }
}

/// One comprehension record: the source text, the translation the reader saw
/// immediately, and — once the backend finishes — the cloud translation and
/// the three explanation fields.
struct ComprehensionRecord: Identifiable, Hashable, Decodable {
    /// Server-generated, assigned at enqueue.
    let id: Int
    let sourceText: String
    /// The on-device translation, written at enqueue and never modified
    /// afterwards, so the reader always has something even when the cloud
    /// never answers.
    let translatedText: String
    /// Claude's own translation; `nil` until the record reaches `.ok`.
    let cloudTranslation: String?
    let grammarNotes: String?
    let contextNotes: String?
    let toneRegister: String?
    let targetLanguage: String
    /// The catalog's stable IDs for where this text came from (see
    /// `CONTEXT.md`'s Stable ID), matching `Comic.id` / `Chapter.id`.
    let comicID: String
    let chapterID: String
    /// The 1-based Page index within the chapter, matching the reader's and
    /// `Progress.lastPage`'s convention.
    let pageNumber: Int
    /// Display titles joined by the backend from its in-memory catalog, since
    /// the stored IDs are path hashes and unusable as labels. `nil` when the
    /// comic has left the library — which is also the cue that jumping back to
    /// the source page would fail.
    let comicTitle: String?
    let chapterTitle: String?
    let status: ComprehensionStatus
    let isRead: Bool
    let useStrongerModel: Bool
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, sourceText, translatedText, cloudTranslation
        case grammarNotes, contextNotes, toneRegister
        case targetLanguage, pageNumber, comicTitle, chapterTitle
        case status, isRead, useStrongerModel, createdAt
        case comicID = "comicId"
        case chapterID = "chapterId"
    }

    /// The translation to show: the cloud's wording when it has arrived,
    /// otherwise the on-device one.
    ///
    /// Both are kept on the record so this stays a display decision rather
    /// than something the data layer already settled — and so a `pending`,
    /// `failed` or `declined` record needs no special case to show something.
    var displayedTranslation: String {
        cloudTranslation ?? translatedText
    }

    /// Whether an explanation actually arrived, as opposed to the record
    /// merely having finished.
    var hasExplanation: Bool {
        grammarNotes != nil || contextNotes != nil || toneRegister != nil
    }
}
