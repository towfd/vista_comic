//
//  OriginUnreachableTests.swift
//  vista_comicTests
//
//  What counts as "nothing was reached" (bug fix, 2026-08-21).
//
//  Reported from a device: the backend was down, the phone had signal, and the
//  reader was stuck on a connection error with a full cache sitting on the
//  device. **The tunnel is why.** With `cloudflared` up and the backend down,
//  Cloudflare answers a perfectly valid HTTP 530 — so `URLSession` succeeds, no
//  `URLError` is thrown, and a check for transport failure alone concluded the
//  server had answered.
//
//  Both real failure modes were reproduced against the live tunnel before the
//  fix was written, and neither throws:
//
//      backend down, tunnel up   ->  HTTP 502
//      tunnel down               ->  HTTP 530  ("error code: 1033")
//      both up                   ->  HTTP 200
//

import Foundation
import Testing

@testable import vista_comic

@Suite("What counts as unreachable")
struct OriginUnreachableTests {

    @Test("A transport failure is unreachable", arguments: [
        URLError.Code.notConnectedToInternet,
        .cannotConnectToHost,
        .timedOut,
        .networkConnectionLost,
    ])
    func transportFailuresAreUnreachable(_ code: URLError.Code) {
        #expect(APIConfig.isOriginUnreachable(URLError(code)))
    }

    @Test("A gateway saying there is no origin is unreachable", arguments: [502, 503, 504, 530])
    func gatewayStatusesAreUnreachable(_ status: Int) {
        // The bug. These arrive as *successful* responses carrying a status,
        // so nothing throws a URLError and the app used to conclude the server
        // had answered — 530 being Cloudflare's own "no tunnel", which is
        // exactly the state a stopped `cloudflared` leaves.
        #expect(APIConfig.isOriginUnreachable(APIError.httpStatus(status)))
    }

    @Test("A server that answered badly is not unreachable", arguments: [400, 401, 403, 404, 500])
    func liveFailuresAreNotUnreachable(_ status: Int) {
        // The reason the rule stays narrow. A 500 means the server is there and
        // its code broke; a 401 or 403 means Access rejected the request.
        // Quietly serving yesterday's data for either would look perfectly
        // normal on screen while being silently wrong, and nothing would say so.
        #expect(APIConfig.isOriginUnreachable(APIError.httpStatus(status)) == false)
    }

    @Test("A response the app cannot read is not unreachable")
    func aDecodingFailureIsNotUnreachable() {
        // The server answered; the app could not understand it. Falling back
        // would hide a contract change behind stale data.
        let failure = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))

        #expect(APIConfig.isOriginUnreachable(APIError.decoding(failure)) == false)
    }

    @Test("An invalid response is not unreachable")
    func anInvalidResponseIsNotUnreachable() {
        #expect(APIConfig.isOriginUnreachable(APIError.invalidResponse) == false)
    }
}
