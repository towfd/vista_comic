//
//  CardSectionHeader.swift
//  vista_comic
//
//  One heading in 單字庫: what kind, how many, and whether it is open.
//
//  The heading became a control in stage 2 ticket 05, and that is the whole
//  reason it stopped being a plain grey caption. A row of small uppercase text
//  is not something anyone tries to tap, so a fold hidden behind one would be a
//  feature the reader never found — the same mistake the rearrangement's
//  hold-to-move gesture made.
//
//  The colour stops at the heading. Two features that existed to be looked at
//  have already been deleted from this app, and 單字庫 is a workshop: the
//  accent is here so the eye lands on the right band in one look, not to make a
//  list of saved words into something to browse.
//

import SwiftUI

struct CardSectionHeader: View {
    let title: LocalizedStringKey
    /// How many cards are under this heading **as displayed** — so the count
    /// follows a search rather than describing a deck the reader cannot see.
    let count: Int
    let isExpanded: Bool
    /// The band's colour. `nil` is the quiet treatment, which the unclassified
    /// section takes: it is work waiting, not a category to be proud of, and it
    /// already sorts last for the same reason.
    let accent: Color?
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                // Rotated rather than swapped for a chevron.down, so the state
                // change is a movement the eye follows to the rows appearing
                // beneath it.
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Text(title)
                    .font(AppFont.rowTitle)

                Spacer()

                Text("\(count)")
                    .font(AppFont.rowTitle)
                    .monospacedDigit()
                    .padding(.vertical, 3)
                    .padding(.horizontal, 9)
                    .background(pillFill, in: Capsule())
            }
            .foregroundStyle(foreground)
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(band, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        // Plain, because a heading is not a submit button: the tinted label a
        // bordered style would give it fights the band behind it.
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isExpanded)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var band: Color { accent ?? Color(.secondarySystemBackground) }

    /// White on an accent, the system's own label colour on the quiet band —
    /// which is what keeps the unclassified heading readable in both
    /// appearances without a second asset colour for it.
    private var foreground: Color { accent == nil ? .primary : .white }

    private var pillFill: Color {
        accent == nil ? Color(.tertiarySystemFill) : .white.opacity(0.22)
    }
}

#Preview {
    VStack(spacing: 12) {
        CardSectionHeader(
            title: "Words", count: 24, isExpanded: false, accent: .practiceTeal
        ) {}
        CardSectionHeader(
            title: "Sentences", count: 8, isExpanded: true, accent: .primaryRed
        ) {}
        CardSectionHeader(
            title: "Unclassified", count: 3, isExpanded: false, accent: nil
        ) {}
    }
    .padding()
}
