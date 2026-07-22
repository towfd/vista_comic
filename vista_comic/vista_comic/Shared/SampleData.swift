//
//  SampleData.swift
//  vista_comic
//
//  Mock catalog for `#Preview`s and `PreviewComicRepository` (M1, retyped at
//  M5 Slice 3). The live app now reads the backend; this keeps previews and the
//  offline canvas rendering the full library → chapter → reader layout without a
//  network. Cover / page URLs are placeholders, so `AsyncImage` shows its
//  loading or failure phase in previews (there is no local image to render).
//

import Foundation

enum SampleData {

    /// A stable placeholder URL. Not expected to load in previews; it exercises
    /// `AsyncImage`'s non-success phases so preview layout still resolves.
    private static let placeholderURL = URL(string: "https://example.com/placeholder.jpg")!

    /// All comics shown in the library.
    static let comics: [Comic] = [
        Comic(
            id: "sample-frieren",
            title: "Frieren",
            coverURL: placeholderURL,
            chapters: chapters(prefix: "frieren", count: 12, pagesEach: 8, started: true),
            lastReadAt: Date(timeIntervalSinceNow: -3600)      // read an hour ago
        ),
        Comic(
            id: "sample-spy-family",
            title: "Spy Family",
            coverURL: placeholderURL,
            chapters: chapters(prefix: "spy", count: 8, pagesEach: 6, started: true),
            lastReadAt: Date(timeIntervalSinceNow: -86_400 * 3) // read three days ago
        ),
        Comic(
            id: "sample-dandadan",
            title: "Dandadan",
            coverURL: placeholderURL,
            chapters: chapters(prefix: "dandadan", count: 5, pagesEach: 10, started: false) // never started
        )
    ]

    /// Builds a run of chapters. A started comic has an in-progress mix of read
    /// states; an unstarted comic keeps every chapter unread so the chapter data
    /// stays consistent with the comic's `lastReadAt`.
    private static func chapters(prefix: String, count: Int, pagesEach: Int, started: Bool) -> [Chapter] {
        (1...count).map { number in
            Chapter(
                id: "\(prefix)-ch\(number)",
                number: number,
                title: "Chapter \(number)",
                pageURLs: Array(repeating: placeholderURL, count: pagesEach),
                readState: started ? startedReadState(for: number) : .unread
            )
        }
    }

    private static func startedReadState(for number: Int) -> ReadState {
        switch number {
        case 1: return .read
        case 2: return .reading
        default: return .unread
        }
    }
}
