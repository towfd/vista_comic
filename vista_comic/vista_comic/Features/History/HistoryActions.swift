//
//  HistoryActions.swift
//  vista_comic
//
//  The two things a reader can do *to* a 歷史紀錄 record
//  (`comprehension-response-ux` ticket 20), as free functions over
//  `ComprehensionRepository` mapped onto `LoadState`.
//
//  Kept out of the views for the same reason `deleteSavedTranslation` was
//  (see `VocabularyView`) and `SelectionActions.swift` before it: these are the
//  parts most worth testing, and they must be testable against a stub
//  repository without rendering anything. The views keep only the question of
//  *when* to call them and what to show afterwards.
//

import SwiftUI

/// Re-enqueues a `failed` record, returning the record as it comes back —
/// `pending` again, and therefore being produced.
///
/// Retry is a backend re-enqueue rather than a local status flip, so what the
/// screen shows afterwards is the backend's own answer rather than an
/// optimistic guess that a later refresh could contradict.
func retryComprehensionRecord(
    id: Int,
    using repository: any ComprehensionRepository
) async -> LoadState<ComprehensionRecord> {
    do {
        return .loaded(try await repository.retry(id: id))
    } catch {
        return .failed(error)
    }
}

/// Deletes one record.
///
/// Surfaced as `.failed` rather than swallowed, so the caller can say so and
/// leave the row in place: nothing was deleted, and a list that dropped the row
/// anyway would lie about it. Same non-silent-failure rule 單字本's delete
/// already followed.
func deleteComprehensionRecord(
    id: Int,
    using repository: any ComprehensionRepository
) async -> LoadState<Void> {
    do {
        try await repository.delete(id: id)
        return .loaded(())
    } catch {
        return .failed(error)
    }
}

// MARK: - The deletion's two alerts

extension View {
    /// The confirmation a deletion must pass, and the message when it fails.
    ///
    /// Both 歷史紀錄 screens delete — the list by swipe, the detail by its
    /// toolbar — and this is the one place either of them words it. Deletion is
    /// irreversible with no undo, so the two screens promising subtly different
    /// things about it is the failure worth designing out, not the handful of
    /// lines saved.
    ///
    /// The screens keep what actually differs: which record is being deleted,
    /// and what to do once it is gone.
    func recordDeletionAlerts(
        isConfirming: Binding<Bool>,
        isShowingFailure: Binding<Bool>,
        confirm: @escaping () -> Void
    ) -> some View {
        self
            .alert("Delete this record?", isPresented: isConfirming) {
                Button("Delete", role: .destructive, action: confirm)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
            // The row stays where it is behind this: nothing was deleted, and a
            // list that dropped it anyway would lie about what happened.
            .alert(
                "Couldn't delete this record. Check your connection and try again.",
                isPresented: isShowingFailure
            ) {
                Button("OK", role: .cancel) {}
            }
    }
}
