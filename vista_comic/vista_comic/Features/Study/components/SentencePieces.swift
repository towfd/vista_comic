//
//  SentencePieces.swift
//  vista_comic
//
//  The two rows a rearrangement is played on: the answer being built, and the
//  pool it is built from.
//
//  **A sentence is not a grid.** Both rows were `LazyVGrid`s with an adaptive
//  column, and an adaptive grid gives every column the same width — so a word
//  wider than the column wrapped onto two lines and a short one was given space
//  it did not need. `FlowLayout` gives each word exactly its own width and
//  wraps to the next line when the row is full, which is how a sentence is set.
//
//  **And a piece can be moved with the pieces around it getting out of the
//  way.** SwiftUI's `.draggable` / `.dropDestination` were here before and
//  reordered on drop, showing nothing until then; the reader never found them.
//  What is here instead is a press-and-hold that reorders the row live under
//  the finger, so where a word will land is visible before it lands.
//

import SwiftUI

/// Lays subviews left to right, wrapping to a new line when the next one will
/// not fit — each at its own natural width.
struct FlowLayout: Layout {
    /// Between two pieces on the same line.
    var spacing: CGFloat = 8
    /// Between lines.
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let lines = wrap(subviews, into: width)
        let height = lines.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        for line in wrap(subviews, into: bounds.width) {
            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + line.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private struct Line {
        var y: CGFloat = 0
        var height: CGFloat = 0
        var items: [(index: Int, x: CGFloat, size: CGSize)] = []
    }

    /// The lines, measured once and used by both passes.
    ///
    /// A piece wider than the whole row is given the row rather than allowed to
    /// run off the edge of it — a single Vietnamese word never is, but a
    /// accessibility text size can make one so.
    private func wrap(_ subviews: Subviews, into width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        var x: CGFloat = 0
        var y: CGFloat = 0

        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            size.width = min(size.width, width)

            if x > 0, x + size.width > width {
                line.y = y
                lines.append(line)
                y += line.height + lineSpacing
                line = Line()
                x = 0
            }

            line.items.append((index: index, x: x, size: size))
            line.height = max(line.height, size.height)
            x += size.width + spacing
        }

        if !line.items.isEmpty {
            line.y = y
            lines.append(line)
        }
        return lines
    }
}

/// The answer as it is being assembled.
///
/// Tap a word to take it back to the pool; press and hold to move it, and the
/// row reorders live so the gap the word is about to fill is always visible.
struct PlacedPiecesRow: View {
    let pieces: [SentencePiece]
    /// Take the piece at this position back to the pool.
    let takeBack: (Int) -> Void
    /// Move the piece at the first position to in front of the second — the
    /// argument order `PieceTray.move(from:before:)` takes.
    let move: (Int, Int) -> Void

    /// Which piece is under the finger, and where it has got to. `nil` unless a
    /// press has been held long enough to pick one up.
    @State private var lifted: UUID?
    /// The lifted piece's position **as the row currently stands**, which
    /// changes under the finger every time the row reorders.
    @State private var liftedIndex: Int?
    /// Where each piece is, measured rather than derived: the layout decides
    /// where words wrap, so only the layout knows what the finger is over.
    @State private var frames: [UUID: CGRect] = [:]
    @State private var fingerAt: CGPoint?

    private let space = "placedPieces"

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                view(of: piece, at: index)
            }
        }
        .coordinateSpace(name: space)
        .onPreferenceChange(PieceFrames.self) { frames = $0 }
        // A piece taken back or dropped while the row is animating must not
        // leave a word stuck to a finger that is no longer down.
        .onChange(of: pieces.count) { _, _ in release() }
    }

    private func view(of piece: SentencePiece, at index: Int) -> some View {
        let isLifted = piece.id == lifted

        return ZStack {
            // The measurer, which never moves. Reading the frame off the piece
            // itself would mean measuring something that is offset by the very
            // number computed from the measurement.
            GeometryReader { geometry in
                Color.clear.preference(
                    key: PieceFrames.self,
                    value: [piece.id: geometry.frame(in: .named(space))]
                )
            }

            Text(piece.text)
                .lineLimit(1)
                .chunkyFace(.piece, sunk: false)
                .scaleEffect(isLifted ? 1.06 : 1)
                .shadow(color: .black.opacity(isLifted ? 0.35 : 0), radius: 8, y: 4)
                .offset(lift(of: piece))
        }
        .fixedSize()
        .zIndex(isLifted ? 1 : 0)
        .onTapGesture { takeBack(index) }
        .gesture(pressAndMove(piece, from: index))
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: pieces)
    }

    /// How far the lifted piece is from where the layout has put it.
    ///
    /// Measured from the finger to the piece's **current** slot, so that each
    /// time the row reorders the word settles back under the finger instead of
    /// drifting a slot further away with every move.
    private func lift(of piece: SentencePiece) -> CGSize {
        guard piece.id == lifted, let finger = fingerAt, let box = frames[piece.id] else {
            return .zero
        }
        return CGSize(width: finger.x - box.midX, height: finger.y - box.midY)
    }

    private func pressAndMove(_ piece: SentencePiece, from index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(space)))
            .onChanged { value in
                // `.second` with no drag yet is the moment the hold is
                // recognised — the word lifts there, rather than waiting for
                // the finger to travel far enough to prove it meant it.
                guard case .second(_, let drag) = value else { return }

                if lifted != piece.id {
                    lifted = piece.id
                    liftedIndex = index
                }
                guard let drag else { return }
                fingerAt = drag.location

                guard let from = liftedIndex, let to = target(under: drag.location) else {
                    return
                }
                if to != from {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        move(from, to)
                    }
                    liftedIndex = PieceTray.landing(movingFrom: from, before: to)
                }
            }
            .onEnded { _ in release() }
    }

    /// Where a finger at `point` is asking the piece to go.
    ///
    /// The position of whatever word it is over — dropping onto a word means
    /// "in front of this one", which is `move(from:before:)`'s own contract. Past
    /// the last word on its line it means the end of the sentence, which no
    /// piece covers and which a word being sent to the back has to be able to
    /// reach.
    private func target(under point: CGPoint) -> Int? {
        if let hit = pieces.firstIndex(where: { frames[$0.id]?.contains(point) == true }) {
            return hit
        }
        if let last = pieces.last, let box = frames[last.id],
           point.y >= box.minY, point.x > box.maxX {
            return pieces.count
        }
        return nil
    }

    private func release() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            lifted = nil
            liftedIndex = nil
            fingerAt = nil
        }
    }
}

/// Where every placed piece is, collected from the layout that placed them.
private struct PieceFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, newer in newer }
    }
}

/// The words still to be used. Tapping one puts it on the end of the answer,
/// where it is one press-and-drag from anywhere.
struct PiecePool: View {
    let pieces: [SentencePiece]
    let place: (Int) -> Void

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                Button(piece.text) { place(index) }
                    .buttonStyle(.poolPiece)
                    .lineLimit(1)
            }
        }
    }
}
