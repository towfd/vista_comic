//
//  VisionOCRRecognizerTests.swift
//  vista_comicTests
//
//  Exercises `VisionOCRRecognizer`'s plumbing — image in, text/error out —
//  against synthetic images built at test time. Real-world Vietnamese
//  recognition accuracy is explicitly not what's asserted here (see the
//  `ocr-recognition` spec's Testing Decisions); these images just need to
//  contain unambiguous rendered text or none at all.
//

import Testing
import CoreGraphics
import UIKit
@testable import vista_comic

@Suite("VisionOCRRecognizer")
struct VisionOCRRecognizerTests {
    /// Draws `text` onto a plain white background at a large, high-contrast
    /// size, which Vision reliably recognizes even without knowledge of the
    /// exact font metrics.
    private func makeTextImage(
        _ text: String,
        size: CGSize = CGSize(width: 600, height: 200)
    ) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            (text as NSString).draw(at: CGPoint(x: 20, y: 50), withAttributes: attributes)
        }
        guard let cgImage = image.cgImage else {
            fatalError("Expected UIGraphicsImageRenderer to produce a backing CGImage")
        }
        return cgImage
    }

    /// A plain white image with no text at all, to exercise the
    /// no-text-found path.
    private func makeBlankImage(size: CGSize = CGSize(width: 600, height: 200)) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        guard let cgImage = image.cgImage else {
            fatalError("Expected UIGraphicsImageRenderer to produce a backing CGImage")
        }
        return cgImage
    }

    // MARK: - Happy path

    @Test func recognizesTextDrawnIntoASyntheticImage() async throws {
        let recognizer = VisionOCRRecognizer()
        let image = makeTextImage("Xin chao")

        let text = try await recognizer.recognizeText(in: image)

        #expect(!text.isEmpty)
        #expect(text.lowercased().contains("xin"))
    }

    // MARK: - No text found

    @Test func throwsNoTextFoundForABlankImage() async throws {
        let recognizer = VisionOCRRecognizer()
        let image = makeBlankImage()

        do {
            _ = try await recognizer.recognizeText(in: image)
            Issue.record("expected .noTextFound to be thrown")
        } catch let error as OCRRecognitionError {
            #expect(error == .noTextFound)
        }
    }
}
