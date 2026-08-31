//
//  CardLibraryTests.swift
//  vista_comicTests
//
//  The 單字庫 tab's grouping and search (vocabulary stage 2, ticket 03).
//
//  The assertion that matters most here is the dullest one: **a deck where
//  every card sits on the same rung renders one section, not three with two
//  empty**. That is the state the app is actually in until stage 3 ships, so a
//  grouping that looks right only once scheduling exists would look wrong for
//  every day between now and then.
//

import Foundation
import Testing

@testable import vista_comic

@Suite("Grouping the deck by what each card is")
struct CardGroupingTests {

    @Test("Cards land under the kind the reader chose")
    func cardsLandUnderTheirKind() {
        let deck = [
            LearningCard.preview(id: 1, kind: "word"),
            LearningCard.preview(id: 2, kind: "sentence"),
            LearningCard.preview(id: 3, kind: nil),
        ]

        let groups = groupedByKind(deck)

        #expect(groups.map(\.kind) == [.word, .sentence, nil])
        #expect(groups.map { $0.cards.map(\.id) } == [[1], [2], [3]])
    }

    @Test("Unclassified sorts last")
    func unclassifiedSortsLast() {
        // It is the section with work in it, and putting the reader's mistakes
        // at the top every time they open the tab would nag rather than help.
        let deck = [
            LearningCard.preview(id: 1, kind: nil),
            LearningCard.preview(id: 2, kind: "word"),
        ]

        #expect(groupedByKind(deck).map(\.kind) == [.word, nil])
    }

    @Test("An empty section is dropped rather than shown empty")
    func emptySectionsAreDropped() {
        // A deck of only words should not carry an empty "Sentences" heading.
        let deck = [LearningCard.preview(kind: "word")]

        #expect(groupedByKind(deck).map(\.kind) == [.word])
    }

    @Test("Newest first within a section")
    func newestFirstWithinASection() {
        // "I just mis-tapped" is one of the only two ways into this screen, and
        // it is answered by the newest card being at the top.
        let deck = [
            LearningCard.preview(id: 1, kind: "word", createdAt: "2026-08-01T10:00:00Z"),
            LearningCard.preview(id: 2, kind: "word", createdAt: "2026-08-19T10:00:00Z"),
            LearningCard.preview(id: 3, kind: "word", createdAt: "2026-08-10T10:00:00Z"),
        ]

        #expect(groupedByKind(deck).first?.cards.map(\.id) == [2, 3, 1])
    }

    @Test("An empty deck has no sections at all")
    func anEmptyDeckHasNoSections() {
        #expect(groupedByKind([]).isEmpty)
    }
}

@Suite("How well a card is known")
struct FamiliarityTests {

    @Test("Each ladder rung maps to a band", arguments: [
        (0, Familiarity.new),
        (1, Familiarity.learning),
        (2, Familiarity.learning),
        (3, Familiarity.familiar),
        (4, Familiarity.familiar),
    ])
    func rungsMapToBands(_ pair: (Int, Familiarity)) {
        #expect(Familiarity(ladderStage: pair.0) == pair.1)
    }

    @Test("Every band shows on a row, including the bottom one", arguments: Familiarity.allCases)
    func everyBandShowsOnARow(_ band: Familiarity) {
        // Reversed by stage 4, deliberately. `.new` was hidden while nothing
        // could move a card off it and six identical badges would have been
        // noise. Now that practice moves cards, an absent badge and a card
        // still at the bottom looked the same on screen — and telling those two
        // apart is the reason a reader opens this list after a round.
        #expect(band.isWorthShowing)
    }

    @Test("The top rung matches the backend\'s ladder")
    func theTopRungMatchesTheBackend() {
        // `LADDER_INTERVALS` in `backend/app/ladder.py` — seven entries since
        // stage 6, and shown to the reader as a denominator. Two constants, one
        // fact, so it is pinned here rather than left to be noticed.
        #expect(ladderTopRung == 6)
        #expect(ladderIntervals == [1, 3, 7, 21, 60, 150, 365])
        #expect(Familiarity(ladderStage: ladderTopRung) == .familiar)
    }
}

@Suite("Searching the deck")
struct CardSearchTests {

    private let deck = [
        LearningCard.preview(id: 1, sourceText: "大丈夫ですか", translation: "你還好嗎"),
        LearningCard.preview(id: 2, sourceText: "SAU KHI", translation: "之後"),
    ]

    @Test("An empty query filters nothing")
    func anEmptyQueryFiltersNothing() {
        #expect(cardsMatching("", in: deck).count == 2)
        #expect(cardsMatching("   ", in: deck).count == 2)
    }

    @Test("The source text is searchable")
    func theSourceTextIsSearchable() {
        #expect(cardsMatching("大丈夫", in: deck).map(\.id) == [1])
    }

    @Test("The translation is searchable")
    func theTranslationIsSearchable() {
        // "I remember one of these being translated oddly" is the other way in,
        // and the reader remembers the meaning, not the foreign spelling.
        #expect(cardsMatching("還好", in: deck).map(\.id) == [1])
    }

    @Test("Search agrees with the deck's own idea of the same text")
    func searchUsesTheDecksNormalisation() {
        // Reusing `normalizedKey` rather than a second matching rule: a search
        // that disagreed with the identity the deck is built on would find
        // nothing for a word the reader can plainly see.
        #expect(cardsMatching("sau khi", in: deck).map(\.id) == [2])
        #expect(cardsMatching("SAU  KHI", in: deck).map(\.id) == [2])
        #expect(cardsMatching("ｓａｕ", in: deck).map(\.id) == [2])
    }

    @Test("A query matching nothing returns nothing, rather than everything")
    func aQueryMatchingNothingReturnsNothing() {
        #expect(cardsMatching("食べる", in: deck).isEmpty)
    }
}

@Suite("What a card says about where it came from")
struct CardSourceLabelTests {

    @Test("A card in the library names its comic and chapter")
    func aCardInTheLibraryNamesItsSource() {
        #expect(LearningCard.preview().sourceLabel == "marrymyhusband · bai1")
    }

    @Test("A comic that has left the library has no label and no jump")
    func aMissingComicHasNoLabelAndNoJump() {
        // One signal, used twice: the row must not name a source it cannot
        // open, and must not offer a link that would fail.
        let orphan = LearningCard.preview(comicTitle: nil, chapterTitle: nil)

        #expect(orphan.sourceLabel == nil)
        #expect(orphan.source.canJumpToSource == false)
    }

    @Test("A missing chapter still names the comic")
    func aMissingChapterStillNamesTheComic() {
        // The comic is what decides whether the jump works; a chapter gone
        // under a comic that is still there is the reader having reorganised
        // files, and the reader route resolves the chapter itself.
        let card = LearningCard.preview(chapterTitle: nil)

        #expect(card.sourceLabel == "marrymyhusband")
        #expect(card.source.canJumpToSource)
    }
}
