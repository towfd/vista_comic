//
//  HistorySummaryTests.swift
//  vista_comicTests
//
//  `comprehension-response-ux` ticket 19: the two rules 歷史紀錄 derives from a
//  fetched list — what the badge counts, and what each row's status line says.
//
//  These are free functions over `[ComprehensionRecord]` precisely so they can
//  be tested without rendering anything, mirroring `SelectionActions`' seams.
//  Reuses `ComprehensionRecord.preview(...)`, the factory `HistoryView`'s own
//  `#Preview`s use, so the fixtures and the previews cannot drift apart.
//

import Foundation
import Testing

@testable import vista_comic

@Suite("What 歷史紀錄 derives from its list")
struct HistorySummaryTests {

    // MARK: - The badge

    /// The badge points at things worth going back to read. Everything else in
    /// this list has either already been read in place or has nothing to read.
    @Test func onlyAnArrivedUnreadExplanationCounts() async throws {
        let records: [ComprehensionRecord] = [
            .preview(id: 1, status: "ok", notes: "…", isRead: false),   // counts
            .preview(id: 2, status: "ok", notes: "…", isRead: true),    // already read
            .preview(id: 3, status: "pending"),                          // still coming
            .preview(id: 4, status: "running"),                          // still coming
            .preview(id: 5, status: "failed"),                           // dead end
            .preview(id: 6, status: "declined"),                         // dead end
        ]

        #expect(unreadExplanationCount(in: records) == 1)
    }

    /// The fast translation is not something to go back and read — the reader
    /// read it in place, seconds ago. A record that finished without notes must
    /// never badge, however it finished.
    @Test func aRecordThatFinishedWithoutNotesNeverCounts() async throws {
        let noNotes = ComprehensionRecord.preview(status: "ok", isRead: false)

        #expect(noNotes.isUnreadExplanation == false)
        #expect(unreadExplanationCount(in: [noNotes]) == 0)
    }

    /// A record the reader watched land on the result screen was marked read
    /// there, so it arrives here already excluded — no second mechanism needed.
    @Test func oneWatchedLandOnTheResultScreenIsAlreadyExcluded() async throws {
        let watched = ComprehensionRecord.preview(status: "ok", notes: "…", isRead: true)

        #expect(watched.isUnreadExplanation == false)
    }

    @Test func anEmptyListBadgesNothing() async throws {
        #expect(unreadExplanationCount(in: []) == 0)
    }

    // MARK: - The row's status line

    /// Four outcomes the reader would act on differently, so four glyphs.
    @Test func eachOutcomeGetsItsOwnRowStatus() async throws {
        #expect(ComprehensionRecord.preview(status: "ok", notes: "…").rowStatus == .arrived)
        #expect(ComprehensionRecord.preview(status: "pending").rowStatus == .inProgress)
        #expect(ComprehensionRecord.preview(status: "running").rowStatus == .inProgress)
        #expect(ComprehensionRecord.preview(status: "declined").rowStatus == .declined)
        #expect(ComprehensionRecord.preview(status: "failed").rowStatus == .failed)
    }

    /// Same reasoning as the result screen's section: an `ok` record carrying
    /// no notes is a failure the reader should see as one, not an "arrived"
    /// row that opens onto nothing.
    @Test func okWithoutNotesReadsAsFailedRatherThanArrived() async throws {
        #expect(ComprehensionRecord.preview(status: "ok").rowStatus == .failed)
    }

    /// A status this build has never heard of is more likely a newer
    /// in-progress step than a failure, so it must not show an error glyph.
    @Test func anUnknownStatusReadsAsStillInProgress() async throws {
        #expect(ComprehensionRecord.preview(status: "something-new").rowStatus == .inProgress)
    }

    /// The four glyphs must actually be four, or the distinction is decorative.
    @Test func theFourStatusesAreVisuallyDistinct() async throws {
        let symbols = Set(
            [ComprehensionRowStatus.arrived, .inProgress, .declined, .failed]
                .map(\.symbolName)
        )

        #expect(symbols.count == 4)
    }

    // MARK: - Provenance

    /// The detail screen follows the same precedence as the result screen, so
    /// one record reads identically in both places.
    @Test func theDetailShowsTheCloudWordingWherePresent() async throws {
        let landed = ComprehensionRecord.preview(
            status: "ok", notes: "…", cloudTranslation: "你小子，挺有一套的嘛"
        )

        #expect(landed.displayedTranslation == "你小子，挺有一套的嘛")
        #expect(
            ComprehensionRecord.preview().displayedTranslation == "你這家伙，還挺有兩下子的嘛"
        )
    }

    /// The row spends no line on the translation, so its glyph has to carry the
    /// provenance signal instead: a cloud appears exactly when a cloud
    /// translation exists.
    @Test func onlyAnArrivedRowCarriesTheCloudGlyph() async throws {
        #expect(ComprehensionRowStatus.arrived.symbolName == "cloud")

        for other in [ComprehensionRowStatus.inProgress, .declined, .failed] {
            #expect(other.symbolName != "cloud")
        }
    }

    /// A comic that left the library must not take its records with it — the
    /// titles simply go missing, and the record stays readable.
    @Test func aRecordSurvivesItsComicLeavingTheLibrary() async throws {
        let orphan = ComprehensionRecord.preview(
            status: "ok", notes: "…", comicTitle: nil, chapterTitle: nil
        )

        #expect(orphan.comicTitle == nil)
        #expect(orphan.displayedTranslation.isEmpty == false)
        #expect(orphan.rowStatus == .arrived)
    }
}
