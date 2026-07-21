//
//  SampleData.swift
//  vista_comic
//
//  A single consistent source of local sample data (M1).
//  The same values drive the library, chapter list, and reader so the
//  whole flow can be demonstrated without a backend or network.
//

import Foundation

enum SampleData {

    /// All comics shown in the library.
    static let comics: [Comic] = [
        Comic(
            title: "Frieren",
            coverImageName: "Landscape_4",
            chapters: chapters(count: 12, pagesEach: 8, started: true),
            lastReadAt: Date(timeIntervalSinceNow: -3600)      // read an hour ago
        ),
        Comic(
            title: "Spy Family",
            coverImageName: "Landscape_4",
            chapters: chapters(count: 8, pagesEach: 6, started: true),
            lastReadAt: Date(timeIntervalSinceNow: -86_400 * 3) // read three days ago
        ),
        Comic(
            title: "Dandadan",
            coverImageName: "Landscape_4",
            chapters: chapters(count: 5, pagesEach: 10, started: false) // never started
        )
    ]

    /// Builds a run of chapters. A started comic has an in-progress mix of read
    /// states; an unstarted comic keeps every chapter unread so the chapter data
    /// stays consistent with the comic's `lastReadAt`.
    private static func chapters(count: Int, pagesEach: Int, started: Bool) -> [Chapter] {
        (1...count).map { number in
            Chapter(
                number: number,
                title: "Chapter \(number)",
                pageImageNames: Array(repeating: "Landscape_4", count: pagesEach),
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
