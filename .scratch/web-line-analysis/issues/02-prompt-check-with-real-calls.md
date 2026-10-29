# 02 — Prompt check with real calls

**What to build:** Run the agreed prompt through the real API on a handful of real lines (about six, chosen to include a pronoun-heavy line, a sentence-final particle, a Sino-Vietnamese-heavy line, a name, and a sound effect) on Sonnet 5.5 and Opus 5.5, and once on Fable 5.1. Show the developer the results side by side with token counts, time and cost, tune effort, `max_tokens` and any prompt wording they ask for, and record the final settings and the measured per-line cost in the spec.

**Blocked by:** 01

**Status:** ready-for-agent

**Acceptance criteria**

- [ ] The developer agrees the spend before any call is made
- [ ] Results, timings and costs are shown to the developer
- [ ] Settings and any prompt changes they approve are applied, and the spec's *Further Notes* carries the measured costs
