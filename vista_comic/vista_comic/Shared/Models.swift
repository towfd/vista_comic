//
//  Models.swift
//  vista_comic
//
//  Shared display models for the app (M1, retyped for the backend at M5 Slice 3).
//  These are the coordinator-owned contracts consumed by the library, chapter,
//  and reader screens. They now decode directly from the local backend's JSON
//  (see `docs/backend-architecture.md`): image fields are `URL`s the app fetches
//  with `AsyncImage`, and identifiers are the server's stable path-hash strings.
//

import Foundation

/// Reading progress for a single chapter.
/// Decodes from the backend's `"unread" | "reading" | "read"` strings.
/// Presentation of each state is owned by the Library milestone (M2).
enum ReadState: String, Decodable {
    case unread
    case reading
    case read
}

/// A single chapter of a comic.
///
/// The backend describes a chapter in two shapes, so some fields are contextual:
/// - In a comic's detail (`GET /comics/{id}`) a chapter carries `number`, `title`,
///   `pageCount`, and `readState`, but **no** page URLs.
/// - The reader endpoint (`GET /comics/{id}/chapters/{cid}`) carries the ordered
///   `pageURLs` and the resume position `lastReadPage`, but no read state.
/// Decoding tolerates either: missing pages default to `[]`, a missing count is
/// derived from the pages, a missing read state defaults to `.unread`, and a
/// missing `lastReadPage` (no progress yet) defaults to `nil`.
struct Chapter: Identifiable, Hashable, Decodable {
    /// Server-generated, stable across scans/restarts (path-derived hash).
    let id: String
    let number: Int
    let title: String
    /// Ordered page image URLs that make up the vertical reading experience.
    /// Populated by the reader endpoint; empty when only a chapter summary is known.
    /// Consumed by the Reader milestone (M3) via `AsyncImage`.
    let pageURLs: [URL]
    /// Number of pages, from the chapter summary; falls back to `pageURLs.count`.
    let pageCount: Int
    var readState: ReadState
    /// The 1-based page the reader should resume at, from the progress store
    /// (M5 Slice 4). `nil` when the chapter has no saved progress, or when only
    /// a chapter summary (not the reader endpoint) is known.
    let lastReadPage: Int?

    init(
        id: String,
        number: Int,
        title: String,
        pageURLs: [URL] = [],
        pageCount: Int? = nil,
        readState: ReadState = .unread,
        lastReadPage: Int? = nil
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.pageURLs = pageURLs
        self.pageCount = pageCount ?? pageURLs.count
        self.readState = readState
        self.lastReadPage = lastReadPage
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, title, pageCount, readState, lastReadPage
        case pageURLs = "pages"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let number = try container.decode(Int.self, forKey: .number)
        let title = try container.decode(String.self, forKey: .title)
        let pageURLs = try container.decodeIfPresent([URL].self, forKey: .pageURLs) ?? []
        let pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        // Lenient: an unknown or missing read state falls back to `.unread`
        // rather than throwing and blanking the whole screen.
        let rawReadState = try container.decodeIfPresent(String.self, forKey: .readState)
        let readState = rawReadState.flatMap(ReadState.init(rawValue:)) ?? .unread
        let lastReadPage = try container.decodeIfPresent(Int.self, forKey: .lastReadPage)
        self.init(
            id: id,
            number: number,
            title: title,
            pageURLs: pageURLs,
            pageCount: pageCount,
            readState: readState,
            lastReadPage: lastReadPage
        )
    }
}

/// A comic and its chapters.
///
/// Also decodes from two shapes: the library list (`GET /comics`) omits the
/// `chapters` array and instead reports a `chapterCount`, while the detail
/// endpoint (`GET /comics/{id}`) includes the full `chapters`. Decoding tolerates
/// either: a missing `chapters` array defaults to `[]`, and a missing count is
/// derived from the decoded chapters.
struct Comic: Identifiable, Hashable, Decodable {
    /// Server-generated, stable across scans/restarts (path-derived hash).
    let id: String
    let title: String
    /// Cover image URL fetched with `AsyncImage`; `nil` if the server omits it.
    let coverURL: URL?
    let chapters: [Chapter]
    /// Number of chapters, from the library summary; falls back to `chapters.count`.
    let chapterCount: Int
    /// When the user last opened this comic, or `nil` if never started.
    /// Richer reading-progress presentation is owned by the Library milestone (M2).
    let lastReadAt: Date?
    /// The chapter "Continue" should open (M5 Slice 4): the most-recent reading
    /// chapter, else the first unread, else the first chapter — decided by the
    /// backend. Present on the library list (`GET /comics`), absent on the detail
    /// endpoint (`nil`), where the reader already knows the chapters.
    let continueChapterId: String?

    init(
        id: String,
        title: String,
        coverURL: URL?,
        chapters: [Chapter] = [],
        chapterCount: Int? = nil,
        lastReadAt: Date? = nil,
        continueChapterId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.chapters = chapters
        self.chapterCount = chapterCount ?? chapters.count
        self.lastReadAt = lastReadAt
        self.continueChapterId = continueChapterId
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, chapters, chapterCount, lastReadAt, continueChapterId
        case coverURL = "coverUrl"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let title = try container.decode(String.self, forKey: .title)
        let coverURL = try container.decodeIfPresent(URL.self, forKey: .coverURL)
        let chapters = try container.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
        let chapterCount = try container.decodeIfPresent(Int.self, forKey: .chapterCount)
        let lastReadAt = try container.decodeIfPresent(Date.self, forKey: .lastReadAt)
        let continueChapterId = try container.decodeIfPresent(String.self, forKey: .continueChapterId)
        self.init(
            id: id,
            title: title,
            coverURL: coverURL,
            chapters: chapters,
            chapterCount: chapterCount,
            lastReadAt: lastReadAt,
            continueChapterId: continueChapterId
        )
    }
}

/// Navigation value for opening the reader.
///
/// Carries only ids (not full models) so entry points that lack a comic's
/// chapters — e.g. the library card, whose `/comics` summary omits them — can
/// still open the reader (M5 Slice 4). The reader fetches the comic detail to
/// resolve the chapter list for prev/next navigation and the chapter-list sheet.
struct ReaderRoute: Hashable {
    let comicID: String
    let chapterID: String
    /// 1-based page to scroll to on open, overriding the chapter's saved
    /// resume position. `nil` (the default) keeps the normal resume
    /// behavior, so existing call sites are unaffected.
    var targetPage: Int? = nil
    /// Opens a read-only preview: still honors `targetPage`, but never calls
    /// `saveProgress`, however the user navigates once inside — so jumping
    /// back to an old page (e.g. from a record in 歷史紀錄) can
    /// never regress the chapter's real reading progress.
    var isPeek: Bool = false
}
