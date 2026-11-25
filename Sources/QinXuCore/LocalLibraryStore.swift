import Foundation

public struct LocalLibraryStore {
    public struct Snapshot: Codable {
        public var version = 1
        public var scores: [PianoScore] = []
        public var history: [PracticeSummary] = []
        public var lastScoreID: String?
        public var error: String?
    }
    public let url: URL
    private let legacyURL: URL?

    /// An explicit file URL is isolated: it never imports the user's default library.
    /// `baseDirectory` replaces Application Support for tests or another local container.
    public init(url: URL? = nil, baseDirectory: URL? = nil) {
        if let url {
            self.url = url
            legacyURL = nil
        } else {
            let base = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.url = base.appendingPathComponent("QinXu", isDirectory: true).appendingPathComponent("library.json")
            legacyURL = base.appendingPathComponent("PianoPractice", isDirectory: true).appendingPathComponent("library.json")
        }
    }

    public func load() -> Snapshot {
        let files = FileManager.default
        // Never fall back over an existing new store, including corrupt or newer-version data.
        if files.fileExists(atPath: url.path) { return loadCurrent() }
        guard let legacyURL, files.fileExists(atPath: legacyURL.path) else { return Snapshot() }
        let legacyData: Data
        do {
            legacyData = try Data(contentsOf: legacyURL)
        } catch {
            if files.fileExists(atPath: url.path) { return loadCurrent() }
            return Snapshot(error: "旧版数据读取失败，原文件已保留：\(legacyURL.path)。\(error.localizedDescription)")
        }
        do {
            try installLegacy(legacyData)
            return loadCurrent()
        } catch {
            // Another writer may have created the new store while the migration was in progress.
            if files.fileExists(atPath: url.path) { return loadCurrent() }
            let migrationMessage = "旧版数据迁移失败，原文件已保留：\(legacyURL.path)。\(error.localizedDescription)"
            do {
                var snapshot = try decode(legacyData)
                snapshot.error = migrationMessage + " 当前仍可读取旧版曲库和练习记录。"
                return snapshot
            } catch {
                return Snapshot(error: migrationMessage + " 旧版数据也暂时无法读取：\(error.localizedDescription)")
            }
        }
    }

    public func save(scores: [PianoScore], history: [PracticeSummary], lastScoreID: String) throws {
        let files = FileManager.default
        // Save may be called without load. Preserve unsupported legacy bytes in the new store
        // before the normal recovery-copy rule runs, while keeping the old file untouched.
        if !files.fileExists(atPath: url.path), let legacyURL, files.fileExists(atPath: legacyURL.path) {
            do {
                try installLegacy(Data(contentsOf: legacyURL))
            } catch {
                guard files.fileExists(atPath: url.path) else {
                    throw NSError(domain: "QinXu.Library", code: 2, userInfo: [NSLocalizedDescriptionKey:
                        "旧版数据迁移失败，尚未写入新数据；原文件已保留：\(legacyURL.path)。\(error.localizedDescription)"])
                }
            }
        }
        let directory = url.deletingLastPathComponent()
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Snapshot(scores: scores, history: history, lastScoreID: lastScoreID))
        if files.fileExists(atPath: url.path) {
            let original = try Data(contentsOf: url)
            if (try? decode(original)) == nil {
                // Never destroy the only copy of corrupt or newer-version user data.
                let backup = directory.appendingPathComponent("library-recovery-\(UUID().uuidString).json")
                try original.write(to: backup, options: .atomic)
            }
        }
        try data.write(to: url, options: .atomic)
    }

    private func loadCurrent() -> Snapshot {
        do {
            var snapshot = try decode(Data(contentsOf: url))
            snapshot.error = nil
            return snapshot
        } catch {
            return Snapshot(error: "本地数据读取失败，原文件已保留：\(url.path)。\(error.localizedDescription)")
        }
    }

    /// Publish a complete file from the same directory. Unlike writing directly to `url`,
    /// FileManager's move refuses an existing destination instead of replacing it.
    private func installLegacy(_ data: Data) throws {
        let files = FileManager.default
        guard !files.fileExists(atPath: url.path) else { return }
        let directory = url.deletingLastPathComponent()
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".library-migration-\(UUID().uuidString).json")
        defer { try? files.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        try files.moveItem(at: temporary, to: url)
    }

    private func decode(_ data: Data) throws -> Snapshot {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        // A compatible outer schema can still contain a newer report with fields
        // this app cannot round-trip. Preserve the original bytes before any save.
        guard snapshot.version == 1,
              snapshot.history.allSatisfy({ $0.report.map { $0.version == 1 } ?? true }) else {
            throw NSError(domain: "QinXu.Library", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "数据版本暂不支持，将保留恢复副本。"])
        }
        return snapshot
    }
}
