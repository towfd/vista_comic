//
//  LearningRecordView.swift
//  vista_comic
//
//  單字本 tab content. Placeholder for now — a future OCR-to-translation
//  feature will fill this in with saved words/sentences. Mirrors
//  `FavouriteView`'s `ContentUnavailableView` empty-state pattern.
//

import SwiftUI

struct LearningRecordView: View {
    var body: some View {
        ContentUnavailableView(
            "Nothing saved yet",
            systemImage: "text.book.closed",
            description: Text("Words and sentences you save while reading will appear here.")
        )
    }
}

#Preview {
    LearningRecordView()
}
