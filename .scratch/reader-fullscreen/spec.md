# The reader should reach the edges of the screen

## The request

From the repo owner, 2026-09-01, after the practice work:

> 漫畫全屏那邊上下會有黑黑的部分 那邊可以拿掉嗎 我想webtoon那邊全屏的有把那邊拿掉 變成真的全屏這樣

## What the bands actually are

Not a letterbox, and not the images. Each page is drawn `.aspectRatio(contentMode: .fit)`
at the full container width, so a page has no bars of its own — its height simply follows
its width.

The bands are the **safe area**. `ComicView`'s pages `ScrollView` respects it, so the strip
is laid out between the status-bar inset and the home-indicator inset, and what shows above
and below is the window behind it.

Everything else in this screen was already taken to the edges when the immersive controls
were built: the navigation bar and tab bar are hidden, the status bar follows the controls,
the home indicator dims with them, and both control bars extend their material into the
safe area with `ignoresSafeAreaEdges`. **The content is the one thing that was left inset**,
which is why the screen reads as almost-fullscreen rather than fullscreen.

## Scope

One ticket. The pages fill the screen; the controls keep their insets.

Out of scope: the controls' own layout, the zoom and pan model, selection, auto-advance,
and every other reader behaviour. This is one modifier and the one measurement that depends
on it.

## The measurement that depends on it

`controlBarHeight` is passed to `selectionCancelZoneFrame` as `topObstruction`, so the
"release here to cancel" badge is drawn below the control bar instead of underneath it.
It is measured as the bar's own height, which was the whole obstruction while the scroll
view started below the status bar.

Once the pages reach the top edge, the bar covers the status-bar inset **as well as**
itself, and a badge placed at the old offset lands under the bar — drawn correctly and
impossible to see, which is the exact failure the parameter was added to prevent.

So the ticket has two halves, and the second one is not optional.

## Why this is safe to do to a vertical strip

The reader is one continuous scroll. Nothing is permanently hidden by extending it: the
top of the first page and the bottom of the last are both still scrollable into view, and
the controls that overlay them are summoned by a tap and dismissed by one. This is the
arrangement every webtoon reader uses, and the repo owner is asking for it by name.
