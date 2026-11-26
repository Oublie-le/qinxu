import Foundation
import CoreGraphics
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
        try await PDFScoreRecognition.shared.convert(source: .pdf(pdfURL), pages: pages, title: title)
    }

    static func convert(document: ImportedReadingDocument, store: ImportedDocumentStore,
                        pages: ClosedRange<Int>, title: String) async throws -> PDFScoreConversionResult {
        try validateSelection(pages, pageCount: document.pageCount)
        switch document.kind {
        case .pdf:
            let url = try store.fileURL(for: document)
            return try await convert(pdfURL: url, pages: pages, title: title)
        case .images:
            return try await PDFScoreRecognition.shared.convert(source: .images(document, store), pages: pages, title: title)
        }
    }

    fileprivate static func validateSelection(_ pages: ClosedRange<Int>, pageCount: Int) throws {
        guard pages.lowerBound > 0, pages.upperBound <= pageCount, pages.count <= maximumPages else {
            throw ConversionFailure("请在曲谱范围内选取 1–\(maximumPages) 页。")
        }
    }
}

private actor PDFScoreRecognition {
    enum Source: Sendable {
        case pdf(URL)
        case images(ImportedReadingDocument, ImportedDocumentStore)
    }

    static let shared = PDFScoreRecognition()
    private static let renderDPI = 300.0
    private static let maxPixels = 14_000_000.0

    // A single worker keeps an immediate retry from running two expensive
    // PDF/Core ML passes side by side after the first request was cancelled.
    func convert(source: Source, pages: ClosedRange<Int>, title: String) throws -> PDFScoreConversionResult {
        try Task.checkCancellation()
        return try autoreleasepool {
            let pdf: Data
            switch source {
            case let .pdf(url): pdf = try selectedPages(pdfURL: url, pages: pages)
            case let .images(document, store): pdf = try selectedImages(document, store: store, pages: pages)
            }
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
            try Task.checkCancellation()
            return PDFScoreConversionResult(archive: archive, score: score, diagnostics: observations.messages)
        }
    }

    private func selectedPages(pdfURL: URL, pages: ClosedRange<Int>) throws -> Data {
        guard let document = PDFDocument(url: pdfURL), !document.isLocked else {
            throw ConversionFailure("无法打开这份 PDF，请检查文件是否损坏或加密。")
        }
        try PDFScoreConverter.validateSelection(pages, pageCount: document.pageCount)
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

    private func selectedImages(_ document: ImportedReadingDocument, store: ImportedDocumentStore,
                                pages: ClosedRange<Int>) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              let pdf = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw ConversionFailure("无法准备图片识谱，请重试。")
        }
        for number in pages {
            try Task.checkCancellation()
            try autoreleasepool {
                let image = try store.imagePage(for: document, pageIndex: number - 1)
                let pointsPerPixel = 72.0 / Self.renderDPI
                var box = CGRect(x: 0, y: 0, width: Double(image.width) * pointsPerPixel,
                                 height: Double(image.height) * pointsPerPixel)
                let bounds = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
                pdf.beginPDFPage([kCGPDFContextMediaBox: bounds] as CFDictionary)
                pdf.interpolationQuality = .none
                pdf.draw(image, in: box)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return data as Data
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
