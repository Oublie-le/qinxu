#if DEBUG && os(iOS)
import CoreGraphics
import Foundation
import SheetMusicCore
import SheetMusicPDF
import UIKit

@MainActor
enum UITestImageScoreFixture {
    static func importPages(into store: ImportedDocumentStore) throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("QinXu-ImageScore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let blank = folder.appendingPathComponent("1.png")
        let engraving = folder.appendingPathComponent("2.png")
        try png(width: 64, height: 64) { _ in }.write(to: blank)
        try scorePagePNG().write(to: engraving)
        _ = try store.importImages(from: [blank, engraving], title: "图片识谱测试谱")
    }

    private static func scorePagePNG() throws -> Data {
        let pdfData = try PDFExporter.export(score: grandStaff(), options: .init(staffSize: .explicit(24)))
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let document = CGPDFDocument(provider), document.numberOfPages == 1,
              let page = document.page(at: 1) else { throw CocoaError(.fileReadCorruptFile) }
        let bounds = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 300.0 / 72.0
        return try png(width: Int(ceil(bounds.width * scale)), height: Int(ceil(bounds.height * scale))) { bitmap in
            bitmap.scaleBy(x: scale, y: scale)
            bitmap.translateBy(x: -bounds.minX, y: -bounds.minY)
            bitmap.drawPDFPage(page)
        }
    }

    private static func png(width: Int, height: Int, draw: (CGContext) -> Void) throws -> Data {
        guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(bitmap)
        guard let image = bitmap.makeImage(), let data = UIImage(cgImage: image).pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    /// Same original two-measure engraving used by the converter's raster regression.
    private static func grandStaff() -> SheetMusicCore.Score {
        func header(_ clef: String) -> [VoiceElement] {
            [.clef(Clef(concertClefType: clef)), .timeSignature(TimeSignature(numerator: 4, denominator: 4))]
        }
        func note(_ pitch: Int, _ tpc: Int, _ duration: NoteDuration) -> VoiceElement {
            .chord(Chord(duration: duration, notes: [Note(pitch: pitch, tpc: tpc)]))
        }
        let upper = Staff(defaultClefType: "G", brackets: [BracketItem(type: .brace, span: 2)], measures: [
            Measure(voices: [Voice(elements: header("G") + [
                note(72, 14, .quarter), note(74, 16, .quarter), note(76, 18, .quarter), note(77, 13, .quarter),
            ])]),
            Measure(voices: [Voice(elements: [note(79, 15, .half), note(77, 13, .half)])]),
        ])
        let lower = Staff(defaultClefType: "F", measures: [
            Measure(voices: [Voice(elements: header("F") + [note(48, 14, .whole)])]),
            Measure(voices: [Voice(elements: [note(43, 15, .whole)])]),
        ])
        var score = SheetMusicCore.Score(division: 480, parts: [
            Part(id: "P1", instrument: Instrument(id: "piano"), staves: [upper, lower]),
        ], systemMeasures: [SystemMeasure(), SystemMeasure()])
        var allocator = EIDAllocator(actor: 17)
        score.assignMissingIDs(using: &allocator)
        return score
    }
}
#endif
