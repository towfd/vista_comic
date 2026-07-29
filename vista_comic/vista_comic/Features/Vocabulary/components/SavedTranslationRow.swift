//
//  SavedTranslationRow.swift
//  vista_comic
//
//  One row in `VocabularyView`'s saved-translations list (ocr-translation
//  ticket 06): shows the original/translated text pair plus enough source
//  context (comic id, chapter id, page number, saved-at time) to identify
//  where it came from. `SavedTranslation` carries no comic/chapter *title* —
//  resolving one would need an extra repository call, which is out of scope
//  for this ticket — so the raw stable ids stand in for it. Mirrors
//  `ComicListView`'s placement under Features/<Tab>/components and its
//  `AppFont` token usage; extracted since a single row already carries five
//  distinct pieces of information.
//
//  Ticket 07 adds the trailing jump button: a `NavigationLink(value:)` for
//  `ReaderRoute`, not a tap-anywhere-on-the-row link, so a stray tap while
//  reading the text doesn't accidentally leave the tab. `VocabularyView`
//  owns the matching `navigationDestination(for: ReaderRoute.self)`.
//  `targetPage`/`isPeek` make this open the reader read-only, scrolled to
//  the exact saved page, instead of resuming (and overwriting) normal
//  reading progress.
//
//  Ticket 08 adds the trailing delete button, confirmed via `.alert` since
//  deleting is irreversible. Stays a "dumb" reusable row per CLAUDE.md: the
//  actual delete call against `TranslationRepository` happens in
//  `VocabularyView` (`onDelete`), not here — this row only asks for
//  confirmation and reports the decision back up.
//

import SwiftUI

struct SavedTranslationRow: View {
    let translation: SavedTranslation
    /// Called once the user confirms deletion. Awaited so the row can show a
    /// spinner while the parent's `TranslationRepository.delete(id:)` call
    /// is in flight — the row is removed from the list by the parent on
    /// success, so nothing further happens here after `onDelete` returns.
    let onDelete: () async -> Void

    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(translation.originalText)
                    .font(AppFont.rowTitle)

                Text(translation.translatedText)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(.primaryRed)

                Text(sourceText)
                    .font(AppFont.caption)
                    .foregroundStyle(.grayFont)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isDeleting {
                ProgressView()
            } else {
                VStack(spacing: 16) {
                    NavigationLink(value: jumpRoute) {
                        Image(systemName: "location.circle")
                            .font(.title2)
                            .foregroundStyle(.primaryRed)
                    }
                    .accessibilityLabel("Jump to source page")

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash.circle")
                            .font(.title2)
                            .foregroundStyle(.grayFont)
                    }
                    .accessibilityLabel("Delete")
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .alert("Delete this translation?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                isDeleting = true
                Task {
                    await onDelete()
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private var jumpRoute: ReaderRoute {
        ReaderRoute(
            comicID: translation.comicID,
            chapterID: translation.chapterID,
            targetPage: translation.pageNumber,
            isPeek: true
        )
    }

    private var sourceText: String {
        let when = translation.savedAt.formatted(date: .abbreviated, time: .shortened)
        return String(
            localized: "\(translation.comicID) · \(translation.chapterID) · page \(translation.pageNumber) · \(when)"
        )
    }
}

#Preview {
    NavigationStack {
        SavedTranslationRow(translation: .preview()) {}
            .padding()
    }
}
