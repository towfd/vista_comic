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

                // Familiarity on every row, including `New`. It was hidden at
                // the bottom band while nothing could move a card off it; now
                // that practice does, an absent badge and a card still at the
                // bottom looked identical, which is the one comparison a reader
                // opens this list to make. The rung itself is in the card's own
                // screen — three bands is the right resolution to scan.
                if Familiarity(ladderStage: card.ladderStage).isWorthShowing {
                    Label(
                        Familiarity(ladderStage: card.ladderStage).title,
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                }

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
