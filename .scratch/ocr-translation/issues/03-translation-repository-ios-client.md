# 03 — `TranslationRepository` + `APITranslationRepository` (iOS)

**What to build:** the iOS-side client for the backend save/list API from Ticket 02. A `TranslationRepository` protocol (in `Networking/`, matching the seam shape of `ComicRepository`) with methods to save a translation pair and to list saved pairs; `APITranslationRepository` is the concrete implementation calling the real endpoints.

**Blocked by:** 02

**Status:** resolved (commit `79b912a` on `feat/ocr-translation-foundation`)

- [x] `TranslationRepository` protocol defined in `Networking/`, shaped so screens depend on the protocol, not a concrete client
- [x] `APITranslationRepository` implements save and list against Ticket 02's real endpoints, routed through `APIConfig.authorizedRequest` (Cloudflare Access headers) like every other backend call in the app
- [x] Unit tests exercise both methods using a stubbed `URLProtocol`-backed `URLSession` — **verified by running**: 9/9 tests pass (`APITranslationRepositoryTests`), no real network call

## Comments

New `SavedTranslation` model kept in its own file (`Networking/SavedTranslation.swift`), not folded into `Shared/Models.swift` alongside `Comic`/`Chapter` — deliberate, matches the spec's explicit "saved learning material is its own domain" decision (story 12).

`targetLanguage` is a plain `String` on this protocol (not `Locale.Language`, which `Translator` uses) — the backend stores/echoes it as an opaque string. Ticket 04 ended up reusing the exact same string scheme (`"zh-Hant"` etc.) for its language picker, so no conversion was needed after all when ticket 05 wired the two together.
