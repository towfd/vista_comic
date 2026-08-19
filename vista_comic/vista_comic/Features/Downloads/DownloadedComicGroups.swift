//
//  DownloadedComicGroups.swift
//  vista_comic
//
//  How the 已下載 screen arranges what is on the device (`offline-download`
//  ticket 05).
//
//  A free function and two value types rather than logic inside the view, for
//  the reason the Reader's own derivations are: the ordering and the grouping
//  are the part worth testing, and testing them should not require rendering
//  anything.
//

import Foundation

/// One downloaded chapter, as the list shows it.
struct DownloadedChapterEntry: Identifiable, Equatable, Sendable {
    let chapter: DownloadedChapter
    /// What it is costing, measured from the files rather than remembered.
    let bytes: Int64

    var id: DownloadedChapterID { chapter.id }
}

/// One comic's downloaded chapters.
struct DownloadedComicGroup: Identifiable, Equatable, Sendable {
    let comicID: String
    let title: String
    let entries: [DownloadedChapterEntry]

    var id: String { comicID }
    var bytes: Int64 { entries.reduce(0) { $0 + $1.bytes } }
}

/// Groups downloaded chapters by comic.
///
/// **Comics come newest-download first, chapters within a comic in reading
/// order.** The two orders answer different questions and deliberately differ:
/// which comic is at the top is "what was I last doing", which the reader has
/// just done and can find without looking; where a chapter sits inside it is
/// "where does this fall in the story", which is the only order a list of
/// chapters can be read in.
///
/// The comic's title comes from the records themselves, which is what lets this
/// screen work with no connection — the catalog may be unreachable, and a list
/// that could only name comics by id would be no use on a plane.
func downloadedComicGroups(
    from records: [DownloadedChapter],
    sizes: [DownloadedChapterID: Int64]
) -> [DownloadedComicGroup] {
    let byComic = Dictionary(grouping: records, by: \.comicID)

    return byComic
        .map { comicID, chapters in
            DownloadedComicGroup(
                comicID: comicID,
                // Any of them will do — they all carry the same comic — but the
                // newest is the one whose title was written most recently, so a
                // renamed comic settles on its current name.
                title: chapters.max { $0.startedAt < $1.startedAt }?.comicTitle ?? "",
                entries: chapters
                    .sorted { $0.chapterNumber < $1.chapterNumber }
                    .map { DownloadedChapterEntry(chapter: $0, bytes: sizes[$0.id] ?? 0) }
            )
        }
        .sorted { left, right in
            let leftNewest = latestDownload(in: left)
            let rightNewest = latestDownload(in: right)
            if leftNewest == rightNewest {
                // Stable, so a list of comics downloaded in the same instant
                // does not shuffle between reloads.
                return left.title < right.title
            }
            return leftNewest > rightNewest
        }
}

private func latestDownload(in group: DownloadedComicGroup) -> Date {
    group.entries.map(\.chapter.startedAt).max() ?? .distantPast
}
