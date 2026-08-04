//
//  APIComprehender.swift
//  vista_comic
//
//  Live `Comprehender` backed by the local FastAPI service's `POST /comprehend`
//  endpoint over `URLSession`, mirroring `APITranslationRepository`'s/
//  `APIComicRepository`'s request-building conventions exactly (including
//  Cloudflare Access header attachment via `APIConfig.authorizedRequest`).
//  See `backend/app/main.py`'s `comprehend` handler and
//  `backend/app/models.py`'s `ComprehendRequest`/`ComprehendResponse` for the
//  exact contract this calls.
//
//  Two differences from `APITranslationRepository`'s `post` helper drive most
//  of this file's shape:
//  - The request body carries both images base64-encoded. The crop travels
//    at its original resolution (the caller's job to have already cropped
//    tightly); the page image is downscaled to a ~1024px long edge *here*
//    (this method's job, not the caller's, per the spec's Implementation
//    Decisions), since only this type knows the wire format's size budget.
//  - The response is always HTTP 200 for both a genuine success and a
//    model-declined outcome — `APITranslationRepository`'s "non-2xx is an
//    error" shortcut doesn't apply. The body's `status` field must be
//    decoded and branched on first; only an actual non-2xx HTTP status (the
//    backend's size-ceiling/daily-cap/upstream-error paths) is a thrown
//    `ComprehensionError.underlying`.
//

import Foundation
import UIKit

/// Requests cloud comprehension results from the backend's `/comprehend` API.
struct APIComprehender: Comprehender {
    /// The long edge (in points) the full page image is downscaled to before
    /// encoding, per the spec's "~1024px long edge" Implementation Decision —
    /// enough for coarse scene/panel context without paying full-resolution
    /// image-token cost for context alone. Images already at or under this
    /// size are sent unscaled.
    private static let pageImageMaxDimension: CGFloat = 1024

    /// JPEG quality for both encoded images. Not pinned by the spec/ticket;
    /// chosen as a reasonable middle ground that keeps request bodies small
    /// without visibly degrading the text the model needs to read.
    private static let jpegQuality: CGFloat = 0.85

    private let baseURL: URL
    private let session: URLSession
    private let cfAccessClientID: String?
    private let cfAccessClientSecret: String?

    init(
        baseURL: URL = APIConfig.baseURL,
        session: URLSession = .shared,
        cfAccessClientID: String? = APIConfig.cfAccessClientID,
        cfAccessClientSecret: String? = APIConfig.cfAccessClientSecret
    ) {
        self.baseURL = baseURL
        self.session = session
        self.cfAccessClientID = cfAccessClientID
        self.cfAccessClientSecret = cfAccessClientSecret
    }

    func comprehend(
        crop cropImage: UIImage,
        page pageImage: UIImage,
        sourceText: String,
        targetLanguage: String,
        useStrongerModel: Bool
    ) async throws -> ComprehensionResult {
        guard let cropImageBase64 = Self.jpegBase64(cropImage, quality: Self.jpegQuality) else {
            throw ComprehensionError.underlying("Failed to encode the selection crop image as JPEG")
        }
        let downscaledPage = Self.downscaled(pageImage, maxDimension: Self.pageImageMaxDimension)
        guard let pageImageBase64 = Self.jpegBase64(downscaledPage, quality: Self.jpegQuality) else {
            throw ComprehensionError.underlying("Failed to encode the page image as JPEG")
        }

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: [
                "cropImageBase64": cropImageBase64,
                "pageImageBase64": pageImageBase64,
                "sourceText": sourceText,
                "targetLanguageCode": targetLanguage,
                "useStrongerModel": useStrongerModel,
            ])
        } catch {
            throw ComprehensionError.underlying("Failed to encode the comprehension request body")
        }

        var request = APIConfig.authorizedRequest(
            url: baseURL.appendingPathComponent("comprehend"),
            method: "POST",
            clientID: cfAccessClientID,
            clientSecret: cfAccessClientSecret
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ComprehensionError.underlying(String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw ComprehensionError.underlying("Invalid response from the comprehension endpoint")
        }
        // Any real non-2xx (413 image-too-large, 429/502 daily-cap or
        // upstream-error paths — see `backend/app/main.py`'s `comprehend`
        // docstring) is a normal thrown failure. A "declined" outcome is
        // never carried by the HTTP status: it is HTTP 200 with
        // `status: "declined"`, decoded below.
        guard (200..<300).contains(http.statusCode) else {
            throw ComprehensionError.underlying("HTTP \(http.statusCode)")
        }

        let decoded: ComprehendResponseBody
        do {
            decoded = try JSONDecoder().decode(ComprehendResponseBody.self, from: data)
        } catch {
            throw ComprehensionError.underlying("Failed to decode the comprehension response: \(error)")
        }

        switch decoded.status {
        case "declined":
            throw ComprehensionError.declined
        case "ok":
            guard let translation = decoded.translation,
                  let grammarNotes = decoded.grammarNotes,
                  let contextNotes = decoded.contextNotes,
                  let toneRegister = decoded.toneRegister
            else {
                throw ComprehensionError.underlying("Comprehension response was \"ok\" but missing an expected field")
            }
            return ComprehensionResult(
                translation: translation,
                grammarNotes: grammarNotes,
                contextNotes: contextNotes,
                toneRegister: toneRegister
            )
        default:
            throw ComprehensionError.underlying("Unrecognized comprehension status: \(decoded.status)")
        }
    }

    // MARK: - Image encoding

    /// Downscales `image` so its long edge is at most `maxDimension`
    /// **pixels**, preserving aspect ratio. Returns `image` unchanged if it's
    /// already at or under that size — this method never upscales.
    ///
    /// Deliberately measured and rendered in pixel space, not `UIImage.size`
    /// (which is in points and divides out `.scale`): the ~1024px cap this
    /// spec asks for is a wire-format/image-token budget on actual encoded
    /// pixels, so bounding by `.size` would silently send 2x/3x the intended
    /// pixel count for any source image whose `.scale` isn't 1 (e.g. an
    /// on-screen Retina-rendered `UIImage`). Rendering at an explicit
    /// `format.scale = 1` guarantees the output `UIImage`'s point size and
    /// pixel size are identical, so the cap holds regardless of the source's
    /// own scale.
    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let longEdge = max(pixelWidth, pixelHeight)
        guard longEdge > maxDimension, longEdge > 0 else { return image }

        let scale = maxDimension / longEdge
        let newPixelSize = CGSize(width: pixelWidth * scale, height: pixelHeight * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newPixelSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newPixelSize))
        }
    }

    private static func jpegBase64(_ image: UIImage, quality: CGFloat) -> String? {
        image.jpegData(compressionQuality: quality)?.base64EncodedString()
    }
}

/// Decoding shape for `POST /comprehend`'s response body, mirroring
/// `ComprehendResponse` (`backend/app/models.py`) field-for-field. Kept
/// private and separate from the public `ComprehensionResult` the protocol
/// returns, since this type also carries the discriminator (`status`) and
/// optionality the wire format needs but the success-only `ComprehensionResult`
/// doesn't.
private struct ComprehendResponseBody: Decodable {
    let status: String
    let translation: String?
    let grammarNotes: String?
    let contextNotes: String?
    let toneRegister: String?
}
