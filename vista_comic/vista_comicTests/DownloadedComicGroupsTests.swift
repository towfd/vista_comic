//
//  DownloadedComicGroupsTests.swift
//  vista_comicTests
//
//  Coverage for `offline-download` ticket 05's arrangement: how what is on the
//  device is grouped and ordered before 已下載 draws it.
//
//  No view, no store, no disk — the ordering is the part worth pinning, and it
//  is a function of two arguments.
//

import Foundation
import Testing
@testable import vista_comic

@Suite("Downloaded comic groups")
struct DownloadedComicGroupsTests {

    private func makeChapter(
        comicID: String,
        comicTitle: String = "Alpha",
        chapterID: String,
        number: Int,
        startedAt: TimeInterval
    ) -> DownloadedChapter {
        DownloadedChapter(
            comicID: comicID,
            comicTitle: comicTitle,
            chapterID: chapterID,
            chapterNumber: number,
            chapterTitle: "Chapter \(number)",
            pageCount: 10,
            startedAt: Date(timeIntervalSince1970: startedAt),
            isComplete: true
        )
    }

    @Test func chaptersAreGroupedByComicAndListedInReadingOrder() {
        let records = [
            makeChapter(comicID: "comic-1", chapterID: "c1-3", number: 3, startedAt: 100),
            makeChapter(comicID: "comic-1", chapterID: "c1-1", number: 1, startedAt: 200),
            makeChapter(comicID: "comic-2", comicTitle: "Beta", chapterID: "c2-1", number: 1, startedAt: 150),
        ]

        let groups = downloadedComicGroups(from: records, sizes: [:])

        #expect(groups.map(\.comicID) == ["comic-1", "comic-2"])
        // Inside a comic the order is the story's, not the download's — it is
        // the only order a list of chapters can be read in.
        #expect(groups.first?.entries.map(\.chapter.chapterNumber) == [1, 3])
    }

    @Test func comicsAreOrderedByTheirMostRecentDownload() {
        let records = [
            makeChapter(comicID: "older", chapterID: "a", number: 1, startedAt: 100),
            makeChapter(comicID: "newer", comicTitle: "Beta", chapterID: "b", number: 1, startedAt: 300),
            makeChapter(comicID: "older", chapterID: "c", number: 2, startedAt: 200),
        ]

        let groups = downloadedComicGroups(from: records, sizes: [:])

        // What the reader was last doing is at the top, which they can find
        // without looking.
        #expect(groups.map(\.comicID) == ["newer", "older"])
    }

    @Test func sizesAreAttachedAndSummedPerComic() {
        let first = makeChapter(comicID: "comic-1", chapterID: "one", number: 1, startedAt: 100)
        let second = makeChapter(comicID: "comic-1", chapterID: "two", number: 2, startedAt: 200)

        let groups = downloadedComicGroups(
            from: [first, second],
            sizes: [first.id: 3_000_000, second.id: 5_000_000]
        )

        #expect(groups.first?.entries.map(\.bytes) == [3_000_000, 5_000_000])
        #expect(groups.first?.bytes == 8_000_000)
    }

    @Test func aChapterWithNoMeasurementCountsAsNothingRatherThanBreaking() {
        // A chapter whose files could not be measured is still a chapter the
        // reader can see and delete; it must not take the screen down with it.
        let chapter = makeChapter(comicID: "comic-1", chapterID: "one", number: 1, startedAt: 100)

        let groups = downloadedComicGroups(from: [chapter], sizes: [:])

        #expect(groups.first?.entries.first?.bytes == 0)
        #expect(groups.first?.bytes == 0)
    }

    @Test func aComicRenamedSinceTheFirstDownloadShowsItsCurrentName() {
        let records = [
            makeChapter(comicID: "comic-1", comicTitle: "Old name", chapterID: "a", number: 1, startedAt: 100),
            makeChapter(comicID: "comic-1", comicTitle: "New name", chapterID: "b", number: 2, startedAt: 200),
        ]

        let groups = downloadedComicGroups(from: records, sizes: [:])

        // The titles come from the records rather than the catalog — which is
        // what lets this screen work with no connection — so the newest record
        // is the most current thing available to name it with.
        #expect(groups.first?.title == "New name")
    }

    @Test func nothingDownloadedIsNoGroups() {
        #expect(downloadedComicGroups(from: [], sizes: [:]).isEmpty)
    }
}
