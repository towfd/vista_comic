//
//  CardLibrary.swift
//  vista_comic
//
//  The 單字庫 tab's derived values, kept as free functions over `[LearningCard]`
//  rather than as computed properties on a view — mirroring
//  `SelectionActions.swift` and the deleted `ComprehensionSummary.swift`: the
//  rules here are the ones most worth testing, and they must be testable
//  without rendering anything.
//

import Foundation
// For `LocalizedStringKey` only. The rules below stay renderer-free and
// testable without a view, the same as `SelectionActions.swift`, which imports
// SwiftUI for the same kind of reason.
import SwiftUI

/// How well a card is known, as a heading the reader can scan.
///
/// A coarsening of `ladderStage`, not a second scale: the ladder is
/// 1/3/7/21/60 days and five headings for five rungs would be a list of
/// intervals rather than a sense of progress.
///
/// **Every card sits in `.new` until stage 3 ships**, because nothing advances
/// `ladderStage` yet. That is why `groupedByFamiliarity` drops empty bands
/// rather than rendering the full set — today this must look like one plain
/// list, and grow headings by itself once scheduling exists.
enum Familiarity: Int, CaseIterable, Hashable {
    case new
    case learning
    case familiar

    init(ladderStage: Int) {
        switch ladderStage {
        case ..<1: self = .new
        case 1...2: self = .learning
        default: self = .familiar
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .new: "New"
        case .learning: "Learning"
        case .familiar: "Familiar"
        }
    }
}

/// One heading and the cards under it.
struct FamiliarityGroup: Identifiable, Hashable {
    let familiarity: Familiarity
    let cards: [LearningCard]

    var id: Int { familiarity.rawValue }
}

/// Groups `cards` into the bands that actually contain something, newest first
/// within each.
///
/// **Empty bands are dropped**, which is what keeps this honest before stage 3:
/// a screen showing "Learning (0)" and "Familiar (0)" above every card the
/// reader owns would be describing a system that does not exist yet.
func groupedByFamiliarity(_ cards: [LearningCard]) -> [FamiliarityGroup] {
    Familiarity.allCases.compactMap { band in
        let members = cards
            .filter { Familiarity(ladderStage: $0.ladderStage) == band }
            .sorted { $0.createdAt > $1.createdAt }
        return members.isEmpty ? nil : FamiliarityGroup(familiarity: band, cards: members)
    }
}

/// The cards matching `query`, across both the source text and the translation.
///
/// **Reuses `normalizedKey`** rather than inventing a second idea of "the same
/// text". There is one definition of that in this app — the one the deck's
/// identity is built on — and a search that disagreed with it would find
/// nothing for a word the reader can plainly see, or claim a duplicate where
/// the deck says there is none.
///
/// That normalisation strips whitespace, so this matches on substrings of a
/// space-free key: searching `SAU KHI` finds a card stored as `SAU  KHI`, and
/// searching `khi` finds it inside a longer line. An empty or whitespace-only
/// query means no filtering at all, rather than matching nothing.
func cardsMatching(_ query: String, in cards: [LearningCard]) -> [LearningCard] {
    let needle = normalizedKey(query)
    guard !needle.isEmpty else { return cards }
    return cards.filter {
        normalizedKey($0.sourceText).contains(needle)
            || normalizedKey($0.translation).contains(needle)
    }
}

extension LearningCard {
    /// Where this card was collected, as the type both this and 歷史紀錄's
    /// records project into — see `Shared/SourceReference.swift`.
    var source: SourceReference {
        SourceReference(
            comicID: comicID,
            chapterID: chapterID,
            pageNumber: pageNumber,
            comicTitle: comicTitle
        )
    }

    /// How this card is described where it came from, or `nil` when the comic
    /// has left the library — which is also when jumping back would fail.
    var sourceLabel: String? {
        guard let comicTitle else { return nil }
        guard let chapterTitle else { return comicTitle }
        return "\(comicTitle) · \(chapterTitle)"
    }
}
