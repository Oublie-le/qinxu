import Foundation
import Testing
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import QinXuCore
@testable import QinXuApp

@Suite struct ImportedDocumentStoreTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("qinxu-reading-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func pdfData(pages: Int = 2) throws -> Data {
        let output = NSMutableData(), consumer = try #require(CGDataConsumer(data: output))
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0..<pages { context.beginPDFPage(nil); context.fill(CGRect(x: 50, y: 50, width: 20, height: 20)); context.endPDFPage() }
        context.closePDF()
        return output as Data
    }
    private func imageData(width: Int = 80, height: Int = 120, frames: Int = 1) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.4, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage()), data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data,
            (frames == 1 ? UTType.png : UTType.gif).identifier as CFString, frames, nil))
        for _ in 0..<frames { CGImageDestinationAddImage(destination, image, nil) }
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }
    private func rejected(_ action: () throws -> Void) {
        do { try action(); Issue.record("Expected document import rejection") } catch { }
    }

    @Test func pdfIsCopiedAndSurvivesSourceDeletionWithoutChangingCoreLibrary() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = folder.appendingPathComponent("library.json"), original = Data("keep core library".utf8)
        try original.write(to: library)
        let source = folder.appendingPathComponent("教材.pdf"), data = try pdfData()
        try data.write(to: source)
        let store = ImportedDocumentStore(libraryURL: library)
        let document = try store.importPDF(from: source, title: " 中文教材 ")
        try FileManager.default.removeItem(at: source)
        let restored = ImportedDocumentStore(libraryURL: library).load()
        #expect(restored.error == nil && restored.documents == [document])
        #expect(document.title == "中文教材" && document.kind == .pdf && document.pageCount == 2)
        #expect(try Data(contentsOf: store.fileURL(for: document)) == data)
        #expect(PDFDocument(url: try store.fileURL(for: document, pageIndex: 1))?.pageCount == 2)
        #expect(try Data(contentsOf: library) == original)
    }

    @Test func imageBookPreservesExplicitOrderAndNormalizesPages() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("z.png"), second = folder.appendingPathComponent("a.png")
        try imageData(width: 4000, height: 200).write(to: first)
        try imageData(width: 80, height: 120).write(to: second)
        let store = ImportedDocumentStore(libraryURL: folder.appendingPathComponent("library.json"))
        let document = try store.importImages(from: [first, second], title: "按页序排列")
        try FileManager.default.removeItem(at: first); try FileManager.default.removeItem(at: second)
        #expect(document.pageCount == 2 && document.kind == .images)
        for (index, size) in [(3200, 160), (80, 120)].enumerated() {
            let data = try Data(contentsOf: store.fileURL(for: document, pageIndex: index))
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == size.0 && image.height == size.1)
            #expect(image.alphaInfo == .none || image.alphaInfo == .noneSkipLast || image.alphaInfo == .noneSkipFirst)
        }
        #expect(store.load().documents == [document])
    }

    @Test func badPageRollsBackWholeBookAndLeavesExistingIndexUnchanged() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("valid.pdf"), image = folder.appendingPathComponent("page.png"), bad = folder.appendingPathComponent("bad.png")
        try pdfData().write(to: source); try imageData().write(to: image); try Data("invalid image".utf8).write(to: bad)
        let store = ImportedDocumentStore(libraryURL: folder.appendingPathComponent("library.json"))
        let original = try store.importPDF(from: source, title: nil), index = try Data(contentsOf: store.indexURL)
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: store.directory.path))
        rejected { _ = try store.importImages(from: [image, bad], title: "不应留下半本") }
        #expect(try Data(contentsOf: store.indexURL) == index)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: store.directory.path)) == before)
        #expect(store.load().documents == [original])
        #expect(try Data(contentsOf: source) == Data(contentsOf: store.fileURL(for: original)))
    }

    @Test(arguments: ["damaged-json", #"{"version":99,"documents":[]}"#])
    func corruptOrFutureIndexIsBackedUpBeforeReplacement(original: String) throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ImportedDocumentStore(libraryURL: folder.appendingPathComponent("library.json"))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let bytes = Data(original.utf8), previousAssets = store.directory.appendingPathComponent("previous-assets")
        try bytes.write(to: store.indexURL); try Data("old page".utf8).write(to: previousAssets)
        #expect(store.load().error != nil)
        #expect(try Data(contentsOf: store.indexURL) == bytes)
        let source = folder.appendingPathComponent("new.pdf"); try pdfData().write(to: source)
        let imported = try store.importPDF(from: source, title: nil)
        let recoveries = try FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("index-recovery-") }
        #expect(recoveries.count == 1)
        #expect(try Data(contentsOf: #require(recoveries.first)) == bytes)
        #expect(try String(contentsOf: previousAssets, encoding: .utf8) == "old page")
        #expect(store.load().documents == [imported])
    }

    @Test func invalidPDFAndMultiframeImagesAreRejectedWithoutCreatingCatalog() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("pretend.pdf")
        try Data("not PDF".utf8).write(to: source)
        let store = ImportedDocumentStore(libraryURL: folder.appendingPathComponent("library.json"))
        rejected { _ = try store.importPDF(from: source, title: nil) }
        rejected { _ = try ImportedDocumentStore.normalizedPage(imageData(frames: 2)) }
        rejected { _ = try store.importImages(from: [], title: "empty") }
        rejected { _ = try store.importImages(from: Array(repeating: source, count: 201), title: "too many") }
        #expect(!FileManager.default.fileExists(atPath: store.indexURL.path))
    }

    @Test func invalidPagePathsAndSymlinkedAssetsCannotBeOpened() throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("book.pdf"); try pdfData().write(to: source)
        let store = ImportedDocumentStore(libraryURL: folder.appendingPathComponent("library.json"))
        let document = try store.importPDF(from: source, title: nil)
        rejected { _ = try store.fileURL(for: document, pageIndex: -1) }
        rejected { _ = try store.fileURL(for: document, pageIndex: 2) }
        let escaped = ImportedReadingDocument(id: "../outside", title: "bad", kind: .pdf, pageCount: 2, createdAt: Date(), assetNames: ["document.pdf"])
        rejected { _ = try store.fileURL(for: escaped) }
        let asset = try store.fileURL(for: document)
        try FileManager.default.removeItem(at: asset)
        try FileManager.default.createSymbolicLink(at: asset, withDestinationURL: source)
        rejected { _ = try store.fileURL(for: document) }
    }

    @Test @MainActor func libraryPublishesOnlySuccessfulImportsAndRestoresAfterRelaunch() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let libraryURL = folder.appendingPathComponent("library.json"), source = folder.appendingPathComponent("pages.pdf")
        try pdfData().write(to: source)
        let library = ImportedDocumentLibrary(libraryURL: libraryURL)
        let document = try await library.importPDF(from: source)
        #expect(!library.isImporting && library.documents == [document])
        try Data("corrupt".utf8).write(to: source)
        do { _ = try await library.importPDF(from: source); Issue.record("Expected corrupt PDF failure") } catch { }
        #expect(!library.isImporting && library.documents == [document])
        #expect(ImportedDocumentLibrary(libraryURL: libraryURL).documents == [document])
    }
}
