//
//  ComprehensionRepository.swift
//  vista_comic
//
//  The single seam for the whole `/comprehensions` resource, mirroring
//  `ComicRepository`'s pattern: screens depend on this protocol, not a
//  concrete network client, so the live backend (`APIComprehensionRepository`)
//  can be swapped for a stub in tests and `#Preview`s.
//
//  It replaced **two** seams, both since deleted: the comprehender (the app no
//  longer calls Claude at all; the backend owns that) and the translation
//  repository (manual saving is gone). The app therefore ends with one fewer
//  network protocol than it had before this feature.
//
//  One protocol rather than a reader-facing and a history-facing pair:
//  marking read is needed by both, so splitting would mean two protocols
//  pointing at one implementation, a shape this codebase has nowhere.
//

import Foundation
import SwiftUI

/// Creates and manages comprehension records against the backend's
/// `/comprehensions` API.
///
/// Mirrors the backend routes (see `backend/app/main.py`):
/// - `enqueue(...)`        → `POST /comprehensions`
/// - `list()`              → `GET /comprehensions`
/// - `record(id:)`         → `GET /comprehensions/{id}`
/// - `setRead(id:isRead:)` → `PATCH /comprehensions/{id}`
/// - `retry(id:)`          → `POST /comprehensions/{id}/retry`
/// - `delete(id:)`         → `DELETE /comprehensions/{id}`
protocol ComprehensionRepository {
    /// Creates one record and returns it immediately, still `pending`.
    ///
    /// Does **not** wait for the explanation: the reader already has
    /// `translatedText` on screen by the time this is called, and the backend
    /// produces the rest on its own. That is the whole point of the resource.
    ///
    /// Throws `ComprehensionEnqueueError.dailyCapReached` when the backend
    /// refuses because today's request budget is spent — distinguished from
    /// every other failure because retrying cannot help until tomorrow.
    @discardableResult
    func enqueue(
        sourceText: String,
        translatedText: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int,
        useStrongerModel: Bool
    ) async throws -> ComprehensionRecord

    /// Every record, newest first.
    func list() async throws -> [ComprehensionRecord]

    /// One record by id — what a screen polls while its record is unfinished.
    func record(id: Int) async throws -> ComprehensionRecord

    /// Sets one record's read flag, returning the updated record.
    @discardableResult
    func setRead(id: Int, isRead: Bool) async throws -> ComprehensionRecord

    /// Re-enqueues a `failed` record, returning it as `pending` again.
    @discardableResult
    func retry(id: Int) async throws -> ComprehensionRecord

    /// Deletes one record.
    func delete(id: Int) async throws
}

/// Enqueue failures the caller must tell apart, because they lead to
/// different things being offered to the reader.
///
/// The split is the same rule the result screen applies to a failed versus a
/// declined explanation: distinguish by whether retrying can possibly help,
/// and offer a retry only where it can.
enum ComprehensionEnqueueError: Error, Equatable {
    /// The backend returned 429: today's request budget is spent and **no
    /// record was created**. Permanent until tomorrow, so no retry is offered.
    ///
    /// The only case, deliberately: every *other* enqueue failure is transient
    /// and needs no distinguishing, so they surface as the repository's
    /// ordinary `APIError` and the flow maps them all to one outcome. A second
    /// case carrying a description would exist only to be ignored.
    case dailyCapReached
}

// MARK: - Environment injection

private struct ComprehensionRepositoryKey: EnvironmentKey {
    /// Defaults straight to the concrete production conformer, following
    /// the precedent for a network-backed seam rather than `ComicRepository`'s
    /// offline preview mock: `#Preview`s that need one inject a stub, and those
    /// that don't override this never reach the network anyway.
    static let defaultValue: any ComprehensionRepository = APIComprehensionRepository()
}

extension EnvironmentValues {
    /// The repository the current view tree creates and reads records through.
    var comprehensionRepository: any ComprehensionRepository {
        get { self[ComprehensionRepositoryKey.self] }
        set { self[ComprehensionRepositoryKey.self] = newValue }
    }
}
