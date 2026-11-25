import Foundation

public struct MetronomeSettingsStore {
    public struct Snapshot {
        public var settings = GlobalMetronomeSettings()
        public var error: String?
    }

    private struct Document: Codable {
        var version = 1
        var settings: GlobalMetronomeSettings
    }

    static let maximumBytes = 64 * 1024
    public let url: URL

    /// Keep custom libraries and UI-test launches in their own exact container.
    public init(libraryURL: URL) {
        url = libraryURL.deletingLastPathComponent().appendingPathComponent("metronome-settings.json")
    }

    public func load() -> Snapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return Snapshot() }
        do {
            return Snapshot(settings: try decode(readBounded()).settings)
        } catch {
            return Snapshot(error: "节拍器设置读取失败，原文件已保留：\(url.path)。\(error.localizedDescription)")
        }
    }

    /// Publish the new settings only after this transaction succeeds.
    public func save(_ settings: GlobalMetronomeSettings) throws {
        let document = Document(settings: settings)
        try validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumBytes else { throw StoreError.message("节拍器设置文件超过大小限制。") }
        let files = FileManager.default
        let directory = url.deletingLastPathComponent()
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        if files.fileExists(atPath: url.path) {
            _ = try regularFileSize()
            if (try? decode(readBounded())) == nil {
                let backup = directory.appendingPathComponent("metronome-settings-recovery-\(UUID().uuidString).json")
                // Preserve unknown fields and damaged/oversized bytes, even without a prior load.
                // A failed recovery copy must abort before replacing the original.
                try files.copyItem(at: url, to: backup)
            }
        }
        try data.write(to: url, options: .atomic)
    }

    private func decode(_ data: Data) throws -> Document {
        let document = try JSONDecoder().decode(Document.self, from: data)
        try validate(document)
        return document
    }

    private func validate(_ document: Document) throws {
        guard document.version == 1 else {
            throw StoreError.message("节拍器设置版本暂不支持，将在写入前保留恢复副本。")
        }
        if let message = document.settings.validationMessage { throw StoreError.message(message) }
    }

    private func regularFileSize() throws -> UInt64 {
        // Fresh attributes avoid stale URL metadata after atomic replacement.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw StoreError.message("节拍器设置路径不是普通文件，原路径已保留。")
        }
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func readBounded() throws -> Data {
        guard try regularFileSize() <= UInt64(Self.maximumBytes) else {
            throw StoreError.message("节拍器设置文件过大，原文件已保留。")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard data.count <= Self.maximumBytes else { throw StoreError.message("节拍器设置文件过大，原文件已保留。") }
        return data
    }

    private enum StoreError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
    }
}
