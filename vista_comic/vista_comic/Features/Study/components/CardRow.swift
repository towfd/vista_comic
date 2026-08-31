//
//  CardRow.swift
//  vista_comic
//
//  One card in 單字庫.
//
//  Three lines at most, and the third is deliberately thin: this is a workshop,
//  so a row exists to be recognised and acted on, not admired. What earns a
//  place is whatever helps the reader decide "is this the one I came to fix" —
//  the words themselves, where they came from, and how often they have needed
//  looking up again.
//

import SwiftUI

struct CardRow: View {
    let card: LearningCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.sourceText)
                .font(AppFont.rowTitle)
                .lineLimit(2)

            Text(card.translation)
                .font(AppFont.caption)
                .foregroundStyle(.grayFont)
                .lineLimit(2)

            HStack(spacing: 8) {
                // Absent when the comic has left the library — the same signal
                // that withdraws the jump, so the row never implies a source it
                // cannot open.
                if let source = card.sourceLabel {
                    Text(source)
                        .lineLimit(1)
                }

                // Where the card is and when it is next up — the two things
                // the scheduler actually knows. This used to be an adjective
                // (New / Learning / Familiar) aliased to the slot number, and a
                // screen full of "New" on cards the reader had practised for
                // days is what provoked the stage 6 rewrite: the word read as a
                // verdict on them while describing a column that had not moved.
                Label(
                    scheduleSummary(
                        of: card, steps: StudySettings.fallback.learningSteps
                    ),
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                .accessibilityIdentifier("cardSchedule")

                // Only ever counted upward, and only on a real re-lookup, so a
                // number here is the reader having forgotten this word that
                // many times.
                if card.lookupCount > 0 {
                    Label("\(card.lookupCount)", systemImage: "arrow.counterclockwise")
                }
            }
            .font(AppFont.caption)
            .foregroundStyle(.grayFont)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    List {
        CardRow(card: .preview())
        CardRow(card: .preview(kind: nil, lookupCount: 3))
        CardRow(card: .preview(comicTitle: nil))
        CardRow(card: .preview(ladderStage: 3))
    }
    .listStyle(.plain)
}
