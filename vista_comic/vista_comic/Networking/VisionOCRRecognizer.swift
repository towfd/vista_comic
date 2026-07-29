//
//  VisionOCRRecognizer.swift
//  vista_comic
//
//  v1's only concrete `OCRRecognizer`: Apple's on-device `Vision` framework,
//  fixed to Vietnamese recognition — the developer's library is
//  Vietnamese-subtitled Korean webtoon scanlations, all Latin-script text
//  with diacritics (see `.scratch/ocr-recognition/spec.md`). A future
//  backend-hosted recognizer conforms to the same `OCRRecognizer` protocol
//  without any change to it or its callers.
//

import CoreGraphics
import Vision

struct VisionOCRRecognizer: OCRRecognizer {
    /// Vision's per-candidate confidence values range 0...1. Recognized text
    /// whose average confidence falls below this is judged unreliable enough
    /// to withhold rather than show a likely-wrong result to the reader.
    ///
    /// Assumption, not measured: real-world Vietnamese diacritic accuracy is
    /// an open research question tracked separately in the spec's Further
    /// Notes. This is a conservative starting point to revisit once
    /// real-library testing happens.
    static let confidenceThreshold: Float = 0.3

    func recognizeText(in image: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["vi-VN"]
        request.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRRecognitionError.underlying(String(describing: error))
        }

        let observations = request.results ?? []
        guard !observations.isEmpty else {
            throw OCRRecognitionError.noTextFound
        }

        let candidates = observations.compactMap { $0.topCandidates(1).first }
        guard !candidates.isEmpty else {
            throw OCRRecognitionError.noTextFound
        }

        let averageConfidence = candidates.reduce(Float(0)) { $0 + $1.confidence } / Float(candidates.count)
        guard averageConfidence >= Self.confidenceThreshold else {
            throw OCRRecognitionError.lowConfidence
        }

        return Self.joinRecognizedLines(candidates.map(\.string))
    }

    /// Vision returns one candidate per detected text *line*, not per
    /// sentence — a single sentence wrapped across multiple lines in a
    /// speech bubble (the common case for scanlated dialogue) used to come
    /// back as several hard-newline-separated fragments, which then
    /// translated line-by-line instead of as one continuous sentence.
    ///
    /// Joins consecutive lines with a space by default (continuing the same
    /// sentence/clause). Only keeps a line break where a line already ends
    /// in punctuation — a real clause/sentence boundary, not just where the
    /// original image happened to wrap.
    ///
    /// `internal` (not `private`) so `@testable import vista_comic` can
    /// exercise this pure joining logic directly with plain string arrays,
    /// without a synthetic image / real Vision recognition round trip.
    static func joinRecognizedLines(_ lines: [String]) -> String {
        let terminators = CharacterSet(charactersIn: ".,!?:;…")
        var result = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if result.isEmpty {
                result = trimmed
            } else if let last = result.unicodeScalars.last, terminators.contains(last) {
                result += "\n" + trimmed
            } else {
                result += " " + trimmed
            }
        }
        return result
    }
}
