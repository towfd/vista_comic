//
//  AppTheme.swift
//  vista_comic
//
//  Minimum shared visual tokens needed by more than one screen (M1).
//  Colors already live in the asset catalog (primaryRed, grayFont);
//  this file only collects the repeated font styles so multiple screens
//  stay visually consistent.
//

import SwiftUI

enum AppFont {
    /// Large screen titles, e.g. the library header and comic title.
    static let title = Font.system(size: 36, weight: .bold)
    /// Primary label inside a list row.
    static let rowTitle = Font.system(size: 14, weight: .bold)
    /// Secondary / caption text inside a list row.
    static let caption = Font.system(size: 12)
    /// Something the reader is meant to sit and read, rather than scan in a
    /// list — a sentence in a practice question, a heading on a card.
    ///
    /// Added because there was nothing between `rowTitle` (14, a list row) and
    /// `title` (36, a screen heading), so a practice prompt had to borrow the
    /// list-row size and came out too small to read comfortably.
    static let prompt = Font.system(size: 22, weight: .semibold)
    /// A single figure meant to be read at a glance — a count on a card.
    static let statistic = Font.system(size: 28, weight: .bold)
}
