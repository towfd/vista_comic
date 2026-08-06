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
//  Ticket 20 makes this the screen the reader *acts* from: retry, delete, and
//  the jump back to the source page all live here. **Retry lives only here** —
//  reaching it costs a deliberate tap into one record, which is precisely what
//  keeps an expensive call hard to trigger by mis-tapping a long list.
//

import SwiftUI

struct ComprehensionDetailView: View {
    let record: ComprehensionRecord
    /// Called whenever this record changes on the backend — marked read, or
    /// re-enqueued by a retry — so the list can update the row and the badge
    /// without re-fetching. Passed in rather than reaching back into the list's
    /// state, per CLAUDE.md's rule about passing actions into views instead of
    /// hard-coding behavior in them.
    var onChanged: (ComprehensionRecord) -> Void = { _ in }
    /// Called once this record is gone from the backend, so the list can drop
    /// the row. This screen dismisses itself; removing the row is the list's.
    var onDeleted: (ComprehensionRecord) -> Void = { _ in }

    @Environment(\.comprehensionRepository) private var repository
    @Environment(\.dismiss) private var dismiss

    /// The record as the backend last returned it, once an action here has
    /// changed it. `nil` until then, so the screen normally renders exactly the
    /// record it was pushed with — a retry is the only thing that rewrites what
    /// is on screen, and it should be visible immediately rather than waiting
    /// for the list to refresh underneath.
    @State private var updated: ComprehensionRecord?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    /// One flag per action rather than a shared message string: the String
    /// Catalog is populated by extracting literals from the call site, so copy
    /// held in a variable never reaches it. Two `.alert`s each stating their own
    /// message keeps both translatable, which is the same reason
    /// `ComprehensionDetailSection` spells its four reasons out separately.
    @State private var showRetryError = false
    @State private var showDeleteError = false

    /// What this screen renders and acts on: the updated record where an action
    /// has produced one, otherwise the one it was pushed with.
    private var current: ComprehensionRecord { updated ?? record }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sourceHeader

                VStack(alignment: .leading, spacing: 4) {
                    Text("Original")
                        .font(AppFont.rowTitle)
                    Text(current.sourceText)
                        .font(AppFont.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Translation")
                            .font(AppFont.rowTitle)
                        TranslationProvenanceChip(isCloud: current.cloudTranslation != nil)
                    }
                    Text(current.displayedTranslation)
                        .font(AppFont.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                ComprehensionDetailSection(state: sectionState, retry: retryAction)
            }
            .padding()
        }
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { actions }
        .task { await markRead() }
        .alert("Delete this record?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .alert(
            "Couldn't ask for this explanation again. Check your connection and try again.",
            isPresented: $showRetryError
        ) {
            Button("OK", role: .cancel) {}
        }
        .alert(
            "Couldn't delete this record. Check your connection and try again.",
            isPresented: $showDeleteError
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Actions

    /// Jump-back and delete sit in the toolbar rather than in the scrolling
    /// body: they act on the whole record, so they should not scroll away from
    /// it — and keeping delete out of the reading flow is half of why a stray
    /// tap can't reach it.
    @ToolbarContentBuilder
    private var actions: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            // M9's peek-mode jump survives unchanged: `targetPage` opens the
            // exact page, `isPeek` keeps the visit from writing progress, so
            // re-reading an old scene never moves where the reader actually is.
            NavigationLink(value: jumpRoute) {
                Image(systemName: "location.circle")
            }
            // Disabled rather than hidden for a comic that has left the
            // library: the record is still readable, and a greyed control says
            // the navigation is gone instead of silently dropping it.
            .disabled(!current.canJumpToSource)
            .accessibilityLabel("Jump to source page")

            if isDeleting {
                ProgressView()
            } else {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete")
            }
        }
    }

    private var sectionState: ComprehensionSectionState {
        ComprehensionSectionState(record: current)
    }

    /// Offered for a `failed` record and withheld for a `declined` one — the
    /// section's own `allowsRetry` rule decides, so this screen and the
    /// reader's result screen can never disagree about what is retryable.
    /// Retrying a decline would spend a request to receive the same verdict.
    private var retryAction: (() -> Void)? {
        guard case .unavailable(let reason) = sectionState, reason.allowsRetry else {
            return nil
        }
        return { Task { await retry() } }
    }

    private var jumpRoute: ReaderRoute {
        ReaderRoute(
            comicID: current.comicID,
            chapterID: current.chapterID,
            targetPage: current.pageNumber,
            isPeek: true
        )
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
        guard let comic = current.comicTitle else {
            return "No longer in your library"
        }
        guard let chapter = current.chapterTitle else { return comic }
        return "\(comic) · \(chapter) · page \(current.pageNumber)"
    }

    /// Best-effort: a failed `PATCH` must not cost the reader the record they
    /// are looking at, so nothing is surfaced and the badge simply still counts
    /// it. Skipped entirely when there is nothing to mark — an unfinished or
    /// failed record was never unread in the first place.
    private func markRead() async {
        guard current.isUnreadExplanation else { return }
        guard let read = try? await repository.setRead(id: current.id, isRead: true) else {
            return
        }
        updated = read
        onChanged(read)
    }

    /// On success the section flips to "being written" straight away, because
    /// the backend returns the re-enqueued record — the reader sees their tap
    /// take effect without a refresh.
    private func retry() async {
        switch await retryComprehensionRecord(id: current.id, using: repository) {
        case .loaded(let requeued):
            updated = requeued
            onChanged(requeued)
        case .failed:
            showRetryError = true
        case .loading:
            break
        }
    }

    /// Dismisses only after the backend confirms, so a failed delete leaves the
    /// reader looking at the record that still exists rather than at a list it
    /// has vanished from.
    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }

        switch await deleteComprehensionRecord(id: current.id, using: repository) {
        case .loaded:
            onDeleted(current)
            dismiss()
        case .failed:
            showDeleteError = true
        case .loading:
            break
        }
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

/// The one state that offers retry.
#Preview("Failed") {
    NavigationStack {
        ComprehensionDetailView(record: .preview(status: "failed"))
    }
}

/// Retrying this would spend a request to receive the same verdict, so the
/// section shows its own copy and no button.
#Preview("Declined") {
    NavigationStack {
        ComprehensionDetailView(record: .preview(status: "declined"))
    }
}

/// The comic has left the library: still readable, but the jump is disabled
/// because that navigation would fail.
#Preview("Comic removed") {
    NavigationStack {
        ComprehensionDetailView(
            record: .preview(status: "ok", notes: "…", comicTitle: nil, chapterTitle: nil)
        )
    }
}
