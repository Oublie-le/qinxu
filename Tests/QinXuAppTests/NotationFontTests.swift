import Foundation
import Testing
@testable import QinXuApp

@Suite struct NotationFontTests {
    @Test func bundledBravuraRegistersAndContainsAllPracticeGlyphs() throws {
        let url = try #require(NotationFont.resourceURL)
        #expect(url.pathExtension == "otf")
        #expect(NotationFont.isAvailable)
        let glyphs: [NotationFont.Glyph] = [
            .brace, .trebleClef, .bassClef, .timeSigFour, .wholeHead, .halfHead, .blackHead,
            .flat, .natural, .sharp, .doubleFlat, .doubleSharp, .dot,
            .eighthUp, .eighthDown, .sixteenthUp, .sixteenthDown,
            .thirtySecondUp, .thirtySecondDown, .eighthUpShort, .sixteenthUpShort
        ]
        for glyph in glyphs {
            let outline = try #require(NotationFont.path(glyph))
            #expect(!outline.isEmpty)
            #expect(outline.boundingBoxOfPath.width > 0)
            #expect(outline.boundingBoxOfPath.height > 0)
        }
        // Bravura's published SMuFL metrics, at 10 points per staff space.
        // A system-font fallback or missing-glyph box must not pass this check.
        #expect(abs(NotationFont.bounds(.blackHead).width - 11.8) < 0.1)
        #expect(abs(NotationFont.bounds(.blackHead).height - 10) < 0.1)
        #expect(NotationFont.bounds(.trebleClef).height > 65)
        #expect(abs(NotationFont.bounds(.timeSigFour).height - 20) < 0.1)
    }
}
