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

@Suite("What a card says about itself")
struct CardScheduleReadoutTests {

    @Test("A new card says so and nothing else")
    func aNewCardSaysOnlyThat() {
        // No due time: a new card waits on the day's quota, not on a clock,
        // and "due now" beside it would be describing the wrong thing.
        let card = LearningCard.preview(state: "new")

        #expect(scheduleSummary(of: card, steps: [5, 7, 10]) == "New")
    }

    @Test("A learning card says which step it is on")
    func aLearningCardCountsItsSteps() {
        // The complaint that started stage 6 was a reader practising a card for
        // days and being told "New" each time. This is the answer: a number
        // that moves.
        let card = LearningCard.preview(state: "learning", learningStep: 1)

        #expect(scheduleState(of: card, steps: [5, 7, 10]) == "Learning 2/3")
    }

    @Test("A relearning card is named apart from a learning one")
    func relearningIsItsOwnWord() {
        // They are the same steps and a different situation: one is a word
        // being met, the other a word being recovered.
        let card = LearningCard.preview(state: "relearning", learningStep: 0)

        #expect(scheduleState(of: card, steps: [5, 7, 10]) == "Relearning 1/3")
    }

    @Test("The step count follows the reader's own settings")
    func theStepCountIsNotHardcoded() {
        let card = LearningCard.preview(state: "learning", learningStep: 1)

        #expect(scheduleState(of: card, steps: [1, 5]) == "Learning 2/2")
    }

    @Test("A card past the end of a shortened list is clamped, not misreported")
    func aShortenedListClamps() {
        let card = LearningCard.preview(state: "learning", learningStep: 4)

        #expect(scheduleState(of: card, steps: [5, 7]) == "Learning 2/2")
    }

    @Test("A graduated card is described by its interval, not its slot number")
    func aReviewCardShowsItsInterval() {
        // "21 days" is a fact about the reader's memory; "slot 3" is a fact
        // about an array.
        let card = LearningCard.preview(state: "review", ladderStage: 3)

        #expect(scheduleState(of: card, steps: [5, 7, 10]) == "21 days")
    }

    @Test("A card already due says so rather than counting backwards")
    func anOverdueCardSaysDueNow() {
        let card = LearningCard.preview(
            state: "review", dueAt: "2020-01-01T00:00:00Z"
        )

        #expect(scheduleDue(of: card) == "due now")
    }

    @Test("The interval table matches the backend's")
    func theIntervalsMatchTheBackend() {
        // `LADDER_INTERVALS` in `backend/app/ladder.py` — seven entries since
        // stage 6, and shown to the reader as a denominator. Two constants, one
        // fact, so it is pinned here rather than left to be noticed.
        #expect(ladderTopRung == 6)
        #expect(ladderIntervals == [1, 3, 7, 21, 60, 150, 365])
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
