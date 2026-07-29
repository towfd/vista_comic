# 02 — Selection-to-crop coordinate mapping (pure unit, no UI)

**What to build:** a pure, non-view function/type that takes an on-screen selection rectangle plus the displayed page image's frame/scale/source-pixel-dimensions, and returns the crop rectangle in source-image pixel space. No gesture, no SwiftUI view — just the coordinate math and its tests, so it's independently verifiable without rendering anything. This is the seam a later ticket wires into the actual drag gesture and image crop.

**Blocked by:** None — can start immediately

**Status:** ready-for-agent

- [ ] A pure function/type with no SwiftUI `View` dependency, directly callable from a unit test
- [ ] Unit tests cover: a fully in-bounds selection, a selection partially outside the image bounds (clamped to the image), a selection spanning off the image entirely (e.g. into an adjacent page), and a degenerate/zero-size selection
- [ ] The output is documented as a pixel-space `CGRect` matching what a `CGImage`/`UIImage` crop operation expects
