//
//  PreviewComicRepository.swift
//  vista_comic
//
//  In-memory `ComicRepository` for `#Preview`s and offline canvas rendering.
//  Serves `SampleData` so previews compile and lay out without a running
//  backend. Cover / page URLs are placeholders, so `AsyncImage` shows its
//  loading or failure phase — which is exactly what a preview needs to exercise.
//

import Foundation

/// Serves the bundled `SampleData` without any network access.
struct PreviewComicRepository: ComicRepository {
    /// Optional artificial delay so previews can show the loading state.
    var delay: Duration = .zero

    func library() async throws -> [Comic] {
        try await waitIfNeeded()
        return SampleData.comics
    }

    func comic(id: String) async throws -> Comic {
        try await waitIfNeeded()
        return SampleData.comics.first { $0.id == id } ?? SampleData.comics[0]
    }

    func readerChapter(comicID: String, chapterID: String) async throws -> Chapter {
        try await waitIfNeeded()
        let comic = SampleData.comics.first { $0.id == comicID }
        let chapter = comic?.chapters.first { $0.id == chapterID }
        return chapter ?? SampleData.comics[0].chapters[0]
    }

    /// Progress is not persisted in previews; accept and drop it.
    func saveProgress(comicID: String, chapterID: String, lastPage: Int) async throws {
        try await waitIfNeeded()
    }

    private func waitIfNeeded() async throws {
        guard delay != .zero else { return }
        try await Task.sleep(for: delay)
    }
}

#if DEBUG
/// Always fails, so `#Preview`s can exercise the shared error / failure states.
struct FailingPreviewRepository: ComicRepository {
    func library() async throws -> [Comic] { throw APIError.invalidResponse }
    func comic(id: String) async throws -> Comic { throw APIError.invalidResponse }
    func readerChapter(comicID: String, chapterID: String) async throws -> Chapter {
        throw APIError.invalidResponse
    }
    func saveProgress(comicID: String, chapterID: String, lastPage: Int) async throws {
        throw APIError.invalidResponse
    }
}
#endif
