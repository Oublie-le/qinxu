import Foundation
import CoreText
import SwiftUI

/// Bravura 1.482, an unmodified SIL-OFL font. SMuFL uses four staff spaces per em.
enum NotationFont {
    enum Glyph: UInt16 {
        case brace = 0xE000, trebleClef = 0xE050, bassClef = 0xE062
        case timeSigFour = 0xE084
        case wholeHead = 0xE0A2, halfHead = 0xE0A3, blackHead = 0xE0A4
        case dot = 0xE1E7
        case eighthUp = 0xE240, eighthDown = 0xE241
        case sixteenthUp = 0xE242, sixteenthDown = 0xE243
        case thirtySecondUp = 0xE244, thirtySecondDown = 0xE245
        case eighthUpShort = 0xF410, sixteenthUpShort = 0xF413
        case flat = 0xE260, natural = 0xE261, sharp = 0xE262
        case doubleSharp = 0xE263, doubleFlat = 0xE264
    }

    static var resourceURL: URL? {
        #if SWIFT_PACKAGE
        // A packaged Mac preview keeps SwiftPM resources in the standard Resources folder.
        let bundle = Bundle.main.resourceURL
            .flatMap { Bundle(url: $0.appendingPathComponent("QinXu_QinXuApp.bundle")) } ?? Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: "Bravura", withExtension: "otf", subdirectory: "Resources/Fonts")
            ?? bundle.url(forResource: "Bravura", withExtension: "otf", subdirectory: "Fonts")
    }

    private static let registeredFont: CTFont? = {
        guard let url = resourceURL else { return nil }
        // Static initialization registers once per process and is safe across Canvas renders.
        // A previously registered copy is fine; verify the actual font, never use a fallback.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let font = CTFontCreateWithName("Bravura" as CFString, 40, nil)
        guard CTFontCopyPostScriptName(font) as String == "Bravura" else { return nil }
        return font
    }()

    static var isAvailable: Bool { registeredFont != nil }
    static func textFont(size: CGFloat) -> Font {
        _ = registeredFont
        return .custom("Bravura", fixedSize: size)
    }

    private static let outlines: [UInt16: CGPath] = {
        guard let font = registeredFont else { return [:] }
        let codes: [UInt16] = [0xE000, 0xE050, 0xE062, 0xE0A2, 0xE0A3, 0xE0A4, 0xE1E7, 0xF410, 0xF413]
            + Array(0xE080...0xE089) + Array(0xE240...0xE245) + Array(0xE260...0xE264)
        var result: [UInt16: CGPath] = [:]
        for code in codes {
            var character = UniChar(code), glyph = CGGlyph(0)
            if CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
               let path = CTFontCreatePathForGlyph(font, glyph, nil) { result[code] = path }
        }
        return result
    }()

    static func path(_ glyph: Glyph) -> CGPath? { outlines[glyph.rawValue] }
    static func bounds(_ glyph: Glyph) -> CGRect { path(glyph)?.boundingBoxOfPath ?? .zero }

    /// Draw at the SMuFL baseline/origin, avoiding text line-box centering errors.
    /// Outlines are the font's actual glyphs; only staff lines and stems are primitives.
    static func draw(_ glyph: Glyph, in context: GraphicsContext, at origin: CGPoint, color: Color) {
        draw(code: glyph.rawValue, in: context, at: origin, color: color)
    }

    private static func draw(code: UInt16, in context: GraphicsContext, at origin: CGPoint, color: Color) {
        guard let path = outlines[code] else { return }
        var glyphContext = context
        glyphContext.translateBy(x: origin.x, y: origin.y)
        glyphContext.scaleBy(x: 1, y: -1)
        glyphContext.fill(Path(path), with: .color(color))
    }

    static func drawTimeNumber(_ number: Int, in context: GraphicsContext, centeredAt point: CGPoint, color: Color) {
        let codes = String(number).compactMap { $0.wholeNumberValue }.map { UInt16(0xE080 + $0) }
        let widths = codes.map { (outlines[$0]?.boundingBoxOfPath.width ?? 12) + 1 }
        var x = point.x - (widths.reduce(0, +) - 1) / 2
        for (index, code) in codes.enumerated() {
            let bounds = outlines[code]?.boundingBoxOfPath ?? .zero
            // SMuFL time-signature digits are centered on their baseline, unlike
            // ordinary text digits. Position their visible boxes in each staff half.
            draw(code: code, in: context, at: CGPoint(x: x - bounds.minX, y: point.y + bounds.midY), color: color)
            x += widths[index]
        }
    }
}
