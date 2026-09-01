//
//  AppTheme.swift
//  vista_comic
//
//  Minimum shared visual tokens needed by more than one screen (M1).
//  Colors already live in the asset catalog (primaryRed, grayFont);
//  this file only collects the repeated font styles so multiple screens
//  stay visually consistent.
//

import SwiftUI

enum AppFont {
    /// Large screen titles, e.g. the library header and comic title.
    static let title = Font.system(size: 36, weight: .bold)
    /// Primary label inside a list row.
    static let rowTitle = Font.system(size: 14, weight: .bold)
    /// Secondary / caption text inside a list row.
    static let caption = Font.system(size: 12)
    /// Something the reader is meant to sit and read, rather than scan in a
    /// list — a sentence in a practice question, a heading on a card.
    ///
    /// Added because there was nothing between `rowTitle` (14, a list row) and
    /// `title` (36, a screen heading), so a practice prompt had to borrow the
    /// list-row size and came out too small to read comfortably.
    ///
    /// Raised from 22 after a real session: a Vietnamese sentence with a gap in
    /// it is being *read*, at arm's length, and 22 was still a list size.
    static let prompt = Font.system(size: 26, weight: .semibold)
    /// The text on something the reader taps to answer — a choice, a piece of a
    /// rearrangement.
    ///
    /// Deliberately close to `prompt`: an option is read as carefully as the
    /// question, and it was inheriting the system body size (17) while the
    /// question was 22, which made the answers look like small print.
    static let choice = Font.system(size: 20, weight: .semibold)
    /// A single figure meant to be read at a glance — a count on a card.
    static let statistic = Font.system(size: 28, weight: .bold)
}


/// A button with a lip under it, and a face that sinks onto the lip when
/// pressed.
///
/// **Why it looks like this.** The practice screen's controls were
/// `.bordered` and `.borderedProminent`, which on a dark background read as
/// dark grey rectangles — the reader's words were the only thing on screen with
/// any colour, and tapping one gave almost no feedback. The pattern here is the
/// one language apps have converged on (Duolingo's is the best-known): a solid
/// face, a darker edge showing beneath it, and a press that travels the depth
/// of that edge.
///
/// The travel is the point rather than the decoration. It is the only
/// confirmation a tap gets on a screen where the answer does not change until
/// the reader commits.
struct ChunkyButtonStyle: ButtonStyle {
    /// The face.
    let face: Color
    /// The lip beneath it — the same colour darkened, not a shadow, so it holds
    /// its shape against any background.
    let edge: Color
    /// How far the face travels. Small: this is a nudge, not a trapdoor.
    var depth: CGFloat = 4
    /// Whether the button should stretch. Choices do (a column of equal
    /// targets); a piece of a sentence must not (it is as wide as its word).
    var fills = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.choice)
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: fills ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: 14).fill(face))
            .offset(y: configuration.isPressed ? depth : 0)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(edge)
                    .offset(y: depth)
            )
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ChunkyButtonStyle {
    /// What the reader picks from: options, and the pieces of a sentence.
    static var option: ChunkyButtonStyle {
        ChunkyButtonStyle(face: .practiceTeal, edge: .practiceTealDeep)
    }

    /// The same, sized to its own text. For a word in a rearrangement, where a
    /// full-width button would be one word per line.
    static var piece: ChunkyButtonStyle {
        ChunkyButtonStyle(face: .practiceTeal, edge: .practiceTealDeep, fills: false)
    }

    /// The commit: Check, Next, Play. The brand colour, so that "I am choosing"
    /// and "I am done choosing" are never the same colour.
    static var commit: ChunkyButtonStyle {
        ChunkyButtonStyle(face: .primaryRed, edge: .primaryRedDeep)
    }
}
