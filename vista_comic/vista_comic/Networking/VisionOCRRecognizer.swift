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

        return candidates.map(\.string).joined(separator: "\n")
    }
}
