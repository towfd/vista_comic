//
//  APIStudyRepositoryTests.swift
//  vista_comicTests
//
//  What actually goes on the wire for an answer and for the settings
//  (vocabulary stage 6, tickets 05 and 06).
//
//  These assertions matter because the two facts they cover are invisible
//  everywhere else. `context` is the difference between an answer that moves
//  the schedule and one that deliberately does not — and if it were dropped
//  from the payload, the backend would default it to `review` and 永無止盡的
//  訓練 would quietly be rescheduling the reader's deck, with nothing on screen
//  to show for it until the next morning.
//
//  Same `URLProtocol` technique as `APIComprehensionRepositoryTests`, and the
//  same reason for a file-private stub: static state races across suites Swift
//  Testing may run in parallel.
//

import Foundation
import Testing

@testable import vista_comic

private final class StudyStubURLProtocol: URLProtocol {
    static var lastRequest: URLRequest?
    static var responseBody: Data = Data("{}".utf8)
    static var statusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StudyStubURLProtocol.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: StudyStubURLProtocol.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StudyStubURLProtocol.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("APIStudyRepository on the wire", .serialized)
struct APIStudyRepositoryTests {
    private static let outcomeJSON = """
    {
        "review": {
            "id": 1, "cardId": 7, "questionType": "cloze_typed",
            "isCorrect": true, "elapsedMs": null,
            "reviewedAt": "2026-08-31T12:00:00Z"
        },
        "state": "learning",
        "learningStep": 1,
        "ladderStage": 0,
        "previousStage": null,
        "introducedOn": "2026-08-31",
        "dueAt": "2026-08-31T12:07:00Z",
        "intervalChanged": false
    }
    """

    private static let settingsJSON = """
    { "learningSteps": [5, 7, 10], "newCardsPerDay": 15 }
    """

    private func makeRepository(body: String) -> APIStudyRepository {
        StudyStubURLProtocol.lastRequest = nil
        StudyStubURLProtocol.responseBody = Data(body.utf8)
        StudyStubURLProtocol.statusCode = 200

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StudyStubURLProtocol.self]
        return APIStudyRepository(
            baseURL: URL(string: "https://example.test")!,
            session: URLSession(configuration: configuration),
            cfAccessClientID: nil,
            cfAccessClientSecret: nil,
            snapshots: InMemoryDeckSnapshotStore()
        )
    }

    private func sentBody() throws -> [String: Any] {
        let request = try #require(StudyStubURLProtocol.lastRequest)
        let data = try #require(request.httpBody ?? bodyStream(from: request))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// `URLProtocol.request.httpBody` is `nil` when `URLSession` has moved the
    /// body into an upload stream instead.
    private func bodyStream(from request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: 4096)
            if read > 0 { data.append(buffer, count: read) } else { break }
        }
        return data
    }

    @Test("A scheduled answer says so")
    func aReviewAnswerCarriesItsContext() async throws {
        let repository = makeRepository(body: Self.outcomeJSON)

        _ = try await repository.recordReview(
            cardID: 7,
            questionType: .clozeTyped,
            isCorrect: true,
            clientToken: "token-1",
            localDate: Date(),
            answeredAt: Date(),
            context: .review,
            elapsedMs: nil
        )

        #expect(try sentBody()["context"] as? String == "review")
    }

    @Test("A training answer says so, which is the only thing stopping it counting")
    func aTrainingAnswerCarriesItsContext() async throws {
        // The backend defaults a missing `context` to `review`. So dropping it
        // here would not fail — it would silently reschedule the deck from a
        // mode whose whole promise is that it does not.
        let repository = makeRepository(body: Self.outcomeJSON)

        _ = try await repository.recordReview(
            cardID: 7,
            questionType: .clozeTyped,
            isCorrect: true,
            clientToken: "token-1",
            localDate: Date(),
            answeredAt: Date(),
            context: .training,
            elapsedMs: nil
        )

        #expect(try sentBody()["context"] as? String == "training")
    }

    @Test("The answer's own time is sent, not the moment it was posted")
    func theAnswersTimeIsSent() async throws {
        // What offline practice rests on: an answer given this morning and
        // flushed this evening has to be scheduled from this morning.
        let repository = makeRepository(body: Self.outcomeJSON)
        let sixHoursAgo = Date().addingTimeInterval(-6 * 3600)

        _ = try await repository.recordReview(
            cardID: 7,
            questionType: .clozeTyped,
            isCorrect: true,
            clientToken: "token-1",
            localDate: Date(),
            answeredAt: sixHoursAgo,
            context: .review,
            elapsedMs: nil
        )

        let sent = try #require(try sentBody()["answeredAt"] as? String)
        let parsed = try #require(ISO8601DateFormatter().date(from: sent))
        #expect(abs(parsed.timeIntervalSince(sixHoursAgo)) < 2)
    }

    @Test("The whole scheduling block comes back")
    func theOutcomeDecodes() async throws {
        let repository = makeRepository(body: Self.outcomeJSON)

        let outcome = try await repository.recordReview(
            cardID: 7,
            questionType: .clozeTyped,
            isCorrect: true,
            clientToken: "token-1",
            localDate: Date(),
            answeredAt: Date(),
            context: .review,
            elapsedMs: nil
        )

        #expect(outcome.state == .learning)
        #expect(outcome.learningStep == 1)
        #expect(outcome.introducedOn == "2026-08-31")
        #expect(outcome.intervalChanged == false)
    }

    @Test("Settings are read from their own route")
    func settingsAreRead() async throws {
        let repository = makeRepository(body: Self.settingsJSON)

        let settings = try await repository.settings()

        #expect(StudyStubURLProtocol.lastRequest?.url?.path == "/study/settings")
        #expect(StudyStubURLProtocol.lastRequest?.httpMethod == "GET")
        #expect(settings.learningSteps == [5, 7, 10])
        #expect(settings.newCardsPerDay == 15)
    }

    @Test("Settings are written as a whole")
    func settingsAreWritten() async throws {
        // A PUT rather than a PATCH: there are two values and the screen edits
        // both, so a partial update would have to invent what an omitted step
        // list means.
        let repository = makeRepository(body: Self.settingsJSON)

        _ = try await repository.updateSettings(
            StudySettings(learningSteps: [1, 20], newCardsPerDay: 5)
        )

        #expect(StudyStubURLProtocol.lastRequest?.httpMethod == "PUT")
        #expect(try sentBody()["newCardsPerDay"] as? Int == 5)
        #expect(try sentBody()["learningSteps"] as? [Int] == [1, 20])
    }
}
