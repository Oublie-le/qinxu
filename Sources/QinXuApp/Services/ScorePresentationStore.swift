import Foundation
import ImageIO
import UniformTypeIdentifiers

/// App-owned presentation data stays separate from musical semantics and the core library.
/// One atomic file keeps a favorite or cover change from partially replacing earlier state.
struct ScorePresentationStore {
    struct Snapshot: Codable, Equatable {
        var version = 1
        var favoriteScoreIDs: Set<String> = []
        var scoreCoverData: [String: Data] = [:]
    }

    struct LoadResult {
        var snapshot = Snapshot()
        var error: String?
    }

    static let maximumImportBytes = 8 * 1024 * 1024
    static let maximumCoverPixels = 512
    private static let maximumCoverBytes = 512 * 1024
    private static let maximumStoreBytes = 64 * 1024 * 1024
    let url: URL

    init(libraryURL: URL) {
        // Derive the sidecar from the exact library URL, including test/custom stores.
        url = libraryURL.deletingPathExtension().appendingPathExtension("presentation.json")
    }

    func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return LoadResult() }
        do {
            return LoadResult(snapshot: try decode(Self.readBounded(url, limit: Self.maximumStoreBytes)))
        } catch {
            return LoadResult(error: "收藏与封面读取失败，原文件已保留：\(url.path)。\(error.localizedDescription)")
        }
    }

    func save(_ snapshot: Snapshot) throws {
        try validate(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= Self.maximumStoreBytes else {
            throw PresentationError.message("收藏与封面数据过大，请先移除不需要的封面。")
        }
        let files = FileManager.default
        let directory = url.deletingLastPathComponent()
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        if files.fileExists(atPath: url.path) {
            var needsRecovery = false
            do { _ = try decode(Self.readBounded(url, limit: Self.maximumStoreBytes)) }
            catch { needsRecovery = true }
            if needsRecovery {
                // Copy, rather than re-encode, so future-version and damaged bytes survive exactly.
                // A failed recovery copy prevents the new write.
                let backup = directory.appendingPathComponent("presentation-recovery-\(UUID().uuidString).json")
                try files.copyItem(at: url, to: backup)
            }
        }
        try data.write(to: url, options: .atomic)
    }

    /// Accept image bytes, not the extension. Downsampling happens before full raster decoding.
    static func normalizedCover(from url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try normalizedCover(data: readBounded(url, limit: maximumImportBytes))
    }

    static func normalizedCover(data: Data) throws -> Data {
        guard data.count <= maximumImportBytes else { throw PresentationError.imageTooLarge }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.jpeg.identifier, UTType.png.identifier, UTType.webP.identifier].contains(type),
              CGImageSourceGetCount(source) > 0,
              let dimensions = dimensions(of: source),
              dimensions.width <= 30_000, dimensions.height <= 30_000,
              Double(dimensions.width) * Double(dimensions.height) <= 100_000_000 else {
            throw PresentationError.message("无法读取封面。请选择有效的 JPG、PNG 或 WebP 图片（不超过 1 亿像素）。")
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumCoverPixels,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions),
              let context = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw PresentationError.message("封面解码失败，请尝试另一张图片。")
        }
        // JPEG is bounded and metadata-free; transparent source pixels sit on the app's paper color.
        context.setFillColor(CGColor(red: 1, green: 0.996, blue: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard let image = context.makeImage() else { throw PresentationError.message("无法生成封面缩略图。") }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PresentationError.message("无法保存封面图片。")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination), result.length <= maximumCoverBytes else {
            throw PresentationError.message("封面缩略图过大，请尝试更简单的图片。")
        }
        return result as Data
    }

    private func decode(_ data: Data) throws -> Snapshot {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        try validate(snapshot)
        return snapshot
    }

    private func validate(_ snapshot: Snapshot) throws {
        guard snapshot.version == 1 else {
            throw PresentationError.message("收藏与封面数据版本暂不支持，将在写入前保留恢复副本。")
        }
        guard snapshot.favoriteScoreIDs.count <= 10_000, snapshot.scoreCoverData.count <= 256 else {
            throw PresentationError.message("收藏与封面数量超出支持范围。")
        }
        for data in snapshot.scoreCoverData.values {
            guard data.count <= Self.maximumCoverBytes,
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  (CGImageSourceGetType(source) as String?) == UTType.jpeg.identifier,
                  CGImageSourceGetStatus(source) == .statusComplete,
                  let dimensions = Self.dimensions(of: source),
                  dimensions.width <= Self.maximumCoverPixels,
                  dimensions.height <= Self.maximumCoverPixels else {
                throw PresentationError.message("封面数据损坏，原文件将在写入前保留恢复副本。")
            }
        }
    }

    private static func dimensions(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0 else { return nil }
        return (width.intValue, height.intValue)
    }

    private static func readBounded(_ url: URL, limit: Int) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= limit else { throw limit == maximumImportBytes ? PresentationError.imageTooLarge : PresentationError.message("收藏与封面文件过大，原文件已保留。") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw limit == maximumImportBytes ? PresentationError.imageTooLarge : PresentationError.message("收藏与封面文件过大，原文件已保留。") }
        return data
    }
}

enum PresentationError: LocalizedError {
    case message(String)
    static var imageTooLarge: PresentationError { .message("封面超过 8 MB，请选择较小的图片。") }
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
