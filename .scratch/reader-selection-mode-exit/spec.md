# Selection mode should end itself

## The request

From the repo owner, 2026-08-10, after using the reader on an iPad:

> 在我辨識完畢後 把ocr的那個扭給他取消 下次按再繼續做便是這樣 因為我發現我不會一直去截要辨識的圖片

Selections turn out to be occasional and deliberate — a glance at one speech bubble — not a run of them. The toolbar toggle was built for the opposite assumption: it stays on until tapped again, which is right for a mode you live in and wrong for a one-off action.

## Why it read as a bug rather than a preference

Selection mode disables the pages `ScrollView`, so a drag draws a rectangle instead of scrolling. That is correct while selecting. But dismissing the result sheet returned the reader to a page that would not scroll, with nothing on screen obviously explaining why — the reader looks frozen, and the fix (tap a toolbar button whose job you have already finished with) is not the one that comes to mind.

## Scope

One ticket. Selection mode ends when a selection is completed, and only then.

Out: the toolbar button itself, the cancel zone, and every other part of the selection flow are unchanged. This is a lifetime change, not a redesign.

## Where this leaves the reader's modes

The reader now has no mode that persists across an action. Worth keeping true: the same reasoning would apply to anything else that disables scrolling, and the failure it produces — a reader that appears to have stopped working — is much worse than the cost of an extra tap.
