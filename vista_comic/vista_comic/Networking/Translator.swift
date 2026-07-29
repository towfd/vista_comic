//
//  Translator.swift
//  vista_comic
//
//  The translation-engine seam for the `ocr-translation` feature, mirroring
//  `OCRRecognizer`'s pattern: the OCR result screen's "Translate" action (a
//  later ticket) depends on this protocol, not on a concrete translator, so
//  Apple's on-device `Translation` framework can later be swapped for a
//  backend-hosted translator as a drop-in implementation change (see the
//  `ocr-translation` spec's Further Notes).
//
//  Deliberately holds no source-language configuration — v1's only caller
//  (the OCR flow) only ever produces Vietnamese text (per `ocr-recognition`'s
//  language-scope decision), so the source is a concrete conformer's choice
//  (see `AppleTranslator`), not the protocol's. Only the target language is
//  a parameter, since that one is user-selectable.
//
//  Environment injection added in the `ocr-translation` ticket that wires
//  the first real consumer (the OCR result screen's "Translate" action),
//  mirroring `OCRRecognizer`'s own `EnvironmentKey`/`EnvironmentValues`
//  extension — see the bottom of this file.
//

import Foundation
import SwiftUI

/// Translates text into a target language.
protocol Translator {
    /// Translates `text` into `targetLanguage`, returning the translated
    /// text.
    ///
    /// Throws `TranslationError` for outcomes the caller should branch on
    /// and message from distinctly (the on-device language pack isn't
    /// available, or an underlying translator failure) rather than a bare
    /// generic error.
    func translate(_ text: String, to targetLanguage: Locale.Language) async throws -> String
}

/// Distinguishable translation failure outcomes, so a caller (the OCR result
/// screen) can show a different message for each rather than one generic
/// failure state.
enum TranslationError: Error, Equatable {
    /// The on-device language pack for this language pair isn't downloaded
    /// or otherwise available, so translation can't run until it is.
    case languagePackUnavailable

    /// The underlying translator implementation failed for a reason outside
    /// language-pack availability (e.g. an unexpected `Translation`
    /// framework error). Carries the original error's description rather
    /// than the `Error` itself so this type can stay `Equatable` for tests,
    /// mirroring `OCRRecognitionError.underlying`'s own reasoning.
    case underlying(String)
}

// MARK: - Environment injection

private struct TranslatorKey: EnvironmentKey {
    /// `AppleTranslator` runs entirely on-device with no network access, so
    /// — like `OCRRecognizerKey`'s `VisionOCRRecognizer` default, and unlike
    /// `ComicRepository`'s network-backed default — it's safe to use as the
    /// default for production, previews, and the canvas alike.
    static let defaultValue: any Translator = AppleTranslator()
}

extension EnvironmentValues {
    /// The translator the current view tree runs translation through.
    var translator: any Translator {
        get { self[TranslatorKey.self] }
        set { self[TranslatorKey.self] = newValue }
    }
}
