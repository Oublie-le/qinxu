import Foundation
import Combine

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
}
