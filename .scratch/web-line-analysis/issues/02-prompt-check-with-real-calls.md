# 02 — Prompt check with real calls

**What to build:** Run the agreed prompt through the real API on a handful of real lines (about six, chosen to include a pronoun-heavy line, a sentence-final particle, a Sino-Vietnamese-heavy line, a name, and a sound effect) on Sonnet 5.5 and Opus 5.5, and once on Fable 5.1. Show the developer the results side by side with token counts, time and cost, tune effort, `max_tokens` and any prompt wording they ask for, and record the final settings and the measured per-line cost in the spec.

**Blocked by:** 01

**Status:** done (2026-10-29)

**What was run**

Approved spend: about US$1–2. Spent: US$0.63 for 18 calls (six lines × Sonnet / Opus / Fable) plus US$0.07 re-checking Sonnet after the prompt change. The first attempt failed with 401 on a stale local key and was not billed.

Lines: `Anh không thanh toán tiền viện phí cho tôi à?` (particle, Sino-Vietnamese), `ANH YÊU NÀY, VẬY ANH CÓ THỂ MUA CHO EM TÚI XÁCH MỚI ĐƯỢC KHÔNG?` (pronouns), `TÔI SẼ LÀM CHO ANH VÀ CẬU TA CẢ ĐỜI NÀY KHÔNG NGỐC ĐẦU LÊN ĐƯỢC!!!` (long, idiom, OCR typo), `BỆNH NHÂN KANG JI WON, TỚI GIỜ UỐNG THUỐC R...` (name, cut-off word), `AI GU, GIỜ ĐANG LÀ MÙA XUÂN NHỈ?` (Korean interjection, nhỉ), `CỐC CỐC` (sound effect).

Findings: all three split words correctly, explained against the translation without retranslating, recognised `R...` as cut-off `rồi`, `AI GU` as Korean 아이고, and used the name table. Opus and Fable named `NGỐC` as a misspelling of `ngóc`. Sonnet over-assigned Sino-Vietnamese characters to native words; the developer approved tightening that instruction (see the spec's *Further Notes* for figures and the change).

**Acceptance criteria**

- [x] The developer agrees the spend before any call is made
- [x] Results, timings and costs are shown to the developer
- [x] Settings and any prompt changes they approve are applied, and the spec's *Further Notes* carries the measured costs
