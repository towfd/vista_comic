//
//  SourceReference.swift
//  vista_comic
//
//  Where a kept line came from, and whether the reader can still go back to it.
//
//  Extracted from `Features/History/ComprehensionSummary.swift` (vocabulary
//  stage 2, ticket 02) ahead of that folder being deleted. **Moved rather than
//  rewritten**, deliberately: the rules below already handle a comic that has
//  left the library and already avoid disturbing reading progress, and
//  reimplementing them inside the new screen would trade working navigation for
//  a fresh set of bugs in something the reader had working yesterday.
//
//  It became a type of its own rather than a straight file move because two
//  different things now come from a page — a comprehension record and a
//  learning card — and the question "can I go back there, and where to" is the
//  same question for both. One answer, one place.
//

import Foundation

/// The page a kept line was read on, plus what is known about whether it is
/// still there.
struct SourceReference: Hashable, Sendable {
    let comicID: String
    let chapterID: String
    /// 1-based, matching the backend's contract.
    let pageNumber: Int
    /// Joined by the backend from its live catalog at read time, so `nil` is
    /// not "we didn't fetch it" — it is the statement that the comic has left
    /// the library.
    let comicTitle: String?
}

extension SourceReference {
    /// Whether jumping back can actually work.
    ///
    /// A `nil` comic title *is* the signal: the stored ids would still resolve
    /// to a route, and that route would fail. What was kept stays perfectly
    /// readable; only the navigation is withdrawn, which is why this is a
    /// separate question from whether the thing can be shown at all.
    ///
    /// The chapter is not consulted. A comic present with a chapter missing is
    /// the reader having reorganised files under one comic, and the reader
    /// route resolves the chapter itself — so gating on the comic is both the
    /// honest signal and the one the backend actually gives.
    var canJumpToSource: Bool {
        comicTitle != nil
    }

    /// Where jumping back goes: the exact page, read-only.
    ///
    /// Lives beside `canJumpToSource` so the route and the rule guarding it
    /// cannot drift apart. `isPeek` is what keeps re-reading an old scene from
    /// moving where the reader actually is.
    var peekRoute: ReaderRoute {
        ReaderRoute(
            comicID: comicID,
            chapterID: chapterID,
            targetPage: pageNumber,
            isPeek: true
        )
    }
}
