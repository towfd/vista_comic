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

@Suite("Grouping the deck by familiarity")
struct FamiliarityGroupingTests {

    @Test("Every card is new until scheduling exists, so there is one section")
    func oneRungMakesOneSection() {
        // Stage 1 writes ladderStage 0 and nothing advances it yet. Headings
        // for bands the reader cannot reach would describe a system that does
        // not exist.
        let deck = [
            LearningCard.preview(id: 1, ladderStage: 0),
            LearningCard.preview(id: 2, ladderStage: 0),
        ]

        let groups = groupedByFamiliarity(deck)

        #expect(groups.count == 1)
        #expect(groups.first?.familiarity == .new)
        #expect(groups.first?.cards.count == 2)
    }

    @Test("Bands appear as cards reach them, in order")
    func bandsAppearAsCardsReachThem() {
        let deck = [
            LearningCard.preview(id: 1, ladderStage: 4),
            LearningCard.preview(id: 2, ladderStage: 0),
            LearningCard.preview(id: 3, ladderStage: 2),
        ]

        let groups = groupedByFamiliarity(deck)

        #expect(groups.map(\.familiarity) == [.new, .learning, .familiar])
    }

    @Test("An empty band is dropped rather than shown as empty")
    func emptyBandsAreDropped() {
        let deck = [LearningCard.preview(ladderStage: 4)]

        let groups = groupedByFamiliarity(deck)

        #expect(groups.map(\.familiarity) == [.familiar])
    }

    @Test("Newest first within a band")
    func newestFirstWithinABand() {
        let deck = [
            LearningCard.preview(id: 1, createdAt: "2026-08-01T10:00:00Z"),
            LearningCard.preview(id: 2, createdAt: "2026-08-19T10:00:00Z"),
            LearningCard.preview(id: 3, createdAt: "2026-08-10T10:00:00Z"),
        ]

        let groups = groupedByFamiliarity(deck)

        // "I just mis-tapped" is one of the only two ways into this screen, and
        // it is answered by the newest card being at the top.
        #expect(groups.first?.cards.map(\.id) == [2, 3, 1])
    }

    @Test("An empty deck has no groups at all")
    func anEmptyDeckHasNoGroups() {
        #expect(groupedByFamiliarity([]).isEmpty)
    }

    @Test("Each ladder rung lands in the band it belongs to", arguments: [
        (0, Familiarity.new),
        (1, Familiarity.learning),
        (2, Familiarity.learning),
        (3, Familiarity.familiar),
        (4, Familiarity.familiar),
    ])
    func rungsMapToBands(_ pair: (Int, Familiarity)) {
        #expect(Familiarity(ladderStage: pair.0) == pair.1)
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
