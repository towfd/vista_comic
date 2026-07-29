//
//  ReaderSelectionCropTests.swift
//  vista_comicTests
//
//  End-to-end wiring coverage for Ticket 03 of `ocr-recognition`: proves
//  Ticket 01 (`AuthorizedAsyncImage`'s `onDecoded`/`FetchedImage`) and
//  Ticket 02 (`SelectionCropMapping.cropRect`) are correctly wired together
//  exactly the way `ReaderPage.produceCrop` uses them — decode a real fetched
//  image, map a known on-screen selection to source-pixel space, crop the
//  *decoded* `CGImage`, and assert the result's dimensions and actual pixel
//  content. This does not drive the drag gesture or render any SwiftUI view;
//  see `.scratch/ocr-recognition/issues/03-reader-selection-mode-crop.md` for
//  why the gesture itself isn't exercised here.
//

import Testing
import Foundation
import SwiftUI
import UIKit
@testable import vista_comic

/// A stub `URLProtocol` that never touches the network: it serves a canned
/// response body for every request.
///
/// File-private and not shared with other suites' identically-shaped stubs on
/// purpose — see the comment on `AuthorizedAsyncImageTests`'s stub for why: a
/// shared stub's static state races across suites that Swift Testing may run
/// in parallel with each other.
private final class ReaderSelectionStubURLProtocol: URLProtocol {
    static var responseBody: Data = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: ReaderSelectionStubURLProtocol.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReaderSelectionStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

@Suite("Reader selection → crop, end to end", .serialized)
struct ReaderSelectionCropTests {
    private static let mediaURL = URL(string: "https://api.example.com/media/comic/chapter/1")!

    /// A real 4x4-pixel PNG with four solid-color quadrants (top-left red,
    /// top-right green, bottom-left blue, bottom-right yellow), so a crop of
    /// a known region has an unambiguous expected color — unlike
    /// `SampleData`'s `https://example.com/placeholder.jpg`, which never
    /// resolves to a real image in this environment.
    private static func makeQuadrantTestImage() -> UIImage {
        let size = CGSize(width: 4, height: 4)
        // Without an explicit scale, `UIGraphicsImageRenderer` defaults to the
        // main screen's scale (3x on the simulator's default device), which
        // would render a 12x12-pixel image for this 4x4-point size — pixel
        // dimensions this test asserts on exactly, so scale must be pinned.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2)) // top-left
            UIColor.green.setFill()
            context.fill(CGRect(x: 2, y: 0, width: 2, height: 2)) // top-right
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 2, width: 2, height: 2)) // bottom-left
            UIColor.yellow.setFill()
            context.fill(CGRect(x: 2, y: 2, width: 2, height: 2)) // bottom-right
        }
    }

    /// Reads a `CGImage`'s raw RGBA pixel bytes for exact-value assertions.
    private static func rgbaBytes(of cgImage: CGImage) -> [UInt8] {
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    /// Reproduces exactly what `ReaderPage.produceCrop` does: fetch a real
    /// image through `AuthorizedAsyncImage.fetchImage` (Ticket 01's decoded
    /// `UIImage`), map a known selection rect through
    /// `SelectionCropMapping.cropRect` (Ticket 02) using the decoded image's
    /// actual pixel dimensions, then crop the *decoded* `CGImage` — not a
    /// screenshot of any on-screen rendering, since none is rendered here.
    @Test func selectionOverTopLeftQuadrantCropsExactlyThatRegionAtSourceResolution() async throws {
        let sourceImage = Self.makeQuadrantTestImage()
        ReaderSelectionStubURLProtocol.responseBody = try #require(sourceImage.pngData())

        let fetched = try await AuthorizedAsyncImage<EmptyView>.fetchImage(
            url: Self.mediaURL,
            session: ReaderSelectionStubURLProtocol.makeSession(),
            clientID: "test-client-id",
            clientSecret: "test-client-secret"
        )

        let decodedCGImage = try #require(fetched.decodedImage.cgImage)
        #expect(decodedCGImage.width == 4)
        #expect(decodedCGImage.height == 4)
        let imagePixelSize = CGSize(width: decodedCGImage.width, height: decodedCGImage.height)

        // A selection drawn over exactly the top-left quarter of a 400x400
        // display frame showing this 4x4 image (no letterboxing: both are
        // square, so the fit scale is uniform on both axes).
        let selection = CGRect(x: 0, y: 0, width: 200, height: 200)
        let displayFrameSize = CGSize(width: 400, height: 400)

        let cropRect = SelectionCropMapping.cropRect(
            for: selection,
            displayFrameSize: displayFrameSize,
            imagePixelSize: imagePixelSize
        )
        #expect(cropRect == CGRect(x: 0, y: 0, width: 2, height: 2))

        let croppedCGImage = try #require(decodedCGImage.cropping(to: cropRect))
        #expect(croppedCGImage.width == 2)
        #expect(croppedCGImage.height == 2)

        // Every pixel in the crop should be opaque red (255, 0, 0, 255) — the
        // top-left quadrant's color — proving the crop came from the correct
        // source-pixel region, not an arbitrary or scaled-down one.
        let pixels = Self.rgbaBytes(of: croppedCGImage)
        #expect(pixels.count == 2 * 2 * 4)
        for pixelIndex in stride(from: 0, to: pixels.count, by: 4) {
            #expect(pixels[pixelIndex] == 255, "unexpected red channel at pixel \(pixelIndex / 4)")
            #expect(pixels[pixelIndex + 1] == 0, "unexpected green channel at pixel \(pixelIndex / 4)")
            #expect(pixels[pixelIndex + 2] == 0, "unexpected blue channel at pixel \(pixelIndex / 4)")
            #expect(pixels[pixelIndex + 3] == 255, "unexpected alpha channel at pixel \(pixelIndex / 4)")
        }
    }

    /// A selection drawn entirely outside the displayed image (e.g. a stray
    /// drag that never touched this Page) must map to `.zero`, and — exactly
    /// like `ReaderPage.produceCrop`'s guard — that must not be turned into a
    /// crop: `CGImage.cropping(to:)` on a zero rect returns `nil`.
    @Test func selectionOutsideDisplayFrameProducesNoCrop() async throws {
        let sourceImage = Self.makeQuadrantTestImage()
        ReaderSelectionStubURLProtocol.responseBody = try #require(sourceImage.pngData())

        let fetched = try await AuthorizedAsyncImage<EmptyView>.fetchImage(
            url: Self.mediaURL,
            session: ReaderSelectionStubURLProtocol.makeSession(),
            clientID: "test-client-id",
            clientSecret: "test-client-secret"
        )
        let decodedCGImage = try #require(fetched.decodedImage.cgImage)
        let imagePixelSize = CGSize(width: decodedCGImage.width, height: decodedCGImage.height)
        let displayFrameSize = CGSize(width: 400, height: 400)

        // Well past the display frame's bounds on both axes.
        let strayDrag = CGRect(x: 500, y: 500, width: 50, height: 50)

        let cropRect = SelectionCropMapping.cropRect(
            for: strayDrag,
            displayFrameSize: displayFrameSize,
            imagePixelSize: imagePixelSize
        )
        #expect(cropRect == .zero)
        #expect(decodedCGImage.cropping(to: cropRect) == nil)
    }
}
