import Foundation
import PDFKit
import QinXuCore
import SheetMusicCore
import SheetMusicOMRModel
import SheetMusicPDF

struct PDFScoreConversionResult: Sendable {
    let archive: Data
    let score: PianoScore
    let diagnostics: [String]
}

enum PDFScoreConverter {
    static let maximumPages = 4

    /// Page numbers are one-based, as shown in the reader.
    static func convert(pdfURL: URL, pages: ClosedRange<Int>, title: String) async throws -> PDFScoreConversionResult {
        try await PDFScoreRecognition.shared.convert(pdfURL: pdfURL, pages: pages, title: title)
    }
}

private actor PDFScoreRecognition {
    static let shared = PDFScoreRecognition()
    private static let renderDPI = 300.0
    private static let maxPixels = 14_000_000.0

    // A single worker keeps an immediate retry from running two expensive
    // PDF/Core ML passes side by side after the first request was cancelled.
    func convert(pdfURL: URL, pages: ClosedRange<Int>, title: String) throws -> PDFScoreConversionResult {
        try Task.checkCancellation()
        return try autoreleasepool {
            let pdf = try selectedPages(pdfURL: pdfURL, pages: pages)
            let observations = RecognitionObservations()
            var options = PDFImportOptions()
            options.omrRenderDPI = Self.renderDPI
            options.diagnostics = { observations.record($0) }
            do {
                options.omrTileClassifier = CancellableClassifier(model: try CoreMLTileClassifier())
            } catch {
                throw ConversionFailure("本机识谱模型未能加载，请重新打开琴序后再试。")
            }
            let recognized: SheetMusicCore.Score
            do {
                recognized = try PDFImporter.parse(pdfData: pdf, options: options)
            } catch {
                try Task.checkCancellation()
                throw ConversionFailure("这几页没有识别出可用的五线谱。请选有完整谱表的清晰页面重试。")
            }
            try Task.checkCancellation()
            // The importer marks a page break on the last measure of each
            // recognized page except the last one. Reject unrecognized pages
            // before their absence could be mistaken for a complete result.
            let pageBreaks = recognized.parts.flatMap(\.staves).map { staff in
                staff.measures.filter(\.pageBreak).count
            }.max() ?? 0
            guard pageBreaks + 1 == pages.count else {
                throw ConversionFailure("部分页面未能识别，请逐页转换并检查原谱。")
            }
            let xml = try RecognizedScoreMusicXML.encode(recognized, title: title)
            let score = try MusicXMLParser().parse(data: xml)
            let archive = try PDFScoreMXLArchive.make(musicXML: xml)
            return PDFScoreConversionResult(archive: archive, score: score, diagnostics: observations.messages)
        }
    }

    private func selectedPages(pdfURL: URL, pages: ClosedRange<Int>) throws -> Data {
        guard let document = PDFDocument(url: pdfURL), !document.isLocked else {
            throw ConversionFailure("无法打开这份 PDF，请检查文件是否损坏或加密。")
        }
        guard pages.lowerBound > 0, pages.upperBound <= document.pageCount,
              pages.count <= PDFScoreConverter.maximumPages else {
            throw ConversionFailure("请在 PDF 范围内选取 1–\(PDFScoreConverter.maximumPages) 页。")
        }
        let selected = PDFDocument()
        for number in pages {
            try Task.checkCancellation()
            guard let page = document.page(at: number - 1),
                  let copy = page.copy() as? PDFPage else {
                throw ConversionFailure("无法读取原谱第 \(number) 页。")
            }
            let size = page.bounds(for: .mediaBox).size
            let width = size.width * Self.renderDPI / 72
            let height = size.height * Self.renderDPI / 72
            guard width.isFinite, height.isFinite, width > 0, height > 0,
                  max(width, height) <= 6_000, width * height <= Self.maxPixels else {
                throw ConversionFailure("原谱第 \(number) 页的页面尺寸过大或无效。")
            }
            selected.insert(copy, at: selected.pageCount)
        }
        guard let data = selected.dataRepresentation(), !data.isEmpty else {
            throw ConversionFailure("所选页面无法读取。")
        }
        return data
    }
}

private struct CancellableClassifier: OMRTileClassifier {
    let model: CoreMLTileClassifier
    var manifest: OMRModelManifest { model.manifest }

    func run(tile: [Float]) throws -> OMRHeadOutputs {
        try Task.checkCancellation()
        return try model.run(tile: tile)
    }
}

private final class RecognitionObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var warnings = 0

    func record(_ diagnostic: PDFImportDiagnostic) {
        if diagnostic.severity == .warning {
            lock.withLock { warnings += 1 }
        }
    }

    var messages: [String] {
        lock.withLock {
            warnings == 0 ? [] : [
                "识谱引擎标出了 \(warnings) 处异常。请重点检查遗漏的音符、小节、谱号和节奏。"
            ]
        }
    }
}

private struct ConversionFailure: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}
