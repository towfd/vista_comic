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
/// 1/3/7/21/60 days and five labels for five rungs would be a list of intervals
/// rather than a sense of progress.
///
/// **Every card sits in `.new` until stage 3 ships**, because nothing advances
/// `ladderStage` yet. That is why this is shown one card at a time rather than
/// used to group the list, and why a row mentions it only once a card has
/// actually moved: six identical badges would be noise, and the same six become
/// worth reading the moment they start to differ.
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

    /// Whether this is worth putting on a list row.
    ///
    /// `.new` is not: it is where every card starts and, before stage 3, where
    /// every card still is.
    var isWorthShowing: Bool { self != .new }
}

/// One heading and the cards under it.
struct CardGroup: Identifiable, Hashable {
    /// `nil` is the unclassified section — cards collected before the reader
    /// could say which they were, and mis-taps waiting to be corrected.
    let kind: CardKind?
    let cards: [LearningCard]

    var id: String { kind?.rawValue ?? "unclassified" }

    var title: LocalizedStringKey {
        switch kind {
        case .word: "Words"
        case .sentence: "Sentences"
        case nil: "Unclassified"
        }
    }
}

/// Groups `cards` by what the reader said each one is, newest first within each.
///
/// **By kind rather than by familiarity**, because kind is what actually varies
/// today: `ladderStage` is written as 0 by stage 1 and nothing advances it until
/// stage 3, so familiarity bands would be one heading over everything for weeks.
/// Kind also matches what this screen is for — the unclassified section is a
/// list of cards needing work, which is a workshop's natural first question.
///
/// Familiarity has not gone away; it moved to where it can be read one card at a
/// time (`CardDetailView`), and appears on a row only once a card has actually
/// advanced.
///
/// **Empty sections are dropped**: a deck of only words should not carry an
/// empty "Sentences" heading.
///
/// Unclassified sorts last. It is the section with work in it, and a heading
/// that put the reader's mistakes at the top every time they opened the tab
/// would nag rather than help.
func groupedByKind(_ cards: [LearningCard]) -> [CardGroup] {
    let order: [CardKind?] = [.word, .sentence, nil]
    return order.compactMap { kind in
        let members = cards
            .filter { $0.kind == kind }
            .sorted { $0.createdAt > $1.createdAt }
        return members.isEmpty ? nil : CardGroup(kind: kind, cards: members)
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
