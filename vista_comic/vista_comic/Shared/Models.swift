//
//  Models.swift
//  vista_comic
//
//  Shared display models for the local UI prototype (M1).
//  These are the coordinator-owned contracts consumed by the
//  library, chapter, and reader screens.
//

import Foundation

/// Reading progress for a single chapter.
/// Presentation of each state is owned by the Library milestone (M2).
enum ReadState {
    case unread
    case reading
    case read
}

/// A single chapter of a comic.
struct Chapter: Identifiable, Hashable {
    let id: UUID
    let number: Int
    let title: String
    /// Ordered image asset names that make up the vertical reading experience.
    /// Consumed by the Reader milestone (M3).
    let pageImageNames: [String]
    var readState: ReadState

    init(
        id: UUID = UUID(),
        number: Int,
        title: String,
        pageImageNames: [String],
        readState: ReadState = .unread
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.pageImageNames = pageImageNames
        self.readState = readState
    }
}

/// A comic and its chapters.
struct Comic: Identifiable, Hashable {
    let id: UUID
    let title: String
    let coverImageName: String
    let chapters: [Chapter]
    /// When the user last opened this comic, or `nil` if never started.
    /// Richer reading-progress presentation is owned by the Library milestone (M2).
    let lastReadAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        coverImageName: String,
        chapters: [Chapter],
        lastReadAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.coverImageName = coverImageName
        self.chapters = chapters
        self.lastReadAt = lastReadAt
    }
}

/// Navigation value for opening the reader.
/// Carries the whole comic (not just one chapter) so the reader can offer a
/// chapter list and, later, previous / next chapter navigation (M3).
struct ReaderRoute: Hashable {
    let comic: Comic
    let chapter: Chapter
}
