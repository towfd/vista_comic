# Research: scroll anchoring and pinch-zoom for a lazy, unequal-height vertical image strip

Feature: `reader-zoom`. Written 2026-08-16.

**Scope.** Two recurring defects in the reader: (1) content above the viewport changing
height shoves the reading position; (2) committing a zoom requires the layout-width change,
the row-height recomputation and the scroll-offset assignment to agree, and their ordering
inside a SwiftUI update is not controllable.

**Source discipline.** Every claim below carries the source that owns it. Sources are
Apple's shipped documentation (fetched from the `developer.apple.com/tutorials/data/...`
JSON that backs the docs site), Apple's shipped SDK headers and `.swiftinterface` files on
this machine, Apple WWDC session transcripts, Apple's archived programming guides, and the
actual source of production open-source readers. Anything weaker is labelled
**[weaker source]**. Anything I could not verify is in "What I could not establish".

Local toolchain, because it bounds what is usable: **Xcode 16.1 (16B40), iOS 18.1 SDK**
(`/Applications/Xcode.app/.../iPhoneOS.sdk/SDKSettings.plist`). Every API below is
annotated with its availability.

---

## What this means for this app

**Direct answer: keep the zoom in SwiftUI. The exact scroll-anchoring you are trying to
build cannot be expressed in SwiftUI, and if it keeps mattering, the pages strip — and only
the pages strip — has to become a `UIViewRepresentable`-wrapped `UICollectionView` with a
custom vertical layout. That is the architecture every production iOS webtoon reader ships.**

The reasoning, in the order it should change your behaviour:

**1. Your zoom model is the one Apple documents.** `UIScrollView`'s own contract is
"scale during the gesture, re-render at the end": *"As the user makes a pinch-in or
pinch-out gesture, the scroll view adjusts the offset and the scale of the content. When
the gesture ends, the object managing the content view updates subviews of the content as
necessary."*
([UIScrollView](https://developer.apple.com/documentation/uikit/uiscrollview)). Transient
`scaleEffect` during the pinch plus a layout-width commit on release is exactly that. Do
not throw it away.

**2. Your zoom-commit bug has a documented, mechanical cause.** `ScrollPosition.scrollTo(point:)`
is documented as *"The scroll view will clamp this value to only scroll to the size of its
actual content."*
([scrollTo(point:)](https://developer.apple.com/documentation/swiftui/scrollposition/scrollto(point:))).
On a zoom-in commit you assign an offset that is only reachable **after** the strip has
grown. If the assignment is evaluated against the pre-growth content size, it is silently
clamped down — which is precisely "the ordering is not controllable" presenting as a jump.
This is not a race you can win by reordering statements inside `onEnded`; it needs the
offset expressed in a coordinate system that does not depend on the new content size, or
applied in a later update.

**3. You are also actively switching off the one anchoring mechanism SwiftUI has.**
`ScrollPosition` has two modes, and the docs draw the line explicitly: *"For a point,
SwiftUI won't attempt to keep that exact offset scrolled when the content size changes nor
will it update to a new offset when that changes. For view identity positions, SwiftUI will
attempt to keep the view with the identity specified in the provided binding visible when
events occur that might cause it to be scrolled out of view by the system."*
([ScrollPosition](https://developer.apple.com/documentation/swiftui/scrollposition)).
`ComicView` declares `ScrollPosition(idType: Int.self)` and binds it with
`.scrollPosition($scrollPosition, anchor: .top)` — identity mode, the stabilised one — and
then every zoom commit and every container resize calls `scrollTo(point:)`, which converts
it to point mode, the explicitly un-stabilised one, and leaves it there. There is a
documented way back:
[`isPositionedByUser`](https://developer.apple.com/documentation/swiftui/scrollposition/ispositionedbyuser)
— *"You can write to this property to control whether the scroll view acts as if it has
been positioned by the user. If the position had a non-nil edge / point value, that value
will become nil when setting this property to true."*

**4. Apple's current guidance says the numbers you are reasoning from are not trustworthy.**
WWDC26 session 321, closing best-practice list: *"avoid using the absolute content size or
content offset with lazy stacks, since these are estimated and unstable."*
([Dive into lazy stacks and scrolling with SwiftUI](https://developer.apple.com/videos/play/wwdc2026/321/)).
`readerPassedBottom` is built entirely from `contentOffset`, `contentSize` and
`containerSize`; so is `ReaderScrollMetrics.offset(afterScalingBy:focal:)`. That is a
standing liability independent of zoom, and it is the same class of defect
`.scratch/reader-auto-advance-false-trigger/` already exists for.

**5. Apple's stated remedy for problem (1) is not offset compensation — it is not being
wrong about the height.** Same session, on views that resize after they appear: *"The lazy
stack measures the view's original height, but the height changes after the view appears,
pushing down other content. In cases like this, if you cannot use SwiftUI's layout
primitives, use a custom layout instead."* Your cheapest real fix is upstream of all of
this: **ship page pixel dimensions in the chapter payload.** `docs/api-contract.md` does not
carry width/height today; `reservedPageHeight` therefore guesses (per-page cached ratio →
chapter median → the 1549/900 library default) and gets corrected on decode. If the server
returns each page's real dimensions, `reservedPageHeight` is exact on first layout, the
estimate is never replaced, and the "an image arrived and moved me" defect stops existing
rather than being compensated for. That is one backend field against an unbounded amount of
client-side anchoring machinery.

**6. What SwiftUI genuinely cannot do, and why that is the UIKit trigger.** The operation
you want is "keep content point *P* under viewport point *V* across a layout change". UIKit
expresses it directly (`contentOffsetAdjustment`, `targetContentOffset(forProposedContentOffset:)`,
or just assigning `contentOffset` inside `prepare()`). SwiftUI's nearest expression is
`scrollTo(id:anchor:)`, and its `anchor` is documented as *"it defines the points in the
identified view **and** the scroll view to align"*
([scrollTo(_:anchor:)](https://developer.apple.com/documentation/swiftui/scrollviewproxy/scrollto(_:anchor:)))
— **one** `UnitPoint` for both sides. You cannot say "40% into page 12, at 25% down the
screen". The residual error is bounded by a viewport height. For a reader that is visible.

**Recommended sequence.**

*Now, in SwiftUI, all supported and cheap:*
- Add page dimensions to the chapter API and make `reservedPageHeight` exact (kills problem 1
  for the common case).
- After any `scrollTo(point:)`, set `scrollPosition.isPositionedByUser = true` so the
  binding returns to identity mode and SwiftUI resumes stabilising it.
- Wrap the zoom commit in
  `withTransaction { $0.scrollContentOffsetAdjustmentBehavior = .disabled } { ... }` so
  SwiftUI's own automatic adjustment is not simultaneously fighting your explicit offset
  (iOS 18+; see Q1).
- Consider `.defaultScrollAnchor(.bottom, for: .sizeChanges)` **only** if you measure that
  growth above the viewport dominates growth below; it is a single static `UnitPoint` and
  can only be right for one direction (see Q1).

*If position shoves survive that:* port `pagesScrollView` to a `UIViewRepresentable` around
`UICollectionView` + a custom `UICollectionViewLayout`, keeping `ComicView`'s SwiftUI
chrome, selection overlay and state. Q5 describes the shape. This is what Aidoku ships, and
its layout file is literally named `VerticalContentOffsetPreservingLayout.swift`.

*What not to do:* do not reach for `UIScrollView`'s native `zoomScale` over the strip
expecting sharp pages. Apple documents that zooming scales without redrawing: *"the content
of the zoom view is simply scaled in response to the change in the scroll factor. This
creates in larger or smaller, content, but doesn't cause the content to redraw. As a result
the displayed content is not displayed sharply."*
([Scroll View Programming Guide for iOS, archived](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/UIScrollView_pg/ZoomZoom/ZoomZoom.html)).
Aidoku works around exactly this; see Q2.

---

## Q1. Does SwiftUI offer content-offset preservation when content above the viewport changes size?

**Answer: there is no API that takes an offset delta, and no per-item "keep this pixel
still" primitive. There are four partial mechanisms, none of which is the UIKit equivalent.
SwiftUI does perform internal anchoring, but only for the lazy stack's own estimates of
views it has not loaded.**

### 1a. `ScrollAnchorRole.sizeChanges` — the closest named thing, and it is a single UnitPoint

`.defaultScrollAnchor(_:for:)` (iOS 18.0+) takes a `ScrollAnchorRole`, and one of the three
roles is exactly this problem:

> `sizeChanges` — *"The role that influences how a scroll view should adjust its content
> offset when the scroll view's content or container size changes."*
> — [ScrollAnchorRole.sizeChanges](https://developer.apple.com/documentation/swiftui/scrollanchorrole/sizechanges)

The type overview:

> *"You can associate a `UnitPoint` to a `ScrollView` using the `defaultScrollAnchor(_:)`
> modifier. By default, the system uses this point for different kinds of behaviors
> including: Where the scroll view should initially be scrolled; How the scroll view should
> handle content size or container size changes; How the scroll view should align content
> smaller than its container size. You can further customize this behavior by assigning
> different unit points for these different roles."*
> — [ScrollAnchorRole](https://developer.apple.com/documentation/swiftui/scrollanchorrole)

and the iOS 17 single-argument form:

> *"Use this modifier to specify an anchor to control both which part of the scroll view's
> content should be visible initially and how the scroll view handles content size changes.
> … The user may scroll away from the initial defined scroll position. When the content
> size of the scroll view changes, it may consult the anchor to know how to reposition the
> content."*
> — [defaultScrollAnchor(\_:)](https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:))

Availability: `defaultScrollAnchor(_:)` iOS 17.0+; `defaultScrollAnchor(_:for:)` and
`ScrollAnchorRole` iOS 18.0+. Confirmed against the local SDK
(`SwiftUI.swiftinterface` lines 10919–10942).

**Why it does not solve this app's problem.** The anchor is one static `UnitPoint` for the
whole scroll view. `.top` keeps the absolute offset, so growth above the viewport pushes the
reader down. `.bottom` keeps the distance-to-bottom constant, which *is* exactly right when
all growth is above the viewport (the chat-app case), and exactly wrong for growth below —
and in this reader both happen constantly, because pages resolve in both directions around
the prefetch window. No `UnitPoint` is correct for both. Note also the wording is
permissive — *"it **may** consult the anchor"* — not a guarantee.

### 1b. `Transaction.scrollContentOffsetAdjustmentBehavior` — an off switch, not a delta

This is the least-known relevant API and it is nearly undocumented on the docs site. It
exists in the shipped SDK (`SwiftUI.swiftinterface` lines 9211–9230):

```swift
@available(iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
public struct ScrollContentOffsetAdjustmentBehavior {
  public static var automatic: ScrollContentOffsetAdjustmentBehavior { get }
  public static var disabled: ScrollContentOffsetAdjustmentBehavior { get }
}

@available(iOS 18.0, ...)
extension SwiftUICore.Transaction {
  public var scrollContentOffsetAdjustmentBehavior: ScrollContentOffsetAdjustmentBehavior { get set }
}
```

The documentation is the important part, because it is Apple confirming that SwiftUI *does*
adjust content offset automatically:

> *"A scroll view may automatically adjust its content offset based on the current context.
> The absolute offset may be adjusted to keep content in relatively the same place. For
> example, when scrolled to the bottom, a scroll view may keep the bottom edge scrolled to
> the bottom when the overall size of its content changes. Use this property to disable
> these kinds of adjustments when needed."*
> — [Transaction.scrollContentOffsetAdjustmentBehavior](https://developer.apple.com/documentation/swiftui/transaction/scrollcontentoffsetadjustmentbehavior)

> `disabled` — *"A scroll view will not adjust its content offset."*
> — [ScrollContentOffsetAdjustmentBehavior.disabled](https://developer.apple.com/documentation/swiftui/scrollcontentoffsetadjustmentbehavior/disabled)

So the shape of the API is the inverse of what you want: you can suppress SwiftUI's
adjustment for one transaction, but you cannot supply one. **Relevant to problem (2)**: a
zoom commit is exactly a case where SwiftUI's automatic adjustment and your explicit
`scrollTo` can both act on the same update. `.disabled` is the supported way to make the
explicit one authoritative.

### 1c. `ScrollPosition` identity mode — "keep visible", not "keep still", and event-limited

Verbatim, from the type overview (identical text appears on the modifier):

> *"When configuring a scroll position, SwiftUI will attempt to keep that position stable.
> For an edge, that means keeping a top aligned scroll view scrolled to the top if the
> content size changes. For a point, SwiftUI won't attempt to keep that exact offset
> scrolled when the content size changes nor will it update to a new offset when that
> changes.*
>
> *For view identity positions, SwiftUI will attempt to keep the view with the identity
> specified in the provided binding visible when events occur that might cause it to be
> scrolled out of view by the system. Some examples of these include: The data backing the
> content of a scroll view is re-ordered. The size of the scroll view changes, like when a
> window is resized on macOS or during a rotation on iOS. The scroll view initially lays out
> it content defaulting to the top most view, but the binding has a different view's
> identity."*
> — [ScrollPosition](https://developer.apple.com/documentation/swiftui/scrollposition) /
> [scrollPosition(\_:anchor:)](https://developer.apple.com/documentation/swiftui/view/scrollposition(_:anchor:))

Three things to take from this:

- The guarantee is "**visible**", not "at the same pixel". A 2500pt page kept "visible" can
  still move most of a screen.
- The enumerated events are **re-ordering, scroll-view size change, and initial layout**.
  "A subview above the viewport got taller" is not on the list.
- `scrollTo(point:)` opts out. The app calls it on every zoom commit and every container
  resize.

`isPositionedByUser` is the documented escape hatch back to identity mode:

> *"You can write to this property to control whether the scroll view acts as if it has been
> positioned by the user. If the position had a non-nil edge / point value, that value will
> become nil when setting this property to true."*
> — [isPositionedByUser](https://developer.apple.com/documentation/swiftui/scrollposition/ispositionedbyuser)

### 1d. What SwiftUI actually does internally — and its stated limit

The most valuable primary source on this whole question is WWDC26 session 321, *Dive into
lazy stacks and scrolling with SwiftUI*. Verbatim from the transcript:

> *"Since a LazyVStack doesn't load all of its views, the height of the subviews that are
> off-screen are estimated. This estimated height is based on the average size of views that
> have been placed before, and the estimated number of remaining subviews. **The lazy stack
> is also unaware of changes in off-screen views, since they aren't loaded.**"*

> *"The space above the visible rect isn't precise either. The scroll position, or content
> offset of the scroll view, therefore depends on an estimated position of the visible items."*

> *"During the orientation change, the lazy stack will keep the StepView for step 4, the
> topmost visible view, anchored. … It will update the content offset of the ScrollView with
> the same amount, such that the content offset at the top is zero as well. **The lazy stack
> and the embedding scroll view coordinate the position and content offset. That way, when
> the estimations are updated, the relative position of the visible subviews in the scroll
> view doesn't change.**"*

> *"avoid using the absolute content size or content offset with lazy stacks, since these
> are estimated and unstable."*
>
> — [WWDC26 session 321](https://developer.apple.com/videos/play/wwdc2026/321/)

So: **SwiftUI does implement scroll anchoring, keyed on the topmost visible subview, and it
covers corrections to `LazyVStack`'s own estimates of unloaded views.** It explicitly does
not cover a *loaded* view changing height after it is placed — which is this app's case,
because the row is on screen or just above it when its image decodes. The same session says
so directly, in the context of `onGeometryChange`-driven resizing:

> *"Programmatic scrolling also becomes less smooth, if too many views change their layout
> after they appear on screen. A common pattern that does this, is using onGeometryChange,
> to set a state value that is then used in another layout pass. … The lazy stack measures
> the view's original height, but the height changes after the view appears, pushing down
> other content. In cases like this, if you cannot use SwiftUI's layout primitives, use a
> custom layout instead."*

**Version caveat, stated honestly.** The session is descriptive ("Discover the inner
workings"), not a "what's new", so this anchoring behaviour is most likely long-standing
rather than new in iOS 26/27. I could not find a documentation page that states it, so I
cannot pin the earliest OS version it applies to. Treat the behaviour as real but
version-unpinned. **[weaker on versioning; the behaviour claim itself is a first-party WWDC statement]**

### 1e. Things checked and ruled out

- `scrollTargetLayout(isEnabled:)` — declares which layout contains scroll targets. WWDC23
  10159: *"When using lazy stacks, it's important to use the scroll target layout modifier.
  Views outside the visible region have not yet been created. The layout knows about which
  views it will create, though, so it can make sure the ScrollView scrolls to the right
  place."* ([WWDC23 10159](https://developer.apple.com/videos/play/wwdc2023/10159/)). It
  enables identity-based scrolling; it does not preserve offset.
- `onScrollGeometryChange(for:of:action:)` — read-only observation. *"The geometry of a
  scroll view changes frequently while scrolling. You should avoid updating large parts of
  your app whenever the scroll geometry changes."*
  ([docs](https://developer.apple.com/documentation/swiftui/view/onscrollgeometrychange(for:of:action:))).
  No write path.
- `ScrollGeometry` — a value type of `contentOffset` / `contentSize` / `contentInsets` /
  `containerSize`. Read-only.
  ([docs](https://developer.apple.com/documentation/swiftui/scrollgeometry))
- `List` anchoring — I found no `List`-specific anchoring API. The full
  [Scroll views API collection](https://developer.apple.com/documentation/swiftui/scroll-views)
  under "Managing scroll position" lists exactly: `scrollPosition(_:anchor:)`,
  `scrollPosition(id:anchor:)`, `defaultScrollAnchor(_:)`, `defaultScrollAnchor(_:for:)`,
  `ScrollAnchorRole`, `ScrollPosition`. That is the complete public surface, and none of it
  takes a delta.

### 1f. The structural gap, stated precisely

UIKit can express "keep content point *P* under viewport point *V*". SwiftUI cannot, because
its only item-relative primitive uses one `UnitPoint` for both sides of the alignment:

> *"If `anchor` is non-nil, it defines the points in the identified view and the scroll view
> to align. For example, setting `anchor` to top aligns the top of the identified view to
> the top of the scroll view."*
> — [ScrollViewProxy.scrollTo(\_:anchor:)](https://developer.apple.com/documentation/swiftui/scrollviewproxy/scrollto(_:anchor:))

`ScrollPosition.scrollTo(id:anchor:)` has the same signature shape
([docs](https://developer.apple.com/documentation/swiftui/scrollposition/scrollto(id:anchor:))).
With a shared unit point you can align fraction *f* of a page to fraction *f* of the
viewport; you cannot align fraction *f* of a page to fraction *g* of the viewport. Residual
error is bounded by one viewport height, not by zero.

---

## Q2. Can `UIScrollView`'s native zoom coexist with a lazily recycled long list?

**Answer: not by handing the collection view to `viewForZooming`. But there is a real,
shipping, production pattern that gets native zoom gestures and native zoom-anchoring on top
of a recycled list — a decoy zoom view. Apple neither documents nor forbids it.**

### 2a. What Apple documents about zooming

The delegate contract:

> *"A scroll view also handles zooming and panning of content. As the user makes a pinch-in
> or pinch-out gesture, the scroll view adjusts the offset and the scale of the content. When
> the gesture ends, the object managing the content view updates subviews of the content as
> necessary. … For zooming and panning to work, the delegate must implement both
> `viewForZooming(in:)` and `scrollViewDidEndZooming(_:with:atScale:)`. In addition, the
> `maximumZoomScale` and `minimumZoomScale` zoom scales must be different."*
> — [UIScrollView](https://developer.apple.com/documentation/uikit/uiscrollview)

> *"Asks the delegate for the view to scale when zooming is about to occur in the scroll
> view. … Return `nil` if you don't want zooming to occur."*
> — [viewForZooming(in:)](https://developer.apple.com/documentation/uikit/uiscrollviewdelegate/viewforzooming(in:))

And the disqualifying property, from the archived guide:

> *"When the content of a scroll view is zoomed, the content of the zoom view is simply
> scaled in response to the change in the scroll factor. This creates in larger or smaller,
> content, but doesn't cause the content to redraw. As a result the displayed content is not
> displayed sharply."*
> — [Scroll View Programming Guide for iOS — Basic Zooming Using the Pinch Gestures](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/UIScrollView_pg/ZoomZoom/ZoomZoom.html)

Apple's two documented answers to that: `CATiledLayer`, or pre-rendered tiles as in the
[PhotoScroller sample](https://developer.apple.com/library/archive/samplecode/PhotoScroller/Introduction/Intro.html)
(*"demonstrates the use of embedded UIScrollViews and CATiledLayer … CATiledLayer is used to
increase the performance of paging, panning, and zooming with high-resolution images"*).
Neither is a recycled list.

Note that Apple's whole content model for scroll views assumes the *content owner* does the
recycling, not the scroll view:

> *"The object that manages the drawing of content that displays in a scroll view needs to
> tile the content's subviews so that no view exceeds the size of the screen. As users
> scroll in the scroll view, this object adds and removes subviews as necessary."*
> — [UIScrollView](https://developer.apple.com/documentation/uikit/uiscrollview)

### 2b. Is zooming a `UICollectionView` documented or endorsed?

**No, in both directions.** I found no Apple documentation, sample code or WWDC session that
either describes or prohibits it. `UICollectionView`'s class overview
([docs](https://developer.apple.com/documentation/uikit/uicollectionview)) never mentions
zoom. Nor does `UICollectionViewLayout`. Searching Apple's own developer forums surfaced
only per-cell zoom (a `UIScrollView` inside each cell) and layout-invalidation questions, no
official guidance **[weaker source: forum threads, not Apple statements]**.

The mechanical reason the naive version fails: `UIScrollView` zoom applies a
`CGAffineTransform` to the view returned by `viewForZooming`. Applying that to a
`UICollectionView` leaves the collection view's own `bounds` unchanged, so cell realisation
is still computed against the unscaled bounds — the visible-rect calculation and the
on-screen rect stop agreeing — and the cell contents are scaled without redrawing, per the
archived guide above. What Apple *does* document as the supported way to change a collection
view's layout under a continuous gesture is the interactive layout transition:

> *"To create an interactive transition — one that is driven by a gesture recognizer or touch
> events — use the `startInteractiveTransition(to:completion:)` method to change the layout
> object. That method installs an intermediate layout object, which works with your gesture
> recognizer or event-handling code to track the transition progress."*
> — [UICollectionView](https://developer.apple.com/documentation/uikit/uicollectionview)

That is the documented "pinch drives a layout change" mechanism, but it transitions between
two discrete layout objects, not a continuous scale.

### 2c. The pattern that actually works in production: the decoy zoom view

Aidoku (open-source iOS manga reader) does get native `UIScrollView` zoom over a recycled
collection view, and it is worth understanding because it is the closest UIKit analogue of
what `ComicView` is attempting.

Source: [`iOS/UI/Common/Zooming/ZoomableCollectionView.swift`](https://github.com/Aidoku/Aidoku/blob/main/iOS/UI/Common/Zooming/ZoomableCollectionView.swift)

- The collection view is **not** scrollable by the user. A transparent, empty `UIScrollView`
  is overlaid on top of it (`ASOverlayLayoutSpec(child: collectionNode, overlay: scrollNode)`)
  and owns every gesture.
- `viewForZooming(in:)` returns `dummyZoomView` — a content-free `UIView` sized to
  `layout.collectionViewContentSize`. There is nothing to scale badly, so the "doesn't
  redraw, looks blurry" problem never arises.
- `scrollViewDidScroll` forwards the offset: `collectionNode.contentOffset = scrollView.contentOffset`.
- `scrollViewDidZoom` converts the zoom into a **layout change**, every frame:

  ```swift
  func scrollViewDidZoom(_ scrollView: UIScrollView) {
      guard let layout = layout as? ZoomableLayoutProtocol,
            layout.getScale() != scrollView.zoomScale else { return }
      layout.setScale(scrollView.zoomScale)
      self.layout.invalidateLayout()
      onZoomScaleChanged?(scrollView.zoomScale)
  }
  ```
- `scrollNode.view.bouncesZoom = false`, with the comment *"bounce not supported since it
  doesn't call scrollViewDidZoom"*.

What this buys, and why it is architecturally interesting for this app: **the scroll view
that owns the offset is decoupled from the view that owns the content.** `UIScrollView`
computes the pinch-centroid anchoring for free (its native zoom already does that), and the
new offset and the new layout are applied in the same run-loop turn by construction. There
is no ordering problem to solve because there is no ordering. That is precisely the property
SwiftUI does not give you.

Verdict for Q2: **zooming a recycled list is not a documented Apple pattern, and handing the
collection view itself to `viewForZooming` is wrong. Using a decoy zoom view to harvest
`UIScrollView`'s gesture and anchoring maths, and converting `zoomScale` into a layout
scale, is a real production pattern with a public implementation.**

---

## Q3. What architecture do production continuous-vertical readers use for pinch-zoom?

Three distinct answers, and the split is informative: **the zoom is always done by something
that is not the recycler.**

### 3a. Aidoku (iOS, Swift) — layout-level scale, offset owned by an overlay scroll view

Already covered in Q2 for the gesture side. The layout side is
[`VerticalContentOffsetPreservingLayout.swift`](https://github.com/Aidoku/Aidoku/blob/main/iOS/UI/Reader/Readers/Webtoon/VerticalContentOffsetPreservingLayout.swift),
a `UICollectionViewFlowLayout` subclass that computes every attribute itself in `prepare()`.
Two mechanisms matter here:

**Zoom without re-measuring content.** Row heights are computed once at unscaled width; the
scale is then applied as a per-attribute transform plus a recomputed centre, and the content
size is scaled:

```swift
let size = CGSize(width: width, height: origin)
let transform = CGAffineTransform(scaleX: scale, y: scale)
contentSize = size.applying(transform)
// ...
currentAttributes[indexPath]?.transform = transform
currentAttributes[indexPath]?.center = CGPoint(x: frame.origin.x + frame.width / 2,
                                               y: frame.origin.y + frame.height / 2)
```

The document is never re-laid-out at the new width. Note this is a *rendering* transform per
cell, not a re-fit — the opposite of this app's "zoom is a change of layout width" decision.
The trade-off is explicit in Aidoku's source comment: *"setting frame without transform
doesn't scale content, and setting frame with transform messes up the scale."*

**Offset preservation, hand-rolled, exactly the UIKit idiom.** When a previous chapter is
prepended:

```swift
if isInsertingCellsAbove {
    if let oldContentSize = contentSizeBeforeInsertingAbove {
        UIView.performWithoutAnimation {
            let newContentSize = collectionViewContentSize
            let contentOffsetY = collectionView.contentOffset.y + (newContentSize.height - oldContentSize.height)
            collectionView.contentOffset = CGPoint(x: ..., y: contentOffsetY)
        }
    }
}
```

and the call site wraps the whole thing in a `CATransaction` with actions disabled
([`ReaderWebtoonViewController.swift`](https://github.com/Aidoku/Aidoku/blob/main/iOS/UI/Reader/Readers/Webtoon/ReaderWebtoonViewController.swift)):

```swift
layout?.isInsertingCellsAbove = true
CATransaction.begin()
CATransaction.setDisableActions(true)
CATransaction.setAnimationDuration(0)
await collectionNode.performBatch(animated: false) { collectionNode.insertSections(IndexSet(integer: 0)) }
self.scrollView.contentOffset = self.collectionNode.contentOffset
self.zoomView.adjustContentSize()
CATransaction.commit()
```

That `CATransaction` block is the UIKit equivalent of the ordering guarantee SwiftUI does
not give you: content mutation, content-size recomputation and offset assignment all commit
as one, with animations off.

### 3b. Mihon / Tachiyomi (Android) — scale the RecyclerView itself, never re-lay-out

[`WebtoonRecyclerView.kt`](https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/tachiyomi/ui/reader/viewer/webtoon/WebtoonRecyclerView.kt).
The zoom is a **View transform on the RecyclerView**:

```kotlin
private fun setScaleRate(rate: Float) {
    scaleX = rate
    scaleY = rate
}

fun onScale(scaleFactor: Float) {
    currentScale *= scaleFactor
    currentScale = currentScale.coerceIn(minRate, MAX_SCALE_RATE)
    setScaleRate(currentScale)
    layoutParams.height = if (currentScale < 1) (originalHeight / currentScale).toInt() else originalHeight
    // ...
    requestLayout()
}
```

Panning while zoomed is `x`/`y` translation of the RecyclerView (`zoomScrollBy`), clamped by
`getPositionX`/`getPositionY`. Bounds: `MIN_RATE = 0.5f`, `DEFAULT_RATE = 1f`,
`MAX_SCALE_RATE = 3f`. The list's own layout and recycling are completely untouched by zoom;
only when scale drops below 1 does it grow the RecyclerView's laid-out height so the visible
area stays covered.

### 3c. Kotatsu (Android) — same idea, extracted into a wrapper

[`WebtoonScalingFrame.kt`](https://github.com/KotatsuApp/Kotatsu/blob/devel/app/src/main/kotlin/org/koitharu/kotatsu/reader/ui/pager/webtoon/WebtoonScalingFrame.kt)
is a `FrameLayout` that owns the `ScaleGestureDetector` and applies `scaleX`/`scaleY` plus
`translationX`/`translationY` to its single child, which is the `WebtoonRecyclerView`. Same
"height / scale" trick when zoomed out, same `MAX_SCALE = 2.5f` / `MIN_SCALE = 0.5f` clamp,
plus fling and double-tap handling on the transform rather than on the list. Note what
happens at gesture end — `onPostScale` posts `updateChildrenScroll()` and only optionally
`requestLayout()`. The list is reconciled *after* the gesture, never during.

### 3d. Apple's PDFKit — real re-layout, anchored by document coordinate

`PDFView` in continuous scroll mode is the closest first-party analogue: default
`displayMode` is `kPDFDisplaySinglePageContinuous`, and zoom is a genuine scale factor that
re-lays out the inner views. From the shipped header
(`iPhoneOS.sdk/System/Library/Frameworks/PDFKit.framework/Headers/PDFView.h`):

```objc
// See PDFDisplayMode constants above. Default is kPDFDisplaySinglePageContinuous.
@property (nonatomic) PDFDisplayMode displayMode;

// Method to get / set the current scaling on the displayed PDF document. Default is 1.0 (actual size).
@property (nonatomic) CGFloat scaleFactor;
@property (nonatomic) CGFloat minScaleFactor;
@property (nonatomic) CGFloat maxScaleFactor;

// Returns the innermost view used by PDFView. This is the view representing the displayed document pages.
@property (nonatomic, readonly, nullable) PDFKitPlatformView *documentView;

// Tells PDFView to calculate (layout) the inner views.
- (void)layoutDocumentView;
```

**The architecturally important part is how PDFKit names a position.** It does not carry a
content offset. It carries a `PDFDestination`:

> *"Returns a PDFDestination representing the current page and point displayed"*
> — `PDFView.currentDestination`
> ([docs](https://developer.apple.com/documentation/pdfkit/pdfview/currentdestination))

and `PDFDestination` is, from `PDFDestination.h`:

```objc
- (instancetype)initWithPage:(PDFPage *)page atPoint:(PDFPoint)point NS_DESIGNATED_INITIALIZER;
@property (nonatomic, weak, readonly) PDFPage *page;   // "The page that the destination refers to"
@property (nonatomic, readonly) PDFPoint point;        // "The destination point on the page above (in page space)"
@property (nonatomic) CGFloat zoom;
```

**page + point in page space.** That coordinate is invariant under zoom and under re-layout,
which is exactly why PDFKit can re-lay-out the whole document on a scale change without
losing the reader. This is the single most transferable idea in this document: *do not carry
a pixel offset across a layout change; carry (item, fraction into item).*

### 3e. Summary table

| Reader | Who does the zoom | Is the list re-laid-out? | Position carried as |
|---|---|---|---|
| Aidoku (iOS) | Overlay `UIScrollView` + decoy zoom view; layout applies per-cell transform | Layout invalidated, content **not** re-measured | Content offset, mirrored between two scroll views inside one `CATransaction` |
| Mihon (Android) | `scaleX`/`scaleY` on the `RecyclerView` | No | RecyclerView's own scroll state, untouched by zoom |
| Kotatsu (Android) | `scaleX`/`scaleY`+translation on the child from a wrapper `FrameLayout` | No (reconciled after gesture) | Same |
| PDFKit (Apple) | `scaleFactor` → `layoutDocumentView` | **Yes**, genuinely | `PDFDestination`: page + point in page space |
| **vista_comic today** | SwiftUI `scaleEffect` during; layout width on commit | **Yes**, genuinely | Content offset via `scrollTo(point:)` |

The app is in PDFKit's column for layout and in nobody's column for position. That mismatch
is the defect.

---

## Q4. Is there an established solution to "estimate now, correct later, without moving the user"?

**Answer: yes in UIKit, and it is well documented. It works by the framework owning the
content offset outright. SwiftUI has no comparable app-facing machinery — its equivalent
covers only its own internal estimates.**

### 4a. `UITableView`: the framework takes the offset away from you

> *"Providing a nonnegative estimate of the height of rows can improve the performance of
> loading the table view. … Estimation allows you to defer some of the cost of geometry
> calculation from load time to scrolling time. The default value is `automaticDimension`,
> which means that the table view selects an estimated height to use on your behalf. Setting
> the value to `0` disables estimated heights… **When using height estimates, the table view
> actively manages the `contentOffset` and `contentSize` properties inherited from its scroll
> view. Don't attempt to read or modify those properties directly.**"*
> — [UITableView.estimatedRowHeight](https://developer.apple.com/documentation/uikit/uitableview/estimatedrowheight)

That last sentence is the whole answer to "what does it do about content offset when an
estimate is replaced by a real measurement": **the table view owns the offset and rewrites it
as estimates resolve**, and it tells you not to touch it. Note the direct read-across:
`ComicView` reads `contentOffset` and `contentSize` on every geometry change and writes
offsets back — the exact pattern UIKit forbids under estimation, and the exact pattern
WWDC26 321 warns against for lazy stacks.

### 4b. `UICollectionView`: the same machinery, but you must wire the offset yourself

The estimation entry points:

> *"Providing an estimated cell size can improve the performance of the collection view when
> the cells adjust their size dynamically. … **Cells that aren't onscreen are assumed to be
> the estimated height.** Setting it to any other value, like `automaticSize`, causes the
> collection view to query each cell for its actual size using the cell's
> `preferredLayoutAttributesFitting(_:)` method."*
> — [UICollectionViewFlowLayout.estimatedItemSize](https://developer.apple.com/documentation/uikit/uicollectionviewflowlayout/estimateditemsize)

> `NSCollectionLayoutDimension.estimated(_:)` — *"The final size of the dimension is
> determined when the content is rendered."*
> — [docs](https://developer.apple.com/documentation/uikit/nscollectionlayoutdimension/estimated(_:))

The correction pipeline, in order, when an estimate is replaced by a measurement:

1. > *"Gives the cell a chance to modify the attributes provided by the layout object. The
   > default implementation of this method adjusts the size values to accommodate changes made
   > by a self-sizing cell."*
   > — [preferredLayoutAttributesFitting(\_:)](https://developer.apple.com/documentation/uikit/uicollectionreusableview/preferredlayoutattributesfitting(_:))
2. > *"When a collection view includes self-sizing cells, the cells are given the opportunity
   > to modify their own layout attributes before those attributes are applied. … When the cell
   > provides a different set of attributes, the collection view calls this method to determine
   > if the cell's change requires a larger layout refresh. … The default implementation of this
   > method returns `false`."*
   > — [shouldInvalidateLayout(forPreferredLayoutAttributes:withOriginalAttributes:)](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/shouldinvalidatelayout(forpreferredlayoutattributes:withoriginalattributes:))
3. > *"Retrieves a context object that identifies the portions of the layout that should
   > change in response to dynamic cell changes. … Subclasses can override this method and use
   > it to perform additional configuration of the invalidation context before returning it."*
   > — [invalidationContext(forPreferredLayoutAttributes:withOriginalAttributes:)](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/invalidationcontext(forpreferredlayoutattributes:withoriginalattributes:))
4. The compensation itself:
   > *"The delta value to be applied to the collection view's content offset. … Changing the
   > value causes the collection view to add the specified x and y values to its `contentOffset`
   > property. Thus, positive values increase the content offset and negative values decrease
   > it."*
   > — [UICollectionViewLayoutInvalidationContext.contentOffsetAdjustment](https://developer.apple.com/documentation/uikit/uicollectionviewlayoutinvalidationcontext/contentoffsetadjustment)

Plus, for layout swaps and batch updates:

> *"During layout updates, or when transitioning between layouts, the collection view calls
> this method to give you the opportunity to change the proposed content offset to use at the
> end of the animation. … The collection view calls this method after calling the `prepare()`
> and `collectionViewContentSize` methods."*
> — [targetContentOffset(forProposedContentOffset:)](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/targetcontentoffset(forproposedcontentoffset:))

Step 3 is the ordering guarantee this app is missing: the layout is told *this row grew by
Δ*, and it hands back both the invalidation and the offset delta **in the same object**, so
they cannot be applied out of order. Note also step 2's default: `false`. Flow layout does
not automatically compensate for a growth above the viewport; that is why
`VerticalContentOffsetPreservingLayout` exists and why the "jumping collection view" is a
well-known problem class.

### 4c. Does SwiftUI have anything comparable?

**For its own estimates, yes — and it is documented only in a WWDC transcript.** From
[WWDC26 321](https://developer.apple.com/videos/play/wwdc2026/321/): *"The lazy stack and the
embedding scroll view coordinate the position and content offset. That way, when the
estimations are updated, the relative position of the visible subviews in the scroll view
doesn't change."*

**For your estimates, no.** There is no per-item hook, no `preferredLayoutAttributesFitting`
equivalent, and no way to hand SwiftUI a delta. Apple's stated remedy is to remove the
resize instead of compensating for it: *"if you cannot use SwiftUI's layout primitives, use a
custom layout instead."* A custom `Layout` places subviews at sizes you compute, so the
height never changes after placement — but a custom `Layout` is not lazy, so a 180-page
chapter would evaluate every `ReaderPage` body. That trade is worth prototyping if you go
that route; I have not measured it.

**The cheapest version of "remove the resize" for this app does not need any of that.**
`reservedPageHeight` already returns the exact height whenever the page's ratio is known
(`recordedHeightRatio`), and the comment on it is right that *"a page seen once reserves its
exact height forever after"*. The only wrong estimates are for pages never decoded on this
device. Serving page dimensions from the backend closes that hole completely and turns the
correction path into dead code.

---

## Q5. If the honest conclusion is "move to UIKit", what would that look like here?

The honest conclusion is **partly**: SwiftUI cannot express exact anchoring across a layout
change (Q1f), and cannot be given an offset delta (Q1b, Q4c). If the residual imprecision of
identity anchoring is acceptable, stay. If it is not, here is the shape.

**Boundary.** One `UIViewRepresentable` replacing `pagesScrollView(urls:)` only. `ComicView`
keeps: chapter loading, `showControls`, the controls overlay, the selection sheet,
`croppedSelection`, progress saving, prefetch window, `chapterHeightRatio`. The
representable's `Coordinator` publishes the same signals the SwiftUI version does today
(visible page set, scroll phase, committed scale) so `ReaderZoom`, `ReaderBottomEdgeGate`,
`reservedPageHeight` and `medianHeightRatio` survive unchanged and stay unit-testable.

**Components.**

1. **`UICollectionView`, vertical, one section, one item per page.** Cells hold an image view
   and reuse; `prefetchDataSource` replaces the hand-rolled prefetch window if you want it,
   or keep yours.

2. **A custom `UICollectionViewLayout`, not flow layout.** It owns an array of heights, one
   per page, sourced from the same `reservedPageHeight` logic (recorded ratio → chapter median
   → default), computes `collectionViewContentSize` and `layoutAttributesForItem(at:)` from
   the running prefix sum, and caches attributes. Aidoku's `prepare()` is a working reference.
   Because the layout owns every height, the content coordinate system is fully known —
   which is the property `LazyVStack` structurally cannot give you.

3. **Height corrections go through `contentOffsetAdjustment`.** When a decode reports a real
   ratio different from the reserved one, update the height array, and if the changed row is
   above the visible rect, return an invalidation context whose
   [`contentOffsetAdjustment`](https://developer.apple.com/documentation/uikit/uicollectionviewlayoutinvalidationcontext/contentoffsetadjustment)
   is `(0, Δheight)`. Problem (1) becomes a two-line answer. This is the mechanism that has
   no SwiftUI counterpart, and it is the whole reason for the port.

4. **Zoom as a scale on the layout, driven by an overlay scroll view** (Aidoku's pattern,
   Q2c) *or* by a `UIPinchGestureRecognizer` writing a scale into the layout and calling
   `invalidateLayout()`. Two sub-choices:
   - *Aidoku-style per-attribute transform* — cheap, no re-measure, but the pages are scaled
     bitmaps during and after zoom, so you lose the "crisp on release" property the spec
     explicitly wants (user story 7).
   - *Re-layout at the new width* — preserves crispness because cells re-fit at the new size,
     matches your current `containerWidth × scale` model and keeps
     `reservedPageHeight(width:...)` correct as-is, at the cost of a full attribute recompute
     per commit (an O(pages) prefix sum over ≤180 entries — negligible).
     Given the spec, take the second.

5. **Anchoring on commit uses `targetContentOffset(forProposedContentOffset:)`** or a direct
   `contentOffset` assignment inside `prepare()`, both inside a `CATransaction` with
   `setDisableActions(true)` (Aidoku's `prependPreviousChapter` is the template). Because the
   layout computes the new content size before the offset is applied,
   the clamping failure documented on `scrollTo(point:)` cannot occur. Problem (2) becomes
   structurally impossible rather than carefully timed.

6. **Carry the anchor as (page index, fraction into page, x fraction)**, PDFKit's
   `PDFDestination` idea (Q3d), not as a pixel offset. At a uniform scale it is invariant, so
   the correction is `offset = prefixSum(index) + fraction * height(index) - focalY`, all in
   the layout's own coordinates, computed from data the layout owns rather than from
   `ScrollGeometry`.

**What you lose.** `.scrollPosition`, `.onScrollGeometryChange`, `.onScrollPhaseChange`,
`.scrollTargetLayout`, per-row `onAppear`/`onDisappear` and SwiftUI previews of the strip.
The spec already anticipated this and rejected the port for that reason — that judgement was
reasonable, and it remains reasonable until the anchoring defects prove unfixable by the four
cheap steps in "What this means for this app". `UIScrollViewDelegate` gives back
`scrollViewDidScroll`, `scrollViewWillBeginDragging`, `scrollViewDidEndDecelerating` and
`willDisplay`/`didEndDisplaying`, which cover every current use, so this is a translation
cost rather than a capability loss.

**Effort ordering, if it comes to it.** Port the strip behind the same public surface
`ComicView` uses today (a view taking `urls`, `isSelecting`, callbacks) so the change is
contained and reversible, and so `ReaderZoomTests` / `ReservedPageHeightTests` /
`ReaderAutoAdvanceGateTests` keep passing untouched.

---

## What I could not establish

- **Whether `.defaultScrollAnchor(_:for: .sizeChanges)` has any observable effect on a
  `LazyVStack` of unequal-height rows on iOS 18.** The documentation says it "may" be
  consulted; there is no sample and no WWDC coverage. This is worth ten minutes on a device
  before anything larger is decided. Suggested test: a `ScrollView` + `LazyVStack` of 60 rows
  with fixed heights, a timer that doubles row 5's height after 3 seconds, scrolled to row
  30; compare `.defaultScrollAnchor(.top, for: .sizeChanges)` against `.bottom` and against
  no modifier, and note whether the visible row changes. Per `CLAUDE.md` this is your
  verification to run, not mine.
- **Whether `Transaction.scrollContentOffsetAdjustmentBehavior = .disabled` actually makes an
  explicit `scrollTo(point:)` authoritative on a zoom commit.** The API's documentation
  describes the intent; I have no source showing this specific interaction.
- **The earliest OS version at which the WWDC26-described lazy-stack/scroll-view anchoring
  coordination applies.** The session is descriptive, not a "what's new", so it is probably
  not new — but "probably" is the honest word.
- **Any Apple statement, in either direction, on zooming a `UICollectionView`.** I searched
  the UICollectionView, UICollectionViewLayout and UIScrollView documentation trees, Apple
  sample code, and Apple's developer forums. There is no endorsement and no prohibition.
- **Whether a non-lazy custom `Layout` over 180 pages is viable in this app.** Apple
  recommends the approach (WWDC26 321); I did not measure it and the laziness loss is real.
- **Panels.** Named in the brief; I could not find a public iOS manga/webtoon reader by that
  name whose source I could verify, so it is not represented in Q3. The iOS "Panels"
  package I did find is a sliding-panel UI component, unrelated.

---

## Source index

Apple documentation
- [ScrollPosition](https://developer.apple.com/documentation/swiftui/scrollposition) ·
  [scrollTo(point:)](https://developer.apple.com/documentation/swiftui/scrollposition/scrollto(point:)) ·
  [scrollTo(id:anchor:)](https://developer.apple.com/documentation/swiftui/scrollposition/scrollto(id:anchor:)) ·
  [isPositionedByUser](https://developer.apple.com/documentation/swiftui/scrollposition/ispositionedbyuser)
- [scrollPosition(\_:anchor:)](https://developer.apple.com/documentation/swiftui/view/scrollposition(_:anchor:)) ·
  [scrollPosition(id:anchor:)](https://developer.apple.com/documentation/swiftui/view/scrollposition(id:anchor:))
- [defaultScrollAnchor(\_:)](https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:)) ·
  [defaultScrollAnchor(\_:for:)](https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:for:)) ·
  [ScrollAnchorRole](https://developer.apple.com/documentation/swiftui/scrollanchorrole) ·
  [.sizeChanges](https://developer.apple.com/documentation/swiftui/scrollanchorrole/sizechanges)
- [Transaction.scrollContentOffsetAdjustmentBehavior](https://developer.apple.com/documentation/swiftui/transaction/scrollcontentoffsetadjustmentbehavior) ·
  [ScrollContentOffsetAdjustmentBehavior](https://developer.apple.com/documentation/swiftui/scrollcontentoffsetadjustmentbehavior) ·
  [.disabled](https://developer.apple.com/documentation/swiftui/scrollcontentoffsetadjustmentbehavior/disabled)
- [onScrollGeometryChange(for:of:action:)](https://developer.apple.com/documentation/swiftui/view/onscrollgeometrychange(for:of:action:)) ·
  [ScrollGeometry](https://developer.apple.com/documentation/swiftui/scrollgeometry) ·
  [Scroll views (API collection)](https://developer.apple.com/documentation/swiftui/scroll-views) ·
  [ScrollViewProxy.scrollTo(\_:anchor:)](https://developer.apple.com/documentation/swiftui/scrollviewproxy/scrollto(_:anchor:))
- [UIScrollView](https://developer.apple.com/documentation/uikit/uiscrollview) ·
  [viewForZooming(in:)](https://developer.apple.com/documentation/uikit/uiscrollviewdelegate/viewforzooming(in:)) ·
  [zoomScale](https://developer.apple.com/documentation/uikit/uiscrollview/zoomscale) ·
  [minimumZoomScale](https://developer.apple.com/documentation/uikit/uiscrollview/minimumzoomscale) ·
  [scrollViewDidEndZooming(\_:with:atScale:)](https://developer.apple.com/documentation/uikit/uiscrollviewdelegate/scrollviewdidendzooming(_:with:atscale:))
- [UICollectionView](https://developer.apple.com/documentation/uikit/uicollectionview) ·
  [contentOffsetAdjustment](https://developer.apple.com/documentation/uikit/uicollectionviewlayoutinvalidationcontext/contentoffsetadjustment) ·
  [invalidationContext(forPreferredLayoutAttributes:…)](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/invalidationcontext(forpreferredlayoutattributes:withoriginalattributes:)) ·
  [shouldInvalidateLayout(forPreferredLayoutAttributes:…)](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/shouldinvalidatelayout(forpreferredlayoutattributes:withoriginalattributes:)) ·
  [preferredLayoutAttributesFitting(\_:)](https://developer.apple.com/documentation/uikit/uicollectionreusableview/preferredlayoutattributesfitting(_:)) ·
  [targetContentOffset(forProposedContentOffset:)](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/targetcontentoffset(forproposedcontentoffset:)) ·
  [estimatedItemSize](https://developer.apple.com/documentation/uikit/uicollectionviewflowlayout/estimateditemsize) ·
  [NSCollectionLayoutDimension.estimated(\_:)](https://developer.apple.com/documentation/uikit/nscollectionlayoutdimension/estimated(_:))
- [UITableView.estimatedRowHeight](https://developer.apple.com/documentation/uikit/uitableview/estimatedrowheight) ·
  [tableView(\_:estimatedHeightForRowAt:)](https://developer.apple.com/documentation/uikit/uitableviewdelegate/tableview(_:estimatedheightforrowat:))
- [PDFView](https://developer.apple.com/documentation/pdfkit/pdfview) ·
  [PDFView.currentDestination](https://developer.apple.com/documentation/pdfkit/pdfview/currentdestination) ·
  [PDFDestination](https://developer.apple.com/documentation/pdfkit/pdfdestination)

Apple WWDC and archived guides
- [WWDC26 session 321 — Dive into lazy stacks and scrolling with SwiftUI](https://developer.apple.com/videos/play/wwdc2026/321/)
- [WWDC23 session 10159 — Beyond scroll views](https://developer.apple.com/videos/play/wwdc2023/10159/)
- [Scroll View Programming Guide for iOS — Basic Zooming Using the Pinch Gestures (archived)](https://developer.apple.com/library/archive/documentation/WindowsViews/Conceptual/UIScrollView_pg/ZoomZoom/ZoomZoom.html)
- [PhotoScroller sample code (archived)](https://developer.apple.com/library/archive/samplecode/PhotoScroller/Introduction/Intro.html)

Apple SDK on this machine (Xcode 16.1, iOS 18.1 SDK)
- `…/iPhoneOS.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64-apple-ios.swiftinterface`
- `…/iPhoneOS.sdk/System/Library/Frameworks/PDFKit.framework/Headers/PDFView.h`, `PDFDestination.h`

Open-source readers
- Aidoku (iOS) — [ZoomableCollectionView.swift](https://github.com/Aidoku/Aidoku/blob/main/iOS/UI/Common/Zooming/ZoomableCollectionView.swift) ·
  [ZoomableCollectionViewController.swift](https://github.com/Aidoku/Aidoku/blob/main/iOS/UI/Common/Zooming/ZoomableCollectionViewController.swift) ·
  [VerticalContentOffsetPreservingLayout.swift](https://github.com/Aidoku/Aidoku/blob/main/iOS/UI/Reader/Readers/Webtoon/VerticalContentOffsetPreservingLayout.swift) ·
  [ReaderWebtoonViewController.swift](https://github.com/Aidoku/Aidoku/blob/main/iOS/UI/Reader/Readers/Webtoon/ReaderWebtoonViewController.swift) ·
  [ZoomableScrollView.swift](https://github.com/Aidoku/Aidoku/blob/main/iOS/Old%20UI/Reader/ZoomableScrollView.swift) (derived from Apple's PhotoScroller `ImageScrollView`)
- Mihon / Tachiyomi (Android) — [WebtoonRecyclerView.kt](https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/tachiyomi/ui/reader/viewer/webtoon/WebtoonRecyclerView.kt)
- Kotatsu (Android) — [WebtoonScalingFrame.kt](https://github.com/KotatsuApp/Kotatsu/blob/devel/app/src/main/kotlin/org/koitharu/kotatsu/reader/ui/pager/webtoon/WebtoonScalingFrame.kt)
