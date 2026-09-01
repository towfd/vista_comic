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

/// Days between reviews, by slot.
///
/// Mirrors `LADDER_INTERVALS` in `backend/app/ladder.py`. Seven entries since
/// stage 6: the two added continue the table's own ratio, where 90 and 120
/// would have flattened the curve exactly where a card has proved itself most
/// stable.
let ladderIntervals = [1, 3, 7, 21, 60, 150, 365]

/// The highest slot. Shown to the reader as the denominator, so a slot is a
/// position in something finite rather than a bare number.
let ladderTopRung = ladderIntervals.count - 1

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

    /// The heading's colour, or `nil` for the quiet one.
    ///
    /// Kept beside `title` because it is the same decision — how this heading
    /// presents itself — and drawn from the two colour families the app already
    /// has rather than a third invented for this screen. Unclassified takes no
    /// colour on purpose: it is the section with work in it, and giving it a
    /// band as strong as the others would have the reader's mis-taps shouting
    /// every time the tab opens.
    var accent: Color? {
        switch kind {
        case .word: .practiceTeal
        case .sentence: .primaryRed
        case nil: nil
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
/// Where a card stands is on the row itself rather than a heading — see
/// `CardSchedule.swift`. It is four states and seven intervals, so grouping by
/// it would be eleven headings over a deck of thirty.
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
