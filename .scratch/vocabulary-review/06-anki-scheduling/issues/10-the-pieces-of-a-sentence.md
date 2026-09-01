Status: implemented on branch `feat/practice-ui`, 2026-09-01 — verified on device by the reader

# 10 — The pieces of a sentence

Three things the reader asked for after a real session on the rearrangement question. The
screen is right; what is on it is not laid out the way a sentence is read.

## 1. Move a piece, and see where it will land

Placing the third word by mistake should not cost the fourth and fifth. Dragging is already
wired (`.draggable` + `.dropDestination` on each placed piece, `PieceTray.move`) and the reader
never found it — a `Button` and a drag competing for the same touch is the likely reason it did
not start.

**The interaction the reader asked for, in their words:** tap takes it back to the pool
(unchanged), **press and hold moves it**, and the pieces around it **shift out of the way while
the finger is down**, so where it will land is visible before it lands.

That last clause is what rules `.draggable` out: SwiftUI's drag-and-drop reorders on drop and
shows nothing before it. A press-and-drag gesture over a layout that reorders live gives the
feedback; the payload never has to leave the view.

**What is given up:** dragging a word *out of the pool* into a position. It was part of the same
`.draggable` wiring and it has no live feedback either. Tapping still places on the end, and the
end is now one drag from anywhere — so nothing is unreachable, it is two gestures instead of
one for a case the reader has not asked for.

## 2. A word is one word wide, and one line tall

Both rows are `LazyVGrid(columns: [.adaptive(minimum: 72)])`, and an adaptive grid gives every
column the **same** width. A word wider than the column **wraps onto two lines**, which is what
the reader is looking at; a short word gets a column it does not need. A sentence is not a grid.

Replace it with a flow layout — each piece as wide as its word, wrapped onto the next line when
the row is full, one line of text each, never hyphenated or broken.

Also: **the pool's text may be smaller** (the reader offered), and **the pool must be taller**.
`maxHeight: 180` is about two rows of a twelve-piece sentence, so the reader is scrolling a
strip to find a word that should simply be on screen. The answer keeps `AppFont.choice` — it is
the sentence being built and it is read, not scanned.

## 3. The line after a wrong answer

`answered(_:verdict:)` says "The answer was <sentence>". Drop the preamble and **show the
sentence**, which is the only part being read; and the translation under it is `AppFont.caption`
(12pt) when it is the thing that makes the sentence mean something — give it a readable size.

- [x] A placed piece can be pressed and moved to any position, and the others move out of its way
- [x] A tap still takes a piece back, and a press that does not move still takes it back
- [x] No piece wraps onto two lines, in either row, on either phone size
- [x] The pool shows a twelve-piece sentence without scrolling on a large phone
- [x] A wrong answer shows the sentence with no preamble, and a translation that can be read
- [x] `PieceTray` still judges the same string it did before

Every one of these is a claim about a screen, and the reader has since seen all of them on a
device — the move, the wrapping, the pool, and the line after a wrong answer.

## Verification the user owns

The whole of this ticket is touch and layout. On a device: a long Vietnamese sentence in the
rearrangement mode, on a compact phone and a large one — press a middle word, move it two places
left, watch the others part, drop it. Then get one wrong on purpose and read what comes back.

## What was built

`SentencePieces.swift`: a `FlowLayout` both rows are laid out with, `PlacedPiecesRow` (the
answer, with the press-and-move), and `PiecePool` (the words still to be used).

**The move needed the pieces to have identities.** `PieceTray` stored `[String]` and the row
drew it with `id: \.offset`, so reordering did not move anything on screen — it redrew the same
four positions with the text swapped, which is exactly the animation the reader was asking for
and could not get. `SentencePiece` carries a `UUID`, because the word cannot be the identity (a
sentence repeats words) and the position cannot be either (the position is what a move changes).
`placed` and `available` stay as `[String]` computed properties, so judging and every existing
test read what they always did.

The finger keeps the word by measuring rather than accumulating: the offset is the distance from
the finger to the piece's **current** slot, so each time the row reorders underneath it, the word
settles back under the finger instead of drifting a slot further away with every move.

`ChunkyButtonStyle` grew a `font` and a `padding`, and its face moved into a `chunkyFace`
modifier — a piece being dragged cannot be a `Button` (a button keeps its touches to itself) and
the look could not be pasted a second time. The pool uses that to run one size down.

**Not done, and deliberately:** dragging a word out of the pool straight into a position. It went
with the `.draggable` wiring. Tapping still places on the end, and the end is one press-and-drag
from anywhere.
