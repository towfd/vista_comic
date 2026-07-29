# 03 — `TranslationRepository` + `APITranslationRepository` (iOS)

**What to build:** the iOS-side client for the backend save/list API from Ticket 02. A `TranslationRepository` protocol (in `Networking/`, matching the seam shape of `ComicRepository`) with methods to save a translation pair and to list saved pairs; `APITranslationRepository` is the concrete implementation calling the real endpoints.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] `TranslationRepository` protocol defined in `Networking/`, shaped so screens depend on the protocol, not a concrete client
- [ ] `APITranslationRepository` implements save and list against Ticket 02's real endpoints
- [ ] Unit tests exercise both methods using a stubbed `URLProtocol`-backed `URLSession` (same pattern as `APIComicRepositoryTests`), asserting the requests are built correctly and responses decode correctly — no real network call
