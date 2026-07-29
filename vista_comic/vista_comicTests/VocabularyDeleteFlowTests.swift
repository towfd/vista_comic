//
//  VocabularyDeleteFlowTests.swift
//  vista_comicTests
//
//  Exercises `ocr-translation` Ticket 08's wiring: `deleteSavedTranslation(...)`,
//  the free function `VocabularyView` calls from a row's confirmed delete
//  action, mapped onto `LoadState<Void>`. Reuses `StubTranslationRepository`
//  from `SelectionSaveFlowTests` (already exercises the same protocol) so
//  this suite stays independent of the real backend.
//

import Testing
import Foundation
@testable import vista_comic

@Suite("Vocabulary → delete flow")
struct VocabularyDeleteFlowTests {
    @Test func successfulDeleteYieldsLoadedVoid() async throws {
        let stub = StubTranslationRepository()
        stub.deleteResult = .success(())

        let state = await deleteSavedTranslation(id: 42, using: stub)

        guard case .loaded = state else {
            Issue.record("expected .loaded, got \(state)")
            return
        }
        #expect(stub.lastDeletedID == 42)
        #expect(stub.deleteCallCount == 1)
    }

    /// Delete failure surfaces as `.failed` (not silently swallowed), so
    /// `VocabularyView` can show a clear message and leave the entry in the
    /// list — the same non-silent-failure requirement ticket 05 established
    /// for save.
    @Test func deleteFailureSurfacesAsFailedNotSilently() async throws {
        let stub = StubTranslationRepository()
        stub.deleteResult = .failure(.init(message: "network unreachable"))

        let state = await deleteSavedTranslation(id: 1, using: stub)

        guard case .failed(let error) = state else {
            Issue.record("expected .failed, got \(state)")
            return
        }
        #expect((error as? StubTranslationRepository.StubSaveError)?.message == "network unreachable")
    }
}
