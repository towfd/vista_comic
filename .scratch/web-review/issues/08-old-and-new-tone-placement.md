Type: grilling
Status: resolved

# Old and new tone placement

## Question

Vietnamese has two conventions for where a tone mark sits in some vowel pairs — `hoà` and `hòa`, `thuý` and `thúy` — and they are different strings that no Unicode normalisation brings together. Is one the same answer as the other?

On the phone this never surfaced: the two differ only once tones are ignored, so the lenient path absorbed it and the answer came back "correct, watch the tones". [The web is strict about tones](04-typing-vietnamese-at-a-desk.md), so on the web the difference is now the whole verdict. A card's text is whatever the scanlation printed and the reader confirmed; what the reader types is whatever their input method is set to produce. If the two follow different conventions, a perfect answer is marked wrong and lapses the card, every time, with nothing the reader can do at the keyboard.

Either the web folds the two conventions together before comparing — a rule the phone does not have — or strictness means this too.

## Answer

**They are the same answer. The web judges which tone a syllable carries, not which vowel the mark sits on.**

Strictness was chosen to make tones count, and both spellings name the same tone on the same syllable; where the mark is printed is a typographic convention, and the deck mixes conventions because its text comes from different scanlation groups while an input method can only be set to one. So this does not depend on which convention the developer's input method emits, and that was not measured.

The comparison, per whitespace-separated syllable and before spacing is stripped: decompose, lift out the five tone marks (U+0300 grave, U+0301 acute, U+0303 tilde, U+0309 hook above, U+0323 dot below), and compare what is left — letters with their circumflex, breve and horn intact — together with the tone marks lifted. Run in Node on 2026-10-12:

| A | B | |
|---|---|---|
| `hoà` | `hòa` | same |
| `thuý` | `thúy` | same |
| `khoẻ` | `khỏe` | same |
| `hoà` | `hoá` | differ — another tone |
| `hoa` | `hòa` | differ — tone missing |
| `muốn` | `muôn` | differ — tone missing |
| `tôi` | `toi` | differ — circumflex missing |
| `được` | `đươc` | differ — tone missing |
| `của` | `cuả` | same |

The last row is the accepted side effect: a tone on a vowel neither convention would choose also passes. A third verdict that counts the answer and shows the card's own spelling was offered and declined.

**This is judging only**, for both question types — a typed cloze answer is one syllable or a few and takes the same comparison. Card identity and finding deck words inside a sentence stay exact, as they are on the phone. It is a rule the phone does not have, and with strict tones it is the second place the two judges differ on purpose.

## Comments

Surfaced by [What the engine must reproduce](01-what-the-engine-must-reproduce.md), which ran the pair through the Swift keys: they differ under the identity key and are equal under the tone key. Which convention the developer's input method emits was not captured by the typing test — none of its six sentences contains such a pair.

Resolved 2026-10-12 via `/grilling`. [Keeping two engines in step](05-keeping-two-engines-in-step.md) inherits this as a second carve-out.
