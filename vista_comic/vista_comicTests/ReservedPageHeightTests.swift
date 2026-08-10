//
//  ReservedPageHeightTests.swift
//  vista_comicTests
//
//  Coverage for `reader-page-prefetch` ticket 03 at the *reader* level: which
//  proportions a row reserves its height from, and the chapter median that
//  stands in for a Page never yet decoded.
//
//  The cache's half of the ticket — that a Page's proportions outlive both
//  eviction and a memory warning — is asserted in `PageImageCacheTests`, which
//  already owns the stubbed transport needed to put a real image through the
//  real fetch path. Splitting them that way keeps this file free of any
//  networking, so it stays a test of the arithmetic the reader does.
//
//  The two functions under test are free functions in `ComicView.swift` for
//  the same reason `readerStartIndex` and `readerPassedBottom` are.
//

import Foundation
import Testing

@testable import vista_comic

@Suite("Reserved page height")
struct ReservedPageHeightTests {

    // MARK: - Which proportions answer

    @Test("A page decoded before reserves its own exact height")
    func recordedRatioWins() {
        // Its own proportions beat the chapter median, which is what makes a
        // page seen once stop moving for good.
        #expect(
            reservedPageHeight(width: 900, recordedHeightRatio: 2.0, chapterHeightRatio: 1.5) == 1800
        )
    }

    @Test("A page never decoded reserves the chapter's median")
    func chapterRatioStandsIn() {
        #expect(
            reservedPageHeight(width: 900, recordedHeightRatio: nil, chapterHeightRatio: 1.5) == 1350
        )
    }

    @Test("A chapter with nothing decoded falls back to the library default")
    func libraryDefaultStandsIn() {
        let height = reservedPageHeight(width: 900, recordedHeightRatio: nil, chapterHeightRatio: nil)
        #expect(height == 900 * defaultPageHeightRatio)
        // The measured library median, not an invented number: pages 900px
        // wide with a median height of 1549px.
        #expect(height == 1549)
    }

    @Test("The default is far closer to a real page than the old fixed placeholder")
    func defaultBeatsTheOldPlaceholder() {
        // The 220pt placeholder is the whole cause of the collapse this ticket
        // exists to stop: on an iPad it under-reserves a page by roughly an
        // order of magnitude, and every row that recycles takes that much
        // height out of the content.
        let reserved = try! #require(
            reservedPageHeight(width: 820, recordedHeightRatio: nil, chapterHeightRatio: nil)
        )
        #expect(reserved > 1200)
    }

    @Test("Before the first layout there is no width to reserve against")
    func noWidthMeansNoReservation() {
        #expect(reservedPageHeight(width: 0, recordedHeightRatio: 2.0, chapterHeightRatio: 1.5) == nil)
    }

    @Test("A degenerate ratio never reaches the layout")
    func nonPositiveRatioIsRejected() {
        #expect(reservedPageHeight(width: 900, recordedHeightRatio: 0, chapterHeightRatio: nil) == nil)
    }

    // MARK: - The chapter median

    @Test("The median of an odd number of known pages is the middle one")
    func medianOfOdd() {
        #expect(medianHeightRatio(of: [1.0, 3.0, 2.0]) == 2.0)
    }

    @Test("The median of an even number of known pages averages the middle pair")
    func medianOfEven() {
        #expect(medianHeightRatio(of: [1.0, 2.0, 3.0, 4.0]) == 2.5)
    }

    @Test("A chapter with nothing decoded has no median")
    func medianOfNothing() {
        #expect(medianHeightRatio(of: []) == nil)
    }

    @Test("The median ignores a run of outliers a mean would follow")
    func medianResistsOutliers() {
        // Page heights in this library span 8px to 2500px. A couple of thin
        // slices among ordinary pages must not drag what an undecoded row
        // guesses at — which is the reason this is a median and not a mean.
        let ratios: [CGFloat] = [1.7, 1.7, 1.7, 1.7, 1.7, 0.05, 0.05]
        let mean = ratios.reduce(0, +) / CGFloat(ratios.count)

        #expect(medianHeightRatio(of: ratios) == 1.7)
        #expect(mean < 1.3)
    }

    @Test("A degenerate ratio is not counted in the median")
    func medianSkipsDegenerateRatios() {
        #expect(medianHeightRatio(of: [0, 2.0, 0, 2.0]) == 2.0)
    }
}
