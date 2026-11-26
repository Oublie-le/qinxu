import Foundation
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import Testing
import QinXuCore
import SheetMusicCore
import SheetMusicPDF
import UniformTypeIdentifiers
@testable import QinXuApp

@Suite(.serialized) @MainActor struct PDFScoreConverterTests {
    private struct Event: Equatable, CustomStringConvertible {
        let midi: Int
        let staff: Int
        let start: Double
        let duration: Double
        var description: String { "\(midi)/staff\(staff)@\(start)+\(duration)" }
    }

    private var expected: [Event] {
        [Event(midi: 72, staff: 1, start: 0, duration: 1),
         Event(midi: 74, staff: 1, start: 1, duration: 1),
         Event(midi: 76, staff: 1, start: 2, duration: 1),
         Event(midi: 77, staff: 1, start: 3, duration: 1),
         Event(midi: 79, staff: 1, start: 4, duration: 2),
         Event(midi: 77, staff: 1, start: 6, duration: 2),
         Event(midi: 48, staff: 2, start: 0, duration: 4),
         Event(midi: 43, staff: 2, start: 4, duration: 4)]
    }

    private func events(_ score: PianoScore) -> [Event] {
        score.notes.map { Event(midi: $0.midi, staff: $0.staff, start: $0.startBeat, duration: $0.durationBeats) }
            .sorted { ($0.staff, $0.start, $0.midi) < ($1.staff, $1.start, $1.midi) }
    }

    /// Original test music, constructed here rather than borrowing an upstream
    /// score fixture. The upstream exporter supplies genuine engraved glyphs,
    /// barlines and a brace; recognition receives only its PDF bytes.
    private func knownGrandStaffPDF() throws -> Data {
        let trebleHeader: [VoiceElement] = [
            .clef(Clef(concertClefType: "G")),
            .timeSignature(TimeSignature(numerator: 4, denominator: 4)),
        ]
        let bassHeader: [VoiceElement] = [
            .clef(Clef(concertClefType: "F")),
            .timeSignature(TimeSignature(numerator: 4, denominator: 4)),
        ]
        func note(_ pitch: Int, _ tpc: Int, _ duration: NoteDuration) -> VoiceElement {
            .chord(Chord(duration: duration, notes: [Note(pitch: pitch, tpc: tpc)]))
        }
        let upper = Staff(defaultClefType: "G", brackets: [BracketItem(type: .brace, span: 2)], measures: [
            Measure(voices: [Voice(elements: trebleHeader + [
                note(72, 14, .quarter), note(74, 16, .quarter), note(76, 18, .quarter), note(77, 13, .quarter),
            ])]),
            Measure(voices: [Voice(elements: [note(79, 15, .half), note(77, 13, .half)])]),
        ])
        let lower = Staff(defaultClefType: "F", measures: [
            Measure(voices: [Voice(elements: bassHeader + [note(48, 14, .whole)])]),
            Measure(voices: [Voice(elements: [note(43, 15, .whole)])]),
        ])
        var score = SheetMusicCore.Score(division: 480, parts: [
            Part(id: "P1", instrument: Instrument(id: "piano"), staves: [upper, lower]),
        ], systemMeasures: [SystemMeasure(), SystemMeasure()])
        var allocator = EIDAllocator(actor: 17)
        score.assignMissingIDs(using: &allocator)
        if #available(macOS 15.0, *) {
            return try PDFExporter.export(score: score, options: .init(staffSize: .explicit(24)))
        }
        throw FixtureFailure.unavailableExporter
    }

    private enum FixtureFailure: Error { case unavailableExporter }

    /// A second engraving of the same original music, using ordinary embedded
    /// Bravura text glyphs (including its visible grand-staff brace). There is no
    /// hidden score metadata. The upstream exporter above outlines its brace;
    /// its vector importer currently groups only glyph-based braces, as emitted
    /// by notation programs such as MuseScore. Keep the raster fixture separate
    /// so neither route can use the other's representation as an answer key.
    private func glyphGrandStaffPDF() throws -> Data {
        #expect(NotationFont.isAvailable)
        let font = CTFontCreateWithName("Bravura" as CFString, 24, nil)
        #expect(CTFontCopyPostScriptName(font) as String == "Bravura")
        let data = NSMutableData(), consumer = try #require(CGDataConsumer(data: data))
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.textMatrix = .identity

        func glyph(_ code: UInt16) throws -> CGGlyph {
            var character = UniChar(code), value = CGGlyph(0)
            try #require(CTFontGetGlyphsForCharacters(font, &character, &value, 1))
            return value
        }
        func draw(_ code: UInt16, at point: CGPoint) throws {
            var value = try glyph(code), position = point
            CTFontDrawGlyphs(font, &value, &position, 1, context)
        }
        func line(_ from: CGPoint, _ to: CGPoint, width: CGFloat = 0.5) {
            context.setLineWidth(width)
            context.move(to: from); context.addLine(to: to); context.strokePath()
        }
        // Coordinates are ordinary engraving geometry in PDF points, with a
        // six-point staff space; they do not come from recognition output.
        for bottom: CGFloat in [630, 700] {
            for i in 0..<5 {
                let y = bottom + CGFloat(i) * 6
                line(CGPoint(x: 60, y: y), CGPoint(x: 535, y: y))
            }
            for center: CGFloat in [bottom + 6, bottom + 18] {
                var number = try glyph(0xE084)
                let bounds = CTFontGetBoundingRectsForGlyphs(font, .default, &number, nil, 1)
                try draw(0xE084, at: CGPoint(x: 105, y: center - bounds.midY))
            }
        }
        for x: CGFloat in [60, 340, 535] {
            line(CGPoint(x: x, y: 630), CGPoint(x: x, y: 724), width: 0.8)
        }
        try draw(0xE050, at: CGPoint(x: 68, y: 706)) // G clef on G4.
        try draw(0xE062, at: CGPoint(x: 68, y: 648)) // F clef on F3.
        var brace = try glyph(0xE000)
        let braceBounds = CTFontGetBoundingRectsForGlyphs(font, .default, &brace, nil, 1)
        try #require(braceBounds.height > 0)
        context.saveGState()
        context.translateBy(x: 48, y: 630)
        context.scaleBy(x: 1, y: 94 / braceBounds.height)
        var bracePosition = CGPoint(x: -braceBounds.minX, y: -braceBounds.minY)
        CTFontDrawGlyphs(font, &brace, &bracePosition, 1, context)
        context.restoreGState()
        for (x, y): (CGFloat, CGFloat) in [(150, 715), (200, 718), (250, 721), (300, 724)] {
            try draw(0xE0A4, at: CGPoint(x: x, y: y))
            line(CGPoint(x: x + 0.2, y: y), CGPoint(x: x + 0.2, y: y - 21), width: 0.7)
        }
        for (x, y): (CGFloat, CGFloat) in [(385, 727), (460, 724)] {
            try draw(0xE0A3, at: CGPoint(x: x, y: y))
            line(CGPoint(x: x + 0.2, y: y), CGPoint(x: x + 0.2, y: y - 21), width: 0.7)
        }
        try draw(0xE0A2, at: CGPoint(x: 150, y: 639)) // C3 whole note.
        try draw(0xE0A2, at: CGPoint(x: 385, y: 630)) // G2 whole note.
        context.endPDFPage(); context.closePDF()
        return data as Data
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("qinxu-pdf-convert-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func rasterImage(_ page: CGPDFPage) throws -> CGImage {
        let bounds = page.getBoxRect(.mediaBox), scale = 300.0 / 72.0
        let width = Int(ceil(bounds.width * scale)), height = Int(ceil(bounds.height * scale))
        let bitmap = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        bitmap.scaleBy(x: scale, y: scale)
        bitmap.translateBy(x: -bounds.minX, y: -bounds.minY)
        bitmap.drawPDFPage(page)
        return try #require(bitmap.makeImage())
    }

    private func writePNG(of pdf: Data, to url: URL) throws {
        let provider = try #require(CGDataProvider(data: pdf as CFData))
        let page = try #require(CGPDFDocument(provider)?.page(at: 1))
        let image = try rasterImage(page)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
    }

    /// The new PDF contains only one raster image per page: no hidden vector
    /// notation or OCR text survives to let the vector importer answer for OMR.
    private func rasterOnlyPDF(_ vector: Data) throws -> Data {
        let provider = try #require(CGDataProvider(data: vector as CFData))
        let original = try #require(CGPDFDocument(provider))
        let output = NSMutableData(), consumer = try #require(CGDataConsumer(data: output))
        let target = try #require(CGContext(consumer: consumer, mediaBox: nil, nil))
        for index in 1...original.numberOfPages {
            let page = try #require(original.page(at: index))
            let image = try rasterImage(page)
            var box = CGRect(origin: .zero, size: page.getBoxRect(.mediaBox).size)
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            target.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            target.draw(image, in: box)
            target.endPDFPage()
        }
        target.closePDF()
        return output as Data
    }

    private func assertExpected(_ result: PDFScoreConversionResult) throws {
        #expect(result.score.measures.count == 2)
        #expect(events(result.score) == expected)
        let xml = try CompressedMusicXML.scoreData(from: result.archive)
        let imported = try QinXuCore.MusicXMLParser().parse(data: xml)
        #expect(events(imported) == expected)
        #expect(imported.measures.count == 2)
        #expect(imported.title == "原创双手测试")
    }

    @Test func vectorPDFRecognizesBothHandsAndPreservesExactTimingThroughMXL() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("vector.pdf"), data = try glyphGrandStaffPDF()
        try data.write(to: source)
        #expect(PDFDocument(data: data)?.pageCount == 1)
        let result = try await PDFScoreConverter.convert(pdfURL: source, pages: 1...1, title: "原创双手测试")
        try assertExpected(result)
        #expect(try Data(contentsOf: source) == data)
    }

    @Test func rasterPDFUsesRealModelAndMatchesKnownSimpleGrandStaff() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("raster.pdf"), data = try rasterOnlyPDF(knownGrandStaffPDF())
        try data.write(to: source)
        #expect(PDFDocument(data: data)?.pageCount == 1)
        let result = try await PDFScoreConverter.convert(pdfURL: source, pages: 1...1, title: "原创双手测试")
        try assertExpected(result)
        #expect(try Data(contentsOf: source) == data)
    }

    @Test func importedImagePageConvertsToMXLWithoutChangingTheAlbum() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let blank = folder.appendingPathComponent("blank.png"), sheet = folder.appendingPathComponent("score.png")
        try writePNG(of: blankPDF(size: CGSize(width: 60, height: 60)), to: blank)
        try writePNG(of: knownGrandStaffPDF(), to: sheet)
        let store = ImportedDocumentStore(libraryURL: folder.appendingPathComponent("library.json"))
        let album = try store.importImages(from: [blank, sheet], title: "图片谱")
        let pages = try (0..<album.pageCount).map { try store.fileURL(for: album, pageIndex: $0) }
        let before = try pages.map { try Data(contentsOf: $0) }
        let result = try await PDFScoreConverter.convert(document: album, store: store, pages: 2...2, title: "原创双手测试")
        try assertExpected(result)
        #expect(store.load().documents == [album])
        #expect(try pages.map { try Data(contentsOf: $0) } == before)
    }

    private func blankPDF(pages: Int = 1, size: CGSize = CGSize(width: 595, height: 842)) throws -> Data {
        let data = NSMutableData(), consumer = try #require(CGDataConsumer(data: data))
        var box = CGRect(origin: .zero, size: size)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0..<pages { context.beginPDFPage(nil); context.endPDFPage() }
        context.closePDF()
        return data as Data
    }

    @Test func invalidPageSelectionsAreRejectedBeforeRecognitionAndPreserveSource() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("range.pdf"), count = PDFScoreConverter.maximumPages + 1
        let data = try blankPDF(pages: count)
        try data.write(to: source)
        for range in [0...1, 1...(count + 1), 1...count] {
            do {
                _ = try await PDFScoreConverter.convert(pdfURL: source, pages: range, title: "bad range")
                Issue.record("Expected page-range rejection")
            } catch {
                #expect(error.localizedDescription.contains("范围"))
            }
        }
        #expect(try Data(contentsOf: source) == data)
    }

    @Test func malformedPDFAndExcessivePageGeometryFailWithoutProducingScore() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("invalid.pdf")
        for (data, message) in [(Data("not a PDF".utf8), "无法打开"),
                                (try blankPDF(size: CGSize(width: 20_000, height: 20_000)), "页面尺寸")] {
            try data.write(to: source)
            do {
                _ = try await PDFScoreConverter.convert(pdfURL: source, pages: 1...1, title: "invalid")
                Issue.record("Expected invalid PDF rejection")
            } catch {
                #expect(error.localizedDescription.contains(message))
            }
            #expect(try Data(contentsOf: source) == data)
        }
    }

    @Test func cancelledRequestCannotReturnAnImportableResult() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("cancel.pdf")
        try blankPDF().write(to: source)
        let request = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PDFScoreConverter.convert(pdfURL: source, pages: 1...1, title: "cancelled")
        }
        do { _ = try await request.value; Issue.record("Cancelled conversion returned a score") }
        catch is CancellationError { }
        catch { Issue.record("Expected cancellation, received \(error)") }
    }

}
