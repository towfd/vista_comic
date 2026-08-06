//
//  ComprehensionDetailView.swift
//  vista_comic
//
//  One 歷史紀錄 record in full (`comprehension-response-ux` ticket 19).
//
//  Renders the *same* vocabulary as the reader's result sheet rather than
//  inventing a second one: the translation with its provenance chip, then the
//  shared `ComprehensionDetailSection` in whichever state applies. That sharing
//  is why ticket 18 built the section into `Shared/` — a reader who saw an
//  explanation arrive in place should recognise it unchanged here.
//
//  Opening this screen is what "read" means, so marking read happens here and
//  nowhere else. Visiting the tab clears nothing.
//

import SwiftUI

struct ComprehensionDetailView: View {
    let record: ComprehensionRecord
    /// Called once this record has been marked read on the backend, so the
    /// list can drop it from the badge without re-fetching. Passed in rather
    /// than reaching back into the list's state, per CLAUDE.md's rule about
    /// passing actions into views instead of hard-coding behavior in them.
    var onMarkedRead: (ComprehensionRecord) -> Void = { _ in }

    @Environment(\.comprehensionRepository) private var repository

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sourceHeader

                VStack(alignment: .leading, spacing: 4) {
                    Text("Original")
                        .font(AppFont.rowTitle)
                    Text(record.sourceText)
                        .font(AppFont.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Translation")
                            .font(AppFont.rowTitle)
                        TranslationProvenanceChip(isCloud: record.cloudTranslation != nil)
                    }
                    Text(record.displayedTranslation)
                        .font(AppFont.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // No `retry` action: retrying is the next ticket. Passing none
                // means the section shows the failure copy without offering a
                // button that would do nothing.
                ComprehensionDetailSection(state: ComprehensionSectionState(record: record))
            }
            .padding()
        }
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
        .task { await markRead() }
    }

    private var sourceHeader: some View {
        Text(sourceLabel)
            .font(AppFont.caption)
            .foregroundStyle(.grayFont)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Titles rather than the raw stable ids, and a plain statement when the
    /// comic has left the library — its old records stay readable either way.
    private var sourceLabel: String {
        guard let comic = record.comicTitle else {
            return "No longer in your library"
        }
        guard let chapter = record.chapterTitle else { return comic }
        return "\(comic) · \(chapter) · page \(record.pageNumber)"
    }

    /// Best-effort: a failed `PATCH` must not cost the reader the record they
    /// are looking at, so nothing is surfaced and the badge simply still counts
    /// it. Skipped entirely when there is nothing to mark — an unfinished or
    /// failed record was never unread in the first place.
    private func markRead() async {
        guard record.isUnreadExplanation else { return }
        guard let updated = try? await repository.setRead(id: record.id, isRead: true) else {
            return
        }
        onMarkedRead(updated)
    }
}

#Preview("Explained") {
    NavigationStack {
        ComprehensionDetailView(
            record: .preview(
                status: "ok",
                notes: "なかなか + 否定形で「かなり」の意味になる。",
                cloudTranslation: "你小子，挺有一套的嘛"
            )
        )
    }
}

#Preview("Still coming") {
    NavigationStack {
        ComprehensionDetailView(record: .preview(status: "pending"))
    }
}

#Preview("Declined") {
    NavigationStack {
        ComprehensionDetailView(record: .preview(status: "declined"))
    }
}
