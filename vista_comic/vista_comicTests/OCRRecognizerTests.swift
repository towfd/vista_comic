//
//  OCRRecognizerTests.swift
//  vista_comicTests
//
//  Exercises the `OCRRecognizer` protocol boundary itself — a stub
//  conformer, independent of `VisionOCRRecognizer` — so the shape a caller
//  (the Reader's selection flow, wired in a later ticket) depends on is
//  verified without invoking real Vision. In particular: the three
//  `OCRRecognitionError` cases are distinguishable outcomes a caller can
//  branch on and message from.
//

import Testing
import CoreGraphics
import UIKit
@testable import vista_comic

/// A stub `OCRRecognizer`: returns or throws whatever the test configures,
/// and records the last image it was asked to recognize, so tests can
/// assert on the protocol boundary without a real recognizer.
final class StubOCRRecognizer: OCRRecognizer {
    var result: Result<String, OCRRecognitionError> = .success("")
    private(set) var lastImage: CGImage?

    func recognizeText(in image: CGImage) async throws -> String {
        lastImage = image
        switch result {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        }
    }
}

@Suite("OCRRecognizer protocol boundary")
struct OCRRecognizerTests {
    private func makeImage() -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { _ in }.cgImage!
    }

    // MARK: - Success

    @Test func returnsRecognizedTextOnSuccess() async throws {
        let stub = StubOCRRecognizer()
        stub.result = .success("Xin chào")

        let text = try await stub.recognizeText(in: makeImage())

        #expect(text == "Xin chào")
    }

    @Test func passesTheGivenImageThrough() async throws {
        let stub = StubOCRRecognizer()
        stub.result = .success("ignored")
        let image = makeImage()

        _ = try await stub.recognizeText(in: image)

        #expect(stub.lastImage === image)
    }

    // MARK: - Distinguishable failures

    /// A stand-in for a caller (the Reader's result UI) that must show a
    /// different message per error case. Its exhaustive `switch` over
    /// `OCRRecognitionError` is itself a compile-time guarantee that all
    /// three cases stay distinguishable as the type evolves.
    private func message(for error: OCRRecognitionError) -> String {
        switch error {
        case .noTextFound: return "no-text-found"
        case .lowConfidence: return "low-confidence"
        case .underlying: return "underlying"
        }
    }

    @Test func noTextFoundIsDistinguishableFromLowConfidence() async throws {
        let stub = StubOCRRecognizer()
        stub.result = .failure(.noTextFound)

        do {
            _ = try await stub.recognizeText(in: makeImage())
            Issue.record("expected .noTextFound to be thrown")
        } catch let error as OCRRecognitionError {
            #expect(error == .noTextFound)
            #expect(message(for: error) == "no-text-found")
        }
    }

    @Test func lowConfidenceIsDistinguishableFromNoTextFound() async throws {
        let stub = StubOCRRecognizer()
        stub.result = .failure(.lowConfidence)

        do {
            _ = try await stub.recognizeText(in: makeImage())
            Issue.record("expected .lowConfidence to be thrown")
        } catch let error as OCRRecognitionError {
            #expect(error == .lowConfidence)
            #expect(message(for: error) == "low-confidence")
        }
    }

    @Test func underlyingFailureCarriesTheOriginalErrorsDescription() async throws {
        let stub = StubOCRRecognizer()
        stub.result = .failure(.underlying("Vision request failed"))

        do {
            _ = try await stub.recognizeText(in: makeImage())
            Issue.record("expected .underlying to be thrown")
        } catch let error as OCRRecognitionError {
            #expect(error == .underlying("Vision request failed"))
            #expect(message(for: error) == "underlying")
        }
    }
}
