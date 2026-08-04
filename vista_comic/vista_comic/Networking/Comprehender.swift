//
//  Comprehender.swift
//  vista_comic
//
//  The cloud LLM comprehension seam for the `llm-comprehension` feature,
//  mirroring `OCRRecognizer`'s/`Translator`'s existing shape (protocol +
//  distinguishable error enum + `EnvironmentKey`/`EnvironmentValues`
//  extension): the OCR result screen's "Translate" action (ticket 14) will
//  depend on this protocol, not a concrete implementation, so the real
//  backend-hosted comprehender (`APIComprehender`) can be swapped for a stub
//  in tests and `#Preview`s.
//
//  Deliberately its own protocol, distinct from `Translator` (per the spec's
//  Implementation Decisions) — the on-device `Translator`/`AppleTranslator`
//  seam is already shipped and reviewed and stays untouched; `Translator`
//  only gains a new *caller* (ticket 14's automatic fallback path), not new
//  behavior or a shared protocol with this one.
//
//  Takes the selection crop image and the full page image as `UIImage`
//  (unlike `OCRRecognizer.recognizeText(in:)`'s `CGImage`) because a
//  network-backed conformer needs to JPEG-encode both for the request body,
//  and `CroppedSelection`/`ComicView`'s decoded page already hold `UIImage`s
//  (see `Features/ComicPage/ComicView.swift`) — no extra conversion needed at
//  the call site.
//

import SwiftUI

/// Requests a cloud LLM's deeper explanation of a selected piece of text,
/// given both the tightly-cropped selection and the wider page it came from.
///
/// Mirrors the backend's `POST /comprehend` contract (see
/// `backend/app/main.py`'s `comprehend` handler and
/// `backend/app/models.py`'s `ComprehendRequest`/`ComprehendResponse`):
/// `sourceText` is sent as-is, never re-derived from the images server-side,
/// so a user's OCR correction is respected rather than silently overridden.
protocol Comprehender {
    /// Requests a comprehension result for `sourceText`, using `cropImage`
    /// (the selection, at its original resolution) and `pageImage` (the full
    /// page it was selected from, for visual/scene context) as supporting
    /// context, translating and explaining into `targetLanguage`.
    ///
    /// `useStrongerModel` requests the backend's stronger model tier (Claude
    /// Sonnet 5 instead of the default Claude Haiku 4.5) for the manual
    /// re-request path — the parameter exists on this protocol now even
    /// though no UI triggers it yet (that's ticket 17).
    ///
    /// Throws `ComprehensionError` for outcomes the caller should branch on
    /// and message/fall back from distinctly (the model declined to analyze
    /// this selection, or an underlying network/server failure) rather than
    /// a bare generic error.
    func comprehend(
        crop cropImage: UIImage,
        page pageImage: UIImage,
        sourceText: String,
        targetLanguage: String,
        useStrongerModel: Bool
    ) async throws -> ComprehensionResult
}

/// A cloud comprehension result: a translation plus the deeper explanation
/// fields a plain translation leaves out. Mirrors
/// `ComprehendResponse`'s four "ok" fields exactly (see
/// `backend/app/models.py`).
struct ComprehensionResult: Equatable {
    let translation: String
    let grammarNotes: String
    let contextNotes: String
    let toneRegister: String
}

/// Distinguishable comprehension failure outcomes, so a caller (the OCR
/// result screen) can pick the right status banner/fallback for each rather
/// than one generic failure state.
enum ComprehensionError: Error, Equatable {
    /// The backend responded with `{"status": "declined"}` — the model found
    /// no valid result to return (e.g. a content-policy decline), distinct
    /// from a connectivity/server problem so the caller can show that
    /// distinctly rather than an "offline" message (per the spec's Testing
    /// Decisions and user story 9).
    case declined

    /// The request failed for a reason outside a declined result (a network
    /// failure, a non-2xx HTTP status, or an unexpected/malformed response
    /// body). Carries the original error's description rather than the
    /// `Error` itself so this type can stay `Equatable` for tests, mirroring
    /// `TranslationError.underlying`'s/`OCRRecognitionError.underlying`'s own
    /// reasoning.
    case underlying(String)
}

// MARK: - Environment injection

private struct ComprehenderKey: EnvironmentKey {
    /// `APIComprehender` is network-backed (it calls the real `/comprehend`
    /// endpoint), so — unlike `OCRRecognizerKey`'s/`TranslatorKey`'s
    /// on-device defaults — this can't reuse their "safe as a default
    /// everywhere" reasoning. It instead mirrors `TranslationRepositoryKey`'s
    /// precedent (`Networking/TranslationRepository.swift`): that seam is
    /// also network-backed, sits in this same `ocr-translation`/
    /// `llm-comprehension` lineage, and defaults straight to its concrete
    /// production conformer (`APITranslationRepository()`) rather than to a
    /// `ComicRepository`-style offline preview mock — there is no
    /// `PreviewComprehender` today, and none is required by this ticket, so
    /// following `ComicRepository`'s older mocked-default pattern here would
    /// mean building an unused type. `#Preview`s / the canvas that don't
    /// override this environment value simply never invoke `comprehend(...)`
    /// (it only runs from an explicit user action, per the spec's developer
    /// story 15), so this default is never exercised outside a real request.
    static let defaultValue: any Comprehender = APIComprehender()
}

extension EnvironmentValues {
    /// The comprehender the current view tree requests deeper explanations
    /// through.
    var comprehender: any Comprehender {
        get { self[ComprehenderKey.self] }
        set { self[ComprehenderKey.self] = newValue }
    }
}
