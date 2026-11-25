import Foundation

/// Independent from library.json: adding checkpoints never rewrites imported scores.
public struct PracticeProgressStore {
    public struct Snapshot {
        public var checkpoints: [String: PracticeCheckpoint] = [:]
        public var error: String?
    }

    private struct Document: Codable {
        var version = 1
        var checkpoints: [String: PracticeCheckpoint]
    }

    static let maximumBytes = 2 * 1024 * 1024
    static let maximumEntries = 1_000
    public let url: URL

    /// The exact library container is used for both production and isolated tests.
    public init(libraryURL: URL) {
        url = libraryURL.deletingLastPathComponent().appendingPathComponent("practice-progress.json")
    }

    public func load() -> Snapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return Snapshot() }
        do {
            return Snapshot(checkpoints: try decode(readBounded()).checkpoints)
        } catch {
            return Snapshot(error: "练习进度读取失败，原文件已保留：\(url.path)。\(error.localizedDescription)")
        }
    }

    /// Callers publish the new checkpoint dictionary only after this returns successfully.
    public func save(_ checkpoints: [String: PracticeCheckpoint]) throws {
        let document = Document(checkpoints: checkpoints)
        try validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumBytes else { throw ProgressError.invalid("练习进度文件超过大小限制。") }

        let files = FileManager.default
        let directory = url.deletingLastPathComponent()
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        if files.fileExists(atPath: url.path) {
            _ = try regularFileSize()
            if (try? decode(readBounded())) == nil {
                let backup = directory.appendingPathComponent("practice-progress-recovery-\(UUID().uuidString).json")
                // Copy bytes rather than decoding: future formats and oversized files
                // remain recoverable. Failure to preserve the old file aborts the save.
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
            throw ProgressError.invalid("练习进度版本暂不支持，将在写入前保留恢复副本。")
        }
        guard document.checkpoints.count <= Self.maximumEntries,
              document.checkpoints.allSatisfy({ $0.key == $0.value.scoreID && $0.value.isValid }) else {
            throw ProgressError.invalid("练习进度含有无效的曲谱、位置、速度或日期。")
        }
    }

    private func regularFileSize() throws -> UInt64 {
        // URL resource values can remain cached after an atomic replacement; query
        // fresh filesystem metadata so replacing an oversized file can be read back.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw ProgressError.invalid("练习进度路径不是普通文件，原路径已保留。")
        }
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func readBounded() throws -> Data {
        guard try regularFileSize() <= UInt64(Self.maximumBytes) else {
            throw ProgressError.invalid("练习进度文件过大，原文件已保留。")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard data.count <= Self.maximumBytes else { throw ProgressError.invalid("练习进度文件过大，原文件已保留。") }
        return data
    }

    private enum ProgressError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
    }
}
