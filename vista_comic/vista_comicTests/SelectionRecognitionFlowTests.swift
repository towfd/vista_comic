//
//  SelectionRecognitionFlowTests.swift
//  vista_comicTests
//
//  Exercises Ticket 05's wiring: `recognizeSelection(_:using:)`, the free
//  function `CroppedSelectionPreview` calls from its `.task` to run a
//  confirmed crop through `OCRRecognizer` and map the outcome onto
//  `LoadState`. Uses the same `StubOCRRecognizer` as `OCRRecognizerTests`
//  (Ticket 04) so this suite stays independent of real Vision — it proves
//  the selection-complete → recognize → display/edit path, not recognition
//  accuracy.
//

import Testing
import CoreGraphics
import UIKit
@testable import vista_comic

@Suite("Selection → recognition flow")
struct SelectionRecognitionFlowTests {
    /// A real `UIImage` backed by `cgImage`, matching what `produceCrop`
    /// hands `CroppedSelectionPreview` (a `UIImage(cgImage:)` crop).
    private func makeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { _ in }
    }

    // MARK: - Success

    @Test func successfulRecognitionYieldsLoadedText() async throws {
        let stub = StubOCRRecognizer()
        stub.result = .success("Xin chào")

        let state = await recognizeSelection(makeImage(), using: stub)

        guard case .loaded(let text) = state else {
            Issue.record("expected .loaded, got \(state)")
            return
        }
        #expect(text == "Xin chào")
    }

    @Test func passesTheCropsCGImageToTheRecognizer() async throws {
        let stub = StubOCRRecognizer()
        stub.result = .success("ignored")
        let image = makeImage()

        _ = await recognizeSelection(image, using: stub)

        #expect(stub.lastImage === image.cgImage)
    }

    // MARK: - Distinguishable failures

    @Test func noTextFoundSurfacesAsFailedWithThatError() async throws {
        let stub = StubOCRRecognizer()
        stub.result = .failure(.noTextFound)

        let state = await recognizeSelection(makeImage(), using: stub)

        guard case .failed(let error) = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
        #expect(error as? OCRRecognitionError == .noTextFound)
    }

    @Test func lowConfidenceSurfacesAsFailedWithThatError() async throws {
        let stub = StubOCRRecognizer()
        stub.result = .failure(.lowConfidence)

        let state = await recognizeSelection(makeImage(), using: stub)

        guard case .failed(let error) = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
        #expect(error as? OCRRecognitionError == .lowConfidence)
    }

    @Test func underlyingFailureSurfacesWithItsDescription() async throws {
        let stub = StubOCRRecognizer()
        stub.result = .failure(.underlying("Vision request failed"))

        let state = await recognizeSelection(makeImage(), using: stub)

        guard case .failed(let error) = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
        #expect(error as? OCRRecognitionError == .underlying("Vision request failed"))
    }

    // MARK: - Retry

    /// A retry re-runs recognition against the same crop and can succeed
    /// after an earlier failure — the flow a "Retry" button drives.
    @Test func retryingAfterFailureCanSucceed() async throws {
        let stub = StubOCRRecognizer()
        let image = makeImage()

        stub.result = .failure(.noTextFound)
        let firstAttempt = await recognizeSelection(image, using: stub)
        guard case .failed = firstAttempt else {
            Issue.record("expected the first attempt to fail")
            return
        }

        stub.result = .success("Xin chào")
        let retryAttempt = await recognizeSelection(image, using: stub)
        guard case .loaded(let text) = retryAttempt else {
            Issue.record("expected the retry to succeed")
            return
        }
        #expect(text == "Xin chào")
    }

    // MARK: - Boundary: no pixel data

    /// A `UIImage` with no backing `cgImage` (constructed from a `CIImage`
    /// instead) never reaches the recognizer at all — `recognizeSelection`
    /// fails locally rather than crashing or hanging.
    @Test func imageWithNoCGImageFailsWithoutCallingTheRecognizer() async throws {
        let stub = StubOCRRecognizer()
        stub.result = .success("should never be returned")
        let ciOnlyImage = UIImage(ciImage: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 5, height: 5)))
        #expect(ciOnlyImage.cgImage == nil)

        let state = await recognizeSelection(ciOnlyImage, using: stub)

        guard case .failed(let error) = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
        #expect(error as? OCRRecognitionError != nil)
        #expect(stub.lastImage == nil)
    }
}
