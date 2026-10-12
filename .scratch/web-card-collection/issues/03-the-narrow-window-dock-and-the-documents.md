# 03 — The narrow-window dock, and the documents

**What to build:** Two unrelated finishing pieces, together because each is small.

**The narrow window.** Where the window is too narrow for the page column and the panel to sit side by side, the open panel docks along the bottom of the window instead, so collecting works at any width. The page column still never moves or resizes — shifting it would move the scroll position and disturb the reader's idea of the current page. The panel covers the bottom of the manga only while it is open, which is only while a card is being typed.

**The documents.** The README says collecting a card still happens on the phone and lists the browser as lacking it; that stops being true. Update its desk section, the paragraph under the architecture diagram, the project layout, and the web test count. The web review spec says a misread card is collected again on the phone; note that it can now be re-collected from the reader. Set this feature's spec to done.

**Blocked by:** 02 — A line already collected, and a failed save. The dock needs only ticket 01; it waits for 02 because both change the same panel.

**Status:** ready-for-agent

- [ ] On a window too narrow for both, the open panel docks to the bottom edge; on a wide one it still docks right
- [ ] Resizing across the threshold with the panel open moves the panel without losing what was typed or the fixed page
- [ ] The page column's position and width are the same with the panel open or collapsed, at both widths
- [ ] Every control is reachable and nothing is clipped in the bottom dock, including the notices from ticket 02
- [ ] The README describes collecting on the web, no longer says it is phone-only, and carries the current web test count
- [ ] The web review spec's note on re-collecting a misread card is brought up to date
- [ ] This feature's spec is marked done once the developer has confirmed the browser checks
- [ ] The developer is handed the browser checks: both docks at a compact and a large window, and the column not shifting in either
