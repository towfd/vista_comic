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

import SwiftUI

struct SavedTranslationRow: View {
    let translation: SavedTranslation

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

            NavigationLink(value: jumpRoute) {
                Image(systemName: "location.circle")
                    .font(.title2)
                    .foregroundStyle(.primaryRed)
            }
            .accessibilityLabel("Jump to source page")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
    SavedTranslationRow(translation: .preview())
        .padding()
}
