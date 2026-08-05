# 21 — Delete the old paths

**What to build:** Nothing new for the reader — this is the contract half of the expand-then-contract sequence. Every old route to comprehension has been superseded by earlier tickets and now has no callers; this ticket removes them so the codebase describes only how the feature actually works.

Going: the comprehender protocol and its API client, the translation repository and its API client, the saved-translation model, the whole 單字本 feature directory, and on the backend the synchronous comprehend endpoint together with its request-payload size guard — no client uploads images any more. The comprehension client module itself **stays**: it is the seam the worker calls.

From the reader screen: the combined comprehend-or-translate function, the stronger-model upgrade function and its alert, the save function, the outcome enum, the three-banner code, the save control and the upgrade button.

**Staying, and worth stating because it looks like it should go:** the on-device translator, the OCR family, the reader-route jump-back pattern, and the persisted target-language preference. The last of those reads like 單字本-era code but is the pattern the model-tier picker copies — it survives and now has a sibling.

Roughly a thousand lines of tests are **deleted rather than migrated**, because they assert behaviour that no longer exists: the comprehender API client tests, the comprehend-then-fall-back flow tests, and the manual-save flow tests. The saved-translation model, translation repository and vocabulary delete tests were rewritten against the new record and repository in earlier tickets; if any stragglers remain, finish them here. The on-device translation flow tests and every OCR, crop and image test are untouched.

**Blocked by:** 18 and 20 (every replacement path must be live before its predecessor is removed).

**Status:** ready-for-agent

- [ ] The listed iOS types, files and the 單字本 feature directory are gone, and nothing references them.
- [ ] The synchronous comprehend endpoint and its image-size guard are gone from the backend; the comprehension client module remains as the worker's seam.
- [ ] Tests asserting removed behaviour are deleted, not skipped or commented out.
- [ ] The string catalog contains no orphaned entries for removed UI and all new strings are registered.
- [ ] The on-device translator, OCR family, jump-back route and target-language preference are all still present and working.
- [ ] The full test suite is green, and the suite is smaller than before by roughly the deleted tests.
- [ ] The app builds and the whole path works end to end: select → recognise → correct → translate instantly → leave → explanation arrives → badge → open in 歷史紀錄 → jump back to source.
