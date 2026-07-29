//
//  SavedTranslation.swift
//  vista_comic
//
//  The response model for `TranslationRepository`'s save/list methods,
//  matching the backend's `SavedTranslationResponse` shape exactly (see
//  `backend/app/models.py` and `docs/api-contract.md`'s `ocr-translation`
//  addendum). Kept in `Networking/`, deliberately separate from
//  `Shared/Models.swift`'s `Comic`/`Chapter` — saved translations are their
//  own domain ("saved learning material"), not bolted onto the comic/reading-
//  progress domain those describe (per the `ocr-translation` spec's
//  Implementation Decisions).
//

import Foundation

/// One saved original/translation pair with its source reference, as
/// returned by `POST /translations` and each item of `GET /translations`.
struct SavedTranslation: Identifiable, Hashable, Decodable {
    /// Server-generated, assigned on save.
    let id: Int
    let originalText: String
    let translatedText: String
    /// The target language the translation was made into (e.g. `"zh-Hant"`),
    /// as a plain string — the backend stores and echoes it opaquely, with no
    /// `Locale.Language` decoding on this side.
    let targetLanguage: String
    /// The catalog's stable IDs for where this text was recognized (see
    /// `CONTEXT.md`'s Stable ID), matching `Comic.id` / `Chapter.id`.
    let comicID: String
    let chapterID: String
    /// The 1-based Page index within the chapter, matching the reader's and
    /// `Progress.lastPage`'s convention.
    let pageNumber: Int
    /// When the pair was saved, ISO-8601 UTC.
    let savedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, originalText, translatedText, targetLanguage, pageNumber, savedAt
        case comicID = "comicId"
        case chapterID = "chapterId"
    }
}
