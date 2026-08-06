//
//  ComprehensionRow.swift
//  vista_comic
//
//  One row in 歷史紀錄's list (`comprehension-response-ux` ticket 19). Placed
//  under `Features/<Tab>/components/`, matching `ComicListView`'s own placement
//  and its `AppFont` token usage.
//
//  Unlike `SavedTranslationRow` — which showed a short list of things the
//  reader deliberately kept, and could afford an expandable disclosure per row
//  — this list fills up on its own, so scanning is what matters. Two compact
//  lines, no disclosure, no per-row actions: the whole record is one tap away
//  on the detail screen, and actions are the next ticket.
//
//  **The translation is deliberately not on the row.** Ticket 19's AC read
//  "rows show the cloud translation where present, the on-device one
//  otherwise", which contradicted the Variant B mockup the ticket was drawn
//  from ("everything else — translation, notes, source jump, retry, delete —
//  lives on a detail screen"). Resolved in favour of the mockup: a third line
//  per row costs roughly a third of the records visible per screen, on a list
//  whose whole job is scanning. The AC's intent survives in the status line's
//  glyph, which is a cloud exactly when a cloud translation exists — so the row
//  still says *that* the cloud version is there without repeating it in full.
//
//  Stays a "dumb" row per CLAUDE.md: it renders what it is given and reports
//  nothing back. Even marking read belongs to the detail screen, because
//  opening is what "read" means.
//

import SwiftUI

struct ComprehensionRow: View {
    let record: ComprehensionRecord

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Reserved whether or not it is filled, so rows don't jog
            // horizontally as explanations land while the list is on screen.
            Circle()
                .fill(record.isUnreadExplanation ? Color.primaryRed : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                // The source text, not the translation: it is what the reader
                // selected, so it is what they recognise the record by. The
                // translation lives on the detail screen — see this file's
                // header for why the row stops here.
                Text(record.sourceText)
                    .font(AppFont.rowTitle)
                    .lineLimit(1)

                statusLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var statusLine: some View {
        HStack(spacing: 4) {
            Image(systemName: record.rowStatus.symbolName)
            // Titles, never the raw stable ids: those are path hashes (ADR-0003)
            // and unusable as labels. `nil` means the comic has left the
            // library, which the em dash states plainly rather than hiding.
            Text(sourceLabel)
                .lineLimit(1)
            Text("·")
            Text(record.createdAt, format: .relative(presentation: .named))
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(.grayFont)
    }

    private var sourceLabel: String {
        switch (record.comicTitle, record.chapterTitle) {
        case (let comic?, let chapter?): return "\(comic) · \(chapter)"
        case (let comic?, nil): return comic
        default: return "—"
        }
    }
}

#Preview("States") {
    VStack(alignment: .leading, spacing: 16) {
        ComprehensionRow(record: .preview(status: "ok", notes: "…", isRead: false))
        ComprehensionRow(record: .preview(status: "ok", notes: "…", isRead: true))
        ComprehensionRow(record: .preview(status: "pending"))
        ComprehensionRow(record: .preview(status: "declined"))
        ComprehensionRow(record: .preview(status: "failed"))
        ComprehensionRow(record: .preview(status: "ok", notes: "…", comicTitle: nil))
    }
    .padding()
}
