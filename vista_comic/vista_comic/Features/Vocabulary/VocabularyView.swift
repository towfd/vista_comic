//
//  VocabularyView.swift
//  vista_comic
//
//  單字本 tab content. Placeholder for now — the ocr-translation feature
//  (see .scratch/ocr-translation/issues/06-vocabulary-tab-real-list.md)
//  fills this in with saved translations via TranslationRepository. Named to
//  match that ticket's vocabulary-tab vocabulary, not a separate concept.
//  Mirrors `FavouriteView`'s `ContentUnavailableView` empty-state pattern.
//

import SwiftUI

struct VocabularyView: View {
    var body: some View {
        ContentUnavailableView(
            "Nothing saved yet",
            systemImage: "text.book.closed",
            description: Text("Words and sentences you save while reading will appear here.")
        )
    }
}

#Preview {
    VocabularyView()
}
