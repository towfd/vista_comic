//
//  OCRRecognizer.swift
//  vista_comic
//
//  The recognition-engine seam for the `ocr-recognition` feature, mirroring
//  `ComicRepository`'s pattern: the Reader's selection flow (a later ticket)
//  depends on this protocol, not on a concrete recognizer, so on-device
//  Vision can later be swapped for a backend-hosted recognizer
//  (`APIOCRRecognizer`) as a drop-in implementation change.
//
//  Deliberately holds no language or execution-location configuration —
//  those are choices for a concrete conformer (see `VisionOCRRecognizer`),
//  not the protocol. A backend-hosted recognizer conforming to this same
//  protocol should require no changes here.
//

import CoreGraphics

/// Recognizes text within an image region.
///
/// Callers are expected to pass an already-cropped source-pixel image (see
/// the `ocr-recognition` spec's selection-to-crop mapping) rather than a
/// full Page; this protocol has no opinion on cropping, language, or where
/// recognition executes.
protocol OCRRecognizer {
    /// Recognizes text in `image`, returning the recognized text.
    ///
    /// Throws `OCRRecognitionError` for outcomes the caller should branch on
    /// and message from distinctly (no text found, low confidence, an
    /// underlying recognizer failure) rather than a bare generic error.
    func recognizeText(in image: CGImage) async throws -> String
}

/// Distinguishable recognition failure outcomes, so a caller (the Reader's
/// result UI) can show a different message for each rather than one generic
/// failure state.
enum OCRRecognitionError: Error, Equatable {
    /// The recognizer found no text at all in the image.
    case noTextFound

    /// Text was found, but the recognizer's confidence in it was too low to
    /// be worth showing as a result.
    case lowConfidence

    /// The underlying recognizer implementation failed for a reason outside
    /// the two cases above (e.g. a `Vision` framework error). Carries the
    /// original error's description rather than the `Error` itself so this
    /// type can stay `Equatable` for tests.
    case underlying(String)
}
