import Foundation
import Combine
import CoreGraphics

@MainActor
final class ImportedDocumentLibrary: ObservableObject {
    @Published private(set) var documents: [ImportedReadingDocument]
    @Published private(set) var isImporting = false
    @Published var errorMessage: String?
    private let store: ImportedDocumentStore

    init(libraryURL: URL) {
        store = ImportedDocumentStore(libraryURL: libraryURL)
        let loaded = store.load()
        documents = loaded.documents
        errorMessage = loaded.error
    }

    func importPDF(from url: URL, title: String? = nil) async throws -> ImportedReadingDocument {
        guard !isImporting else { throw CompressedMusicXML.ImportError.invalid("正在导入，请等待当前资料保存完成。") }
        isImporting = true
        defer { isImporting = false }
        let storage = store
        let document = try await Task.detached(priority: .userInitiated) { try storage.importPDF(from: url, title: title) }.value
        documents = store.load().documents
        errorMessage = nil
        return document
    }

    func importImages(from urls: [URL], title: String) async throws -> ImportedReadingDocument {
        guard !isImporting else { throw CompressedMusicXML.ImportError.invalid("正在导入，请等待当前资料保存完成。") }
        isImporting = true
        defer { isImporting = false }
        let storage = store
        let document = try await Task.detached(priority: .userInitiated) { try storage.importImages(from: urls, title: title) }.value
        documents = store.load().documents
        errorMessage = nil
        return document
    }

    func fileURL(for document: ImportedReadingDocument, pageIndex: Int = 0) throws -> URL {
        try store.fileURL(for: document, pageIndex: pageIndex)
    }

    func imagePreview(for document: ImportedReadingDocument, pageIndex: Int) throws -> CGImage {
        try store.imagePage(for: document, pageIndex: pageIndex, maximumPixelSize: 1_200)
    }

    func convertScore(for document: ImportedReadingDocument, pages: ClosedRange<Int>) async throws -> PDFScoreConversionResult {
        let title = document.title + " · 第\(pages.lowerBound)–\(pages.upperBound)页"
        return try await PDFScoreConverter.convert(document: document, store: store, pages: pages, title: title)
    }
}
