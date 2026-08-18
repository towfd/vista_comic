//
//  OfflineChapterStoreTests.swift
//  vista_comicTests
//
//  Coverage for `offline-download` ticket 01's storage half: what is on the
//  device, that it survives a relaunch, and that the cap cannot be walked past.
//
//  Every test runs against a **temporary directory injected into the store**.
//  Nothing here may touch the real Application Support path — a test suite that
//  can delete the reader's downloads is a worse bug than anything it could find.
//
//  These assert on what a caller observes — what the store answers, what is on
//  disk, which slots are free — never on how the directory is laid out, so the
//  layout can change without rewriting the suite.
//

import Foundation
import Testing
@testable import vista_comic

@Suite("Offline chapter store")
struct OfflineChapterStoreTests {

    // MARK: - Fixtures

    private func makeChapter(
        comicID: String = "comic-1",
        chapterID: String = "chapter-1",
        number: Int = 1,
        pages: [String] = ["https://example.test/page-1", "https://example.test/page-2"],
        startedAt: Date = Date(),
        isComplete: Bool = false
    ) -> DownloadedChapter {
        DownloadedChapter(
            comicID: comicID,
            comicTitle: "Alpha",
            chapterID: chapterID,
            chapterNumber: number,
            chapterTitle: "Chapter \(number)",
            pageURLs: pages.map { URL(string: $0)! },
            pageCount: pages.count,
            startedAt: startedAt,
            isComplete: isComplete
        )
    }

    /// Runs `body` against a store rooted in a directory that exists only for
    /// this test, and removes it afterwards however the test ends.
    private func withStore(
        chapterLimit: Int = OfflineDownloadLimits.maxChapters,
        _ body: (FileOfflineChapterStore, URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-store-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try FileOfflineChapterStore(root: root, chapterLimit: chapterLimit)
        try body(store, root)
    }

    // MARK: - Records

    @Test func anAdmittedChapterIsFoundAndListed() throws {
        try withStore { store, _ in
            let chapter = makeChapter()
            try store.admit(chapter)

            #expect(store.downloadedChapter(chapter.id) == chapter)
            #expect(store.downloadedChapters() == [chapter])
        }
    }

    @Test func chaptersAreListedOldestDownloadFirst() throws {
        try withStore { store, _ in
            let older = makeChapter(chapterID: "older", startedAt: Date(timeIntervalSince1970: 100))
            let newer = makeChapter(chapterID: "newer", startedAt: Date(timeIntervalSince1970: 200))

            try store.admit(newer)
            try store.admit(older)

            // The order ticket 04 will evict in, so it is worth pinning now.
            #expect(store.downloadedChapters().map(\.chapterID) == ["older", "newer"])
        }
    }

    // MARK: - The cap, and what it removes

    @Test func admittingAtTheCapEvictsTheOldestDownload() throws {
        try withStore(chapterLimit: 2) { store, _ in
            let oldest = makeChapter(chapterID: "oldest", startedAt: Date(timeIntervalSince1970: 100))
            let middle = makeChapter(chapterID: "middle", startedAt: Date(timeIntervalSince1970: 200))
            // Filling the device exactly to the cap costs nothing: the boundary
            // is "one more than fits", not "as many as fit".
            #expect(try store.admit(oldest) == nil)
            #expect(try store.admit(middle) == nil)

            let evicted = try store.admit(
                makeChapter(chapterID: "newest", startedAt: Date(timeIntervalSince1970: 300))
            )

            // The reader is never stopped and asked to tidy up.
            #expect(evicted == oldest.id)
            #expect(store.downloadedChapters().map(\.chapterID) == ["middle", "newest"])
            #expect(store.downloadedChapter(oldest.id) == nil)
        }
    }

    @Test func evictionRemovesThePagesAndNotJustTheRecord() throws {
        try withStore(chapterLimit: 1) { store, root in
            let oldest = makeChapter(chapterID: "oldest", startedAt: Date(timeIntervalSince1970: 100))
            try store.admit(oldest)
            for page in oldest.pageURLs {
                try store.writePage(Data("page bytes".utf8), for: page, of: oldest.id)
            }

            try store.admit(makeChapter(chapterID: "newest", startedAt: Date(timeIntervalSince1970: 200)))

            // The space is genuinely freed — this is the only irreversible thing
            // the feature does, so "gone" has to mean gone from the disk.
            #expect(store.hasPage(oldest.pageURLs[0], of: oldest.id) == false)
            #expect(store.pageData(for: oldest.pageURLs[0]) == nil)
            let directories = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            )
            #expect(directories.count == 1)
        }
    }

    @Test func evictionDoesNotConsultWhetherAChapterWasFinished() throws {
        try withStore(chapterLimit: 1) { store, _ in
            // Complete is the only state of a chapter the store knows at all,
            // and it is deliberately not a factor: strict first-in-first-out is
            // a rule the reader can predict without knowing what the app thinks
            // they have read.
            var finished = makeChapter(chapterID: "finished", startedAt: Date(timeIntervalSince1970: 100))
            finished.isComplete = true
            try store.admit(finished)

            let evicted = try store.admit(
                makeChapter(chapterID: "newer", startedAt: Date(timeIntervalSince1970: 200))
            )

            #expect(evicted == finished.id)
        }
    }

    @Test func admittingFiveAtTheCapEvictsExactlyFive() throws {
        try withStore(chapterLimit: 3) { store, _ in
            for index in 0..<3 {
                try store.admit(
                    makeChapter(
                        chapterID: "old-\(index)",
                        startedAt: Date(timeIntervalSince1970: TimeInterval(100 + index))
                    )
                )
            }

            var evicted: [DownloadedChapterID] = []
            for index in 0..<5 {
                if let victim = try store.admit(
                    makeChapter(
                        chapterID: "new-\(index)",
                        startedAt: Date(timeIntervalSince1970: TimeInterval(200 + index))
                    )
                ) {
                    evicted.append(victim)
                }
            }

            // Five in, five out — the semantics ticket 06's batch download
            // relies on, settled here rather than discovered there.
            #expect(evicted.count == 5)
            #expect(store.downloadedChapters().count == 3)
            #expect(store.downloadedChapters().map(\.chapterID) == ["new-2", "new-3", "new-4"])
        }
    }

    @Test func theChapterBeingReadIsNeverTheOneEvicted() throws {
        try withStore(chapterLimit: 2) { store, _ in
            let beingRead = makeChapter(chapterID: "being-read", startedAt: Date(timeIntervalSince1970: 100))
            let other = makeChapter(chapterID: "other", startedAt: Date(timeIntervalSince1970: 200))
            try store.admit(beingRead)
            try store.admit(other)

            let evicted = try store.admit(
                makeChapter(chapterID: "newest", startedAt: Date(timeIntervalSince1970: 300)),
                protecting: beingRead.id
            )

            // It is the oldest, and it would have gone — but deleting the pages
            // out from under someone who is reading them is never the answer.
            #expect(evicted == other.id)
            #expect(store.downloadedChapter(beingRead.id) != nil)
        }
    }

    @Test func aFullDeviceWithNothingEvictableRefuses() throws {
        try withStore(chapterLimit: 1) { store, _ in
            let beingRead = makeChapter(chapterID: "being-read")
            try store.admit(beingRead)

            #expect(throws: OfflineDownloadError.chapterLimitReached) {
                try store.admit(makeChapter(chapterID: "newest"), protecting: beingRead.id)
            }
            #expect(store.downloadedChapters().map(\.chapterID) == ["being-read"])
        }
    }

    @Test func resumingAnInterruptedChapterDoesNotTakeASecondSlot() throws {
        try withStore(chapterLimit: 2) { store, _ in
            // Re-admitting must not evict anything either: a resume is not a new
            // download, so nothing has to make room for it.
            let started = Date(timeIntervalSince1970: 100)
            let chapter = makeChapter(startedAt: started)
            try store.admit(chapter)
            try store.admit(makeChapter(chapterID: "other"))

            // Re-admitting at the cap, which would throw if it counted as new.
            try store.admit(makeChapter(startedAt: Date(timeIntervalSince1970: 9_999)))

            #expect(store.downloadedChapters().count == 2)
            // And it keeps its original position in the eviction order.
            #expect(store.downloadedChapter(chapter.id)?.startedAt == started)
        }
    }

    @Test func updatingAChapterThatWasNeverAdmittedIsRefused() throws {
        try withStore { store, _ in
            // Admitting is what reserves a slot, so a record that could be
            // written without it would let the cap be walked straight past.
            #expect(throws: OfflineDownloadError.unknownChapter) {
                try store.update(makeChapter())
            }
            #expect(store.downloadedChapters().isEmpty)
        }
    }

    // MARK: - Pages

    @Test func aWrittenPageIsFoundAndOnlyForItsOwnChapter() throws {
        try withStore { store, _ in
            let chapter = makeChapter()
            let other = makeChapter(chapterID: "chapter-2", number: 2)
            try store.admit(chapter)
            try store.admit(other)

            let page = chapter.pageURLs[0]
            #expect(store.hasPage(page, of: chapter.id) == false)

            try store.writePage(Data("page bytes".utf8), for: page, of: chapter.id)

            #expect(store.hasPage(page, of: chapter.id))
            #expect(store.hasPage(chapter.pageURLs[1], of: chapter.id) == false)
            // Chapters do not share each other's pages, even for the same URL —
            // otherwise deleting one would silently empty another.
            #expect(store.hasPage(page, of: other.id) == false)
        }
    }

    @Test func aPartiallyDownloadedChapterIsNotComplete() throws {
        try withStore { store, _ in
            let chapter = makeChapter()
            try store.admit(chapter)
            try store.writePage(Data("page bytes".utf8), for: chapter.pageURLs[0], of: chapter.id)

            // Nothing marked it complete, and having some pages must never be
            // mistaken for having them all.
            #expect(store.isComplete(chapter.id) == false)
        }
    }

    @Test func deletingRemovesTheRecordAndThePagesAndFreesTheSlot() throws {
        try withStore(chapterLimit: 1) { store, root in
            let chapter = makeChapter()
            try store.admit(chapter)
            for page in chapter.pageURLs {
                try store.writePage(Data("page bytes".utf8), for: page, of: chapter.id)
            }

            try store.delete(chapter.id)

            #expect(store.downloadedChapter(chapter.id) == nil)
            #expect(store.hasPage(chapter.pageURLs[0], of: chapter.id) == false)
            // The bytes are actually gone, not merely forgotten.
            let leftovers = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            )
            #expect(leftovers.isEmpty)
            // And the slot is free, which is the point of deleting at the cap.
            try store.admit(makeChapter(chapterID: "replacement"))
            #expect(store.downloadedChapters().count == 1)
        }
    }

    // MARK: - Surviving a relaunch

    @Test func downloadsSurviveANewStoreOverTheSameDirectory() throws {
        try withStore { store, root in
            var chapter = makeChapter()
            try store.admit(chapter)
            for page in chapter.pageURLs {
                try store.writePage(Data("page bytes".utf8), for: page, of: chapter.id)
            }
            chapter.isComplete = true
            try store.update(chapter)

            // A second store over the same directory is what a relaunch is.
            let relaunched = try FileOfflineChapterStore(root: root)

            #expect(relaunched.downloadedChapter(chapter.id) == chapter)
            #expect(relaunched.isComplete(chapter.id))
            #expect(relaunched.hasPage(chapter.pageURLs[0], of: chapter.id))
        }
    }

    // MARK: - Where downloads live

    @Test func theStoreDirectoryIsExcludedFromBackup() throws {
        try withStore { _, root in
            let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(values.isExcludedFromBackup == true)
        }
    }

    @Test func downloadsLiveUnderApplicationSupportRatherThanCaches() throws {
        let root = try FileOfflineChapterStore.defaultRoot()

        // Caches is reclaimed under disk pressure, which would silently delete
        // the one thing this feature promises to keep.
        #expect(root.path.contains("Application Support"))
        #expect(root.path.contains("Caches") == false)
    }
}
