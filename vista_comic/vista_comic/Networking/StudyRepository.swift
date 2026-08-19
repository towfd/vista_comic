//
//  StudyRepository.swift
//  vista_comic
//
//  The single seam for the whole `/cards` resource, mirroring
//  `ComprehensionRepository`'s pattern: screens depend on this protocol rather
//  than a concrete network client, so the live backend
//  (`APIStudyRepository`) can be swapped for a stub in tests and `#Preview`s.
//
//  Named for what the resource is *for* rather than what it holds. 單字庫 is the
//  first thing it serves; the reviewing stages add sessions and results to the
//  same seam rather than growing a second one beside it.
//

import Foundation
import SwiftUI

/// Collects and reads the reader's vocabulary against the backend's `/cards`
/// API.
///
/// Mirrors the backend routes (see `backend/app/main.py`):
/// - `collect(...)`      → `POST /cards`
/// - `cards()`           → `GET /cards`
/// - `recordLookup(id:)` → `POST /cards/{id}/lookups`
protocol StudyRepository {
    /// Collects one line, returning the card.
    ///
    /// **Idempotent**: collecting a line already in the deck returns the
    /// existing card rather than failing, because the backend answers 200 for a
    /// duplicate. Ticket 04's offline queue depends on that, and callers here
    /// benefit from it too — a double tap is not an error worth showing.
    @discardableResult
    func collect(
        sourceText: String,
        translation: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int
    ) async throws -> LearningCard

    /// Every card the reader still has, newest first.
    func cards() async throws -> [LearningCard]

    /// Notes that the reader looked an already-collected word up again.
    func recordLookup(id: Int) async throws
}

// MARK: - Environment injection

private struct StudyRepositoryKey: EnvironmentKey {
    /// Defaults to the concrete production conformer, following
    /// `ComprehensionRepositoryKey`'s precedent for a network-backed seam:
    /// `#Preview`s that need one inject a stub, and those that never touch it
    /// never reach the network either.
    static let defaultValue: any StudyRepository = APIStudyRepository()
}

extension EnvironmentValues {
    /// The repository the current view tree collects and reads cards through.
    var studyRepository: any StudyRepository {
        get { self[StudyRepositoryKey.self] }
        set { self[StudyRepositoryKey.self] = newValue }
    }
}
