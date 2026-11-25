import Foundation
import SwiftUI
import Testing
import ImageIO
import UniformTypeIdentifiers
import PDFKit
#if os(macOS)
import AppKit
#endif
import QinXuCore
@testable import QinXuApp

#if os(macOS)
/// In-memory SwiftUI rendering; this does not capture the user's desktop or test iOS interaction.
@Suite @MainActor struct PracticeRenderingTests {
    @Test(arguments: [667, 844, 834, 1194])
    func homeRendersAtPhoneAndTabletSizes(width: Int) throws {
        let height = width == 667 ? 375 : width == 844 ? 390 : width == 834 ? 1194 : 834
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = PracticeViewModel(storage: LocalLibraryStore(url: directory.appendingPathComponent("library.json")),
                                      automaticTimer: false, deviceAccessEnabled: false)
        let view = PracticeHomeView(model: model)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .frame(width: CGFloat(width), height: CGFloat(height))
        try render(view, name: "home-\(width)", width: width, height: height)
    }

    @Test(arguments: [393, 834, 1194])
    func scoreRendersAtPhoneAndTabletWidths(width: Int) throws {
        let score = DemoScores.all[1]
        let view = PracticeScoreView(score: score, hand: .both, currentBeat: 0,
                                    expectedNotes: Array(score.notes.prefix(3)), verdicts: [:], active: true)
            .frame(width: CGFloat(width), height: 340)
            .background(QinXuTheme.paper)
        try render(view, name: "score-\(width)", width: width, height: 340)
    }

    @Test(arguments: [393, 834, 1194])
    func keyboardRendersExpectedAndHeldNotes(width: Int) throws {
        let view = PianoKeyboardView(expectedPitches: [60, 64, 67], heldPitches: [64],
                                     hand: .both, interactive: true, press: { _ in }, release: { _ in })
            .frame(width: CGFloat(width), height: 124)
            .background(QinXuTheme.paper)
        try render(view, name: "keyboard-\(width)", width: width, height: 124)
    }

    @Test(arguments: [667, 844, 1194])
    func practiceAndDetailRenderInLandscape(width: Int) throws {
        let height = width == 667 ? 375 : width == 844 ? 390 : 834
        let compact = height < 550
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = PracticeViewModel(storage: LocalLibraryStore(url: directory.appendingPathComponent("library.json")),
                                      automaticTimer: false, deviceAccessEnabled: false)
        let practice = PracticeSessionView(model: model, compact: compact, onExit: {}, onShowDevices: {})
            .frame(width: CGFloat(width - 63), height: CGFloat(height))
        try render(practice, name: "practice-\(width)", width: width - 63, height: height)
        let detail = ScoreDetailView(model: model, score: DemoScores.all[1], compact: compact,
                                    onBack: {}, onPractice: {}, onCover: {})
            .padding(compact ? 12 : 24)
            .frame(width: CGFloat(width - 63), height: CGFloat(height))
            .background(QinXuTheme.background)
        try render(detail, name: "detail-\(width)", width: width - 63, height: height)
    }

    @Test(arguments: [667, 1194])
    func bundledBookOpensAllPagesAndRendersReader(width: Int) async throws {
        let book = BundledBook.beyer
        let document = try #require(book.loadDocument())
        #expect(document.pageCount == 88)
        #expect(document.page(at: 0) != nil)
        #expect(document.page(at: 87) != nil)
        let height = width == 667 ? 390 : 834
        let reader = BookReaderView(book: book, compact: width == 667)
            .frame(width: CGFloat(width), height: CGFloat(height))
        let host = NSHostingView(rootView: reader.environment(\.colorScheme, .light))
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        // PDFKit schedules its document layout and tiled drawing after attachment.
        // Keep this window offscreen; only capture our view, never the user's desktop.
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        var pdfInk = 0
        repeat {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if let pdf = findPDFView(in: host), pdf.bounds.width > 40, pdf.bounds.height > 24,
               let page = pdf.currentPage {
                let pageWidth = pdf.convert(page.bounds(for: .cropBox), from: page).width
                // Wait for the reader's asynchronous width-fit to finish, not a fixed delay.
                if pageWidth <= pdf.bounds.width, pageWidth > pdf.bounds.width * 0.9 {
                    let bounds = pdf.bounds.insetBy(dx: 20, dy: 12)
                    let image = try nativePDFSnapshot(pdf, bounds: bounds)
                    pdfInk = try darkPixelCount(image, width: Int(bounds.width), height: Int(bounds.height))
                }
            }
            if pdfInk > 500 { break }
            try await Task.sleep(for: .milliseconds(25))
        } while ContinuousClock.now < deadline
        #expect(pdfInk > 500, "PDF page content must render; header and page-number text do not count.")
        let pdf = try #require(findPDFView(in: host))
        #expect(!pdf.visiblePages.isEmpty)
        #expect(pdf.scaleFactor > 0)
        try checkAndSave(nativePDFSnapshot(pdf, bounds: pdf.bounds), name: "beyer-pages-\(width)",
                         width: Int(pdf.bounds.width), height: Int(pdf.bounds.height))
    }

    private func findPDFView(in view: NSView) -> PDFView? {
        if let pdf = view as? PDFView { return pdf }
        return view.subviews.lazy.compactMap { findPDFView(in: $0) }.first
    }

    private func nativePDFSnapshot(_ view: NSView, bounds: CGRect) throws -> CGImage {
        // cacheDisplay and CALayer.render omit PDFKit's tiled page content, even after
        // layout. AppKit's native PDF drawing captures the same view's visible region.
        // This is an offscreen drawing check, not an iOS interaction or desktop capture.
        let drawing = try #require(PDFDocument(data: view.dataWithPDF(inside: bounds)))
        #expect(drawing.pageCount == 1)
        let page = try #require(drawing.page(at: 0))
        let thumbnail = page.thumbnail(of: CGSize(width: bounds.width * 2, height: bounds.height * 2), for: .cropBox)
        return try #require(thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    func render<V: View>(_ view: V, name: String, width: Int, height: Int) throws {
        // ImageRenderer excludes native ScrollView content. Render our own in-memory view instead.
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        try render(host, name: name, width: width, height: height)
    }

    private func render(_ host: NSView, name: String, width: Int, height: Int) throws {
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = try #require(bitmap.cgImage)
        try checkAndSave(image, name: name, width: width, height: height)
    }

    private func checkAndSave(_ image: CGImage, name: String, width: Int, height: Int) throws {
        #expect(image.width >= width)
        #expect(image.width % width == 0)
        #expect(image.height * width == image.width * height)

        // Catches views that render a blank frame because scroll/Canvas layout collapsed.
        #expect(try darkPixelCount(image, width: width, height: height) > 100)

        if let output = ProcessInfo.processInfo.environment["QINXU_PREVIEW_DIR"] {
            let folder = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name + ".png")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
        }
    }

    private func darkPixelCount(_ image: CGImage, width: Int, height: Int) throws -> Int {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: width, height: height,
                                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var darkPixels = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let darkRGB = pixels[index] < UInt8(160) && pixels[index + 1] < UInt8(180) && pixels[index + 2] < UInt8(180)
            if darkRGB && pixels[index + 3] > UInt8(200) { darkPixels += 1 }
        }
        return darkPixels
    }
}

#endif
