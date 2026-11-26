import Foundation
import SwiftUI
import Testing
import PDFKit
import QinXuCore
@testable import QinXuApp

#if os(macOS)
import AppKit

extension PracticeRenderingTests {
    @Test(arguments: [667, 1194], [false, true])
    func importedPagesKeepGlobalClickAndReadableViewport(width: Int, images: Bool) async throws {
        let height = width == 667 ? 375 : 834
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var now: TimeInterval = 0
        let model = PracticeViewModel(storage: LocalLibraryStore(url: directory.appendingPathComponent("library.json")),
                                      clock: { now }, automaticTimer: false, deviceAccessEnabled: false)
        let source = try #require(BundledBook.beyer.loadDocument())
        let page = try #require(source.page(at: 10))
        let document: ImportedReadingDocument
        if images {
            let thumbnail = page.thumbnail(of: CGSize(width: 600, height: 850), for: .cropBox)
            let imageData = try #require(thumbnail.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: imageData))
            let file = directory.appendingPathComponent("page.png")
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: file)
            document = try await model.documentLibrary.importImages(from: [file], title: "图片跟拍练习")
        } else {
            let selectedPages = PDFDocument()
            selectedPages.insert(page, at: 0)
            let file = directory.appendingPathComponent("page.pdf")
            try #require(selectedPages.write(to: file))
            document = try await model.documentLibrary.importPDF(from: file, title: "PDF 跟拍练习")
        }
        model.togglePlayback()
        #expect(model.isPlaying)
        let reader = ImportedDocumentReaderView(model: model, document: document, compact: width == 667)
            .frame(width: CGFloat(width), height: CGFloat(height))
        let host = NSHostingView(rootView: reader.environment(\.colorScheme, .light))
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if findImportedPDF(in: host)?.currentPage != nil { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let pdf = try #require(findImportedPDF(in: host))
        #expect(pdf.document?.pageCount == 1)
        #expect(pdf.bounds.width > CGFloat(width - 40))
        #expect(pdf.bounds.height >= (width == 667 ? 180 : 550))
        #expect(!model.isPlaying, "Reading must not leave the unrelated selected score evaluating input.")
        #expect(model.updateMetronomeSettings(.init(beatsPerMeasure: 3, tempoBPM: 90, clickNote: .eighth)))
        model.toggleMetronome()
        now = 0.75
        model.tick()
        #expect(model.metronomeRunning && model.metronomeBeat == 2 && model.metronomeSubdivision == 1)
        #expect(!model.showingMetronomeSettings, "Reader settings use their own presentation, not Home's sheet flag.")
        window.contentView = nil
        #expect(model.metronomeRunning, "Closing the reader must preserve the independent global click.")
        model.toggleMetronome()
        #expect(!model.metronomeRunning)
        #expect(model.engine.correctCount == 0 && model.engine.wrongCount == 0)
    }

    private func findImportedPDF(in view: NSView) -> PDFView? {
        if let pdf = view as? PDFView { return pdf }
        return view.subviews.lazy.compactMap { findImportedPDF(in: $0) }.first
    }
}
#endif
