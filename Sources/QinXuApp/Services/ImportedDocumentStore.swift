import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers

struct ImportedReadingDocument: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case pdf, images }
    let id: String
    var title: String
    let kind: Kind
    let pageCount: Int
    let createdAt: Date
    let assetNames: [String]
    var formatTitle: String { kind == .pdf ? "PDF" : "图片教材" }
}

/// Reading assets are stored separately from structured practice scores.
struct ImportedDocumentStore: Sendable {
    static let maximumPDFBytes = 100_000_000
    static let maximumImageBytes = 20_000_000
    static let maximumImagePages = 200
    let directory: URL
    let indexURL: URL

    struct Snapshot: Codable { var version = 1; var documents: [ImportedReadingDocument] = [] }
    struct LoadResult { let documents: [ImportedReadingDocument]; let error: String? }

    init(libraryURL: URL) {
        directory = libraryURL.deletingLastPathComponent().appendingPathComponent("ReadingDocuments", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
    }

    func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return .init(documents: [], error: nil) }
        do { return .init(documents: try decode(StructuredScoreImport.boundedData(from: indexURL, limit: 2_000_000)).documents, error: nil) }
        catch { return .init(documents: [], error: "阅读资料目录暂时无法读取，原文件已保留。\(error.localizedDescription)") }
    }

    func importPDF(from source: URL, title: String?) throws -> ImportedReadingDocument {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let data = try StructuredScoreImport.boundedData(from: source, limit: Self.maximumPDFBytes)
        guard let pdf = PDFDocument(data: data), !pdf.isEncrypted, !pdf.isLocked,
              (1...2_000).contains(pdf.pageCount) else { throw failure("PDF 无法读取、已加密或超过 2000 页。") }
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { throw failure("PDF 中有无法读取的页面。") }
            let bounds = page.bounds(for: .cropBox)
            guard bounds.width.isFinite, bounds.height.isFinite,
                  bounds.width > 0, bounds.height > 0, bounds.width <= 100_000, bounds.height <= 100_000 else {
                throw failure("PDF 页面尺寸无效。")
            }
        }
        let document = ImportedReadingDocument(id: UUID().uuidString,
            title: try cleanTitle(title ?? source.deletingPathExtension().lastPathComponent), kind: .pdf,
            pageCount: pdf.pageCount, createdAt: Date(), assetNames: ["document.pdf"])
        return try install(document) { staging in
            try data.write(to: staging.appendingPathComponent("document.pdf"), options: .atomic)
        }
    }

    /// Caller-provided order is preserved exactly; no implicit file-name sorting here.
    func importImages(from sources: [URL], title: String) throws -> ImportedReadingDocument {
        guard (1...Self.maximumImagePages).contains(sources.count) else { throw failure("一次请选择 1–200 张单页图片。") }
        let names = sources.indices.map { String(format: "page-%04d.jpg", $0 + 1) }
        let document = ImportedReadingDocument(id: UUID().uuidString, title: try cleanTitle(title), kind: .images,
            pageCount: sources.count, createdAt: Date(), assetNames: names)
        return try install(document) { staging in
            var total = 0
            for (index, source) in sources.enumerated() {
                try autoreleasepool {
                    let access = source.startAccessingSecurityScopedResource()
                    defer { if access { source.stopAccessingSecurityScopedResource() } }
                    let data = try StructuredScoreImport.boundedData(from: source, limit: Self.maximumImageBytes)
                    let normalized = try Self.normalizedPage(data)
                    total += normalized.count
                    guard total <= Self.maximumPDFBytes else { throw failure("本组图片保存后超过 100 MB，请分批导入。") }
                    try normalized.write(to: staging.appendingPathComponent(names[index]), options: .atomic)
                }
            }
        }
    }

    func fileURL(for document: ImportedReadingDocument, pageIndex: Int = 0) throws -> URL {
        guard valid(document), pageIndex >= 0, pageIndex < document.pageCount else { throw failure("阅读资料信息无效。") }
        let name = document.assetNames[document.kind == .pdf ? 0 : pageIndex]
        let folder = directory.appendingPathComponent(document.id, isDirectory: true)
        let folderResource = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard folderResource.isDirectory == true, folderResource.isSymbolicLink != true else {
            throw failure("阅读资料目录缺失或不可读取，请重新导入。")
        }
        let url = folder.appendingPathComponent(name)
        let resource = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard resource.isRegularFile == true, resource.isSymbolicLink != true else { throw failure("阅读资料文件缺失或不可读取，请重新导入。") }
        return url
    }

    func imagePage(for document: ImportedReadingDocument, pageIndex: Int, maximumPixelSize: Int = 3_200) throws -> CGImage {
        guard document.kind == .images else { throw failure("这份阅读资料不是图片。") }
        let url = try fileURL(for: document, pageIndex: pageIndex)
        let data = try StructuredScoreImport.boundedData(from: url, limit: Self.maximumImageBytes)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw failure("无法打开第 \(pageIndex + 1) 页图片，请重新导入。")
        }
        return image
    }

    private func install(_ document: ImportedReadingDocument, writeAssets: (URL) throws -> Void) throws -> ImportedReadingDocument {
        let files = FileManager.default
        var documents = load().documents
        guard documents.count < 100 else { throw failure("当前最多保存 100 份阅读资料。") }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".pending-\(UUID().uuidString)", isDirectory: true)
        let destination = directory.appendingPathComponent(document.id, isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }
        try writeAssets(staging)
        try files.moveItem(at: staging, to: destination)
        do {
            documents.insert(document, at: 0)
            try save(documents)
        } catch {
            // Only this operation's newly moved UUID directory is rolled back.
            try? files.removeItem(at: destination)
            throw error
        }
        return document
    }

    private func save(_ documents: [ImportedReadingDocument]) throws {
        guard documents.count <= 100, documents.allSatisfy(valid), Set(documents.map(\.id)).count == documents.count else {
            throw failure("阅读资料目录无效，未覆盖原有数据。")
        }
        let data = try JSONEncoder().encode(Snapshot(documents: documents))
        if FileManager.default.fileExists(atPath: indexURL.path) {
            // A future/corrupt index must remain recoverable, including all old assets.
            let existing = try? StructuredScoreImport.boundedData(from: indexURL, limit: 2_000_000)
            if existing.flatMap({ try? decode($0) }) == nil {
                try FileManager.default.copyItem(at: indexURL,
                    to: directory.appendingPathComponent("index-recovery-\(UUID().uuidString).json"))
            }
        }
        try data.write(to: indexURL, options: .atomic)
    }

    private func decode(_ data: Data) throws -> Snapshot {
        guard data.count <= 2_000_000 else { throw failure("阅读资料目录过大。") }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.version == 1, snapshot.documents.count <= 100,
              snapshot.documents.allSatisfy(valid), Set(snapshot.documents.map(\.id)).count == snapshot.documents.count else {
            throw failure("阅读资料目录版本或内容暂不支持。")
        }
        return snapshot
    }

    private func valid(_ value: ImportedReadingDocument) -> Bool {
        guard UUID(uuidString: value.id) != nil, !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.title.count <= 160, value.createdAt.timeIntervalSince1970.isFinite else { return false }
        switch value.kind {
        case .pdf: return (1...2_000).contains(value.pageCount) && value.assetNames == ["document.pdf"]
        case .images:
            return (1...Self.maximumImagePages).contains(value.pageCount) && value.assetNames.count == value.pageCount &&
                value.assetNames == (0..<value.pageCount).map { String(format: "page-%04d.jpg", $0 + 1) }
        }
    }

    private func cleanTitle(_ value: String) throws -> String {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 160 else { throw failure("请填写 1–160 个字的资料名称。") }
        return title
    }
    private func failure(_ message: String) -> Error { CompressedMusicXML.ImportError.invalid(message) }

    static func normalizedPage(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= maximumImageBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 80_000_000 else {
            throw CompressedMusicXML.ImportError.invalid("图片无法读取、包含多帧或像素过大；请导出单页 JPG、PNG 或 HEIC。")
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 3_200]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw CompressedMusicXML.ImportError.invalid("图片无法转换为阅读页面。")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let output = NSMutableData()
        guard let flattened = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CompressedMusicXML.ImportError.invalid("图片页面无法保存。")
        }
        CGImageDestinationAddImage(destination, flattened, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= maximumImageBytes else {
            throw CompressedMusicXML.ImportError.invalid("图片页面编码失败或保存后超过 20 MB。")
        }
        return output as Data
    }
}
