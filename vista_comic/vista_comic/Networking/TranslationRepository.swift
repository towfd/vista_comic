//
//  TranslationRepository.swift
//  vista_comic
//
//  The "saved learning material" seam for the `ocr-translation` feature,
//  mirroring `ComicRepository`'s pattern: screens depend on this protocol,
//  not a concrete network client, so the live backend (`APITranslationRepository`)
//  can be swapped for a stub in tests and `#Preview`s. Kept separate from
//  `ComicRepository` on purpose (per the `ocr-translation` spec's
//  Implementation Decisions) — saved translations are their own domain, not
//  bolted onto the comic/reading-progress domain `ComicRepository` describes.
//
//  API contract of record: Ticket 02's `POST /translations` / `GET /translations`
//  (see `backend/app/main.py`, `backend/app/models.py`).
//
//  Environment injection added in the `ocr-translation` ticket that wires
//  the first real consumer (the OCR result screen's "Save" action),
//  mirroring `OCRRecognizer`'s/`Translator`'s own `EnvironmentKey`/
//  `EnvironmentValues` extension — see the bottom of this file.
//

import Foundation
import SwiftUI

/// Saves and lists translated text pairs against the backend's "單字本" store.
///
/// Mirrors the backend endpoints:
/// - `save(...)` → `POST /translations`
/// - `list()`    → `GET /translations`
/// - `delete(id:)` → `DELETE /translations/{id}`
protocol TranslationRepository {
    /// Persists one original/translated text pair with its source reference.
    /// Returns the saved entry, including the server-generated `id` and
    /// `savedAt` timestamp, so a caller can display it immediately without a
    /// second round trip.
    @discardableResult
    func save(
        originalText: String,
        translatedText: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int
    ) async throws -> SavedTranslation

    /// Every saved translation, most recently saved first.
    func list() async throws -> [SavedTranslation]

    /// Deletes one saved translation by its server-generated `id`.
    func delete(id: Int) async throws
}

// MARK: - Environment injection

private struct TranslationRepositoryKey: EnvironmentKey {
    /// `APITranslationRepository`'s defaults (`APIConfig.baseURL`, etc.) mirror
    /// `APIComicRepository`'s own network-backed default, per `OCRRecognizerKey`/
    /// `TranslatorKey`'s pattern of defaulting to the concrete production
    /// conformer directly.
    static let defaultValue: any TranslationRepository = APITranslationRepository()
}

extension EnvironmentValues {
    /// The repository the current view tree saves/lists translations through.
    var translationRepository: any TranslationRepository {
        get { self[TranslationRepositoryKey.self] }
        set { self[TranslationRepositoryKey.self] = newValue }
    }
}
