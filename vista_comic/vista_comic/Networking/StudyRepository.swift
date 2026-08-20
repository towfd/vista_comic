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
///
/// `knownCards()` is the odd one out and has no route: it answers from the last
/// good response rather than the network, which is what lets the
/// already-collected marker work on a train.
protocol StudyRepository {
    /// Collects one line.
    ///
    /// `kind` is what the reader said this is, by which button they pressed.
    /// **An existing card keeps the kind it already had** — re-collecting under
    /// the other button is not a correction, and the system does not silently
    /// rewrite something the reader already approved.
    ///
    /// **Idempotent**: collecting a line already in the deck returns the
    /// existing card rather than failing, because the backend answers 200 for a
    /// duplicate. The offline queue depends on that — it replays blindly — and
    /// callers benefit too, since a double tap is not an error worth showing.
    @discardableResult
    func collect(
        sourceText: String,
        translation: String,
        targetLanguage: String,
        comicID: String,
        chapterID: String,
        pageNumber: Int,
        kind: CardKind?
    ) async throws -> CollectOutcome

    /// Every card the reader still has, newest first.
    func cards() async throws -> [LearningCard]

    /// Corrects a card, returning it as it now stands.
    ///
    /// Both fields are always sent, because the screen behind this is a form
    /// showing both — which sidesteps the "did they mean *don't change it* or
    /// *set it to nothing*" question entirely. A `nil` kind therefore **clears**
    /// the classification rather than leaving it alone, which is a thing to
    /// want: it is how a card mis-tapped into the wrong kind gets put back to
    /// unanswered.
    ///
    /// The source text, target language and source reference are not here, and
    /// their absence is the API. Two of them are the card's identity and the
    /// third is a fact about the past.
    @discardableResult
    func update(
        id: Int,
        translation: String,
        kind: CardKind?
    ) async throws -> LearningCard

    /// Removes a card.
    ///
    /// A real delete. Whatever it knew — how often it had been forgotten, how
    /// far up the ladder it had climbed — goes with it, which is why the screen
    /// confirms first.
    func delete(id: Int) async throws

    /// Notes that the reader looked an already-collected word up again.
    func recordLookup(id: Int) async throws

    /// Lines collected but not yet accepted by the server.
    ///
    /// Empty for any repository that has no queue, which is why it has a
    /// default rather than being a second protocol: only the offline decorator
    /// has an answer, and no caller should have to ask which one it holds.
    func queuedLines() -> [PendingCard]

    /// What is known locally, from the last good `cards()` response.
    ///
    /// Neither `async` nor `throws`, and that is the point: this is a local
    /// read on the path of an action the reader is waiting on, and it must be
    /// able to answer instantly with no connection. Nothing here is worth
    /// interrupting them for, so an absent or unreadable snapshot is simply an
    /// empty deck — the marker is a courtesy, never a correctness requirement.
    func knownCards() -> [LearningCard]
}

extension StudyRepository {
    func queuedLines() -> [PendingCard] { [] }
}

/// What became of a collect.
///
/// A queued line is deliberately **not** a `LearningCard`: the server has not
/// given it an id, so nothing can be reported against it and nothing can
/// schedule it. Inventing one would put a number in the data model that no
/// backend ever issued, and every later stage would have to know which ids were
/// real.
enum CollectOutcome: Equatable {
    /// The server has it. Also the answer when the line was already collected —
    /// `POST /cards` returns the existing card rather than an error.
    case collected(LearningCard)
    /// Kept on the device until the backend can be reached.
    case queued
}

// MARK: - Environment injection

private struct StudyRepositoryKey: EnvironmentKey {
    /// Defaults to the concrete production conformer, following
    /// `ComprehensionRepositoryKey`'s precedent for a network-backed seam:
    /// `#Preview`s that need one inject a stub, and those that never touch it
    /// never reach the network either.
    static let defaultValue: any StudyRepository = OfflineFallbackStudyRepository(
        wrapping: APIStudyRepository(),
        pending: (try? FilePendingCardStore()) ?? InMemoryPendingCardStore(),
        pendingLookups: (try? FilePendingLookupStore()) ?? InMemoryPendingLookupStore()
    )
}

extension EnvironmentValues {
    /// The repository the current view tree collects and reads cards through.
    var studyRepository: any StudyRepository {
        get { self[StudyRepositoryKey.self] }
        set { self[StudyRepositoryKey.self] = newValue }
    }
}
