//
//  DownloadedChapterRow.swift
//  vista_comic
//
//  One row of 已下載 (`offline-download` ticket 05): which chapter it is, what
//  it costs, and whether it is actually readable yet.
//
//  Takes its entry and its state as parameters, so a preview renders every case
//  with no store, no engine and nothing on disk.
//

import SwiftUI

struct DownloadedChapterRow: View {
    let entry: DownloadedChapterEntry
    let state: ChapterDownloadState

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.chapter.chapterTitle)
                    .font(AppFont.rowTitle)

                HStack(spacing: 6) {
                    Text("#\(entry.chapter.chapterNumber)")
                    // Size, not page count: what the reader is deciding is what
                    // to free, and pages do not answer that.
                    Text(entry.bytes.formatted(.byteCount(style: .file)))
                    if let progress {
                        Text(progress)
                            .foregroundStyle(Color(.primaryRed))
                    }
                }
                .font(AppFont.caption)
                .foregroundStyle(Color(.grayFont))
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// Shown only while a chapter is still arriving. A finished one says nothing
    /// — everything on this screen is downloaded, so "downloaded" would be noise
    /// on every row.
    private var progress: String? {
        switch state {
        case .downloading(let completed, let total):
            return total > 0
                ? String(localized: "Downloading \(completed)/\(total)")
                : String(localized: "Downloading")
        case .failed:
            return String(localized: "Incomplete")
        case .downloaded, .notDownloaded:
            return nil
        }
    }
}

#Preview {
    let chapter = DownloadedChapter(
        comicID: "comic-1",
        comicTitle: "Alpha",
        chapterID: "chapter-1",
        chapterNumber: 12,
        chapterTitle: "Chapter 12",
        pageCount: 40,
        isComplete: true
    )

    return List {
        DownloadedChapterRow(
            entry: DownloadedChapterEntry(chapter: chapter, bytes: 12_400_000),
            state: .downloaded
        )
        DownloadedChapterRow(
            entry: DownloadedChapterEntry(chapter: chapter, bytes: 3_100_000),
            state: .downloading(completed: 9, total: 40)
        )
        DownloadedChapterRow(
            entry: DownloadedChapterEntry(chapter: chapter, bytes: 900_000),
            state: .failed
        )
    }
}
