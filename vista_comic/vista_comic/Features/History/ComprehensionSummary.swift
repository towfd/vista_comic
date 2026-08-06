//
//  ComprehensionSummary.swift
//  vista_comic
//
//  The 歷史紀錄 tab's derived values, kept as free functions over
//  `[ComprehensionRecord]` rather than as computed properties on a view —
//  mirroring `SelectionActions.swift`'s reasoning: the rules here are the ones
//  most worth testing, and they must be testable without rendering anything.
//

import Foundation

/// How many records the reader has an unread explanation for — the number the
/// tab badge shows.
///
/// Computed client-side from the fetched list because there is no count
/// endpoint and no shared client store: the tab that owns the list is the only
/// thing that knows, and adding a store to share a number two screens apart
/// would be more machinery than the number is worth.
///
/// **Only an explanation that actually arrived can be unread.** A fast
/// translation is not something to go back and read — the reader already read
/// it, in place, seconds ago. A failure is not something to go and read at all;
/// badging it would send them to a dead end. And a record the reader watched
/// land on the result screen was marked read there, so it is already excluded
/// by `isRead`.
func unreadExplanationCount(in records: [ComprehensionRecord]) -> Int {
    records.filter(\.isUnreadExplanation).count
}

extension ComprehensionRecord {
    /// Whether this record is one the badge should be counting.
    var isUnreadExplanation: Bool {
        status == .ok && hasExplanation && !isRead
    }

    /// Whether jumping back to the page this record came from can actually
    /// work.
    ///
    /// The titles are joined by the backend from its live catalog, so a `nil`
    /// comic title *is* the statement that the comic has left the library — the
    /// stored ids would still resolve to a route, and that route would fail.
    /// The record itself stays perfectly readable; only the navigation is
    /// withdrawn, which is why this is a separate question from whether the
    /// record can be shown at all.
    ///
    /// The chapter is not consulted: a comic present with a chapter missing is
    /// the reader having reorganised files under one comic, and the reader
    /// route resolves the chapter itself — so gating on the comic is both the
    /// honest signal and the one the backend actually gives.
    var canJumpToSource: Bool {
        comicTitle != nil
    }

    /// The one-line status shown on a row, distinguishing the four outcomes
    /// the reader can actually act on differently.
    ///
    /// Deliberately a separate vocabulary from `ComprehensionDetailSection`'s:
    /// that one describes a whole section and folds in enqueue failures the
    /// list can never contain (no record was created, so there is no row).
    /// Trying to share one type across both would mean a list row switching
    /// over cases it cannot reach.
    var rowStatus: ComprehensionRowStatus {
        switch status {
        case .ok where hasExplanation: return .arrived
        case .pending, .running, .unknown: return .inProgress
        case .declined: return .declined
        case .ok, .failed: return .failed
        }
    }
}

/// What a row's status line says, and how it looks.
enum ComprehensionRowStatus: Equatable {
    case arrived
    case inProgress
    case declined
    case failed

    /// SF Symbol shown beside the source reference.
    ///
    /// `arrived` is a cloud rather than a checkmark on purpose: an arrived
    /// record is exactly the one carrying a cloud translation, so this single
    /// glyph doubles as the row's provenance signal — which is how the row
    /// conveys "the cloud version exists" without spending a third line
    /// repeating the translation itself (see `ComprehensionRow`).
    var symbolName: String {
        switch self {
        case .arrived: return "cloud"
        case .inProgress: return "clock"
        case .declined: return "minus.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }
}
