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
}
