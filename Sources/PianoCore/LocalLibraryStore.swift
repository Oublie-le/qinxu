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
    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PianoPractice", isDirectory: true).appendingPathComponent("library.json")
    }
    public func load() -> Snapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return Snapshot() }
        do {
            var snapshot = try decode(Data(contentsOf: url))
            snapshot.error = nil
            return snapshot
        } catch {
            return Snapshot(error: "本地数据读取失败，原文件已保留：\(url.path)。\(error.localizedDescription)")
        }
    }
    public func save(scores: [PianoScore], history: [PracticeSummary], lastScoreID: String) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Snapshot(scores: scores, history: history, lastScoreID: lastScoreID))
        if FileManager.default.fileExists(atPath: url.path) {
            let original = try Data(contentsOf: url)
            if (try? decode(original)) == nil {
                // Never destroy the only copy of corrupt or newer-version user data.
                let backup = directory.appendingPathComponent("library-recovery-\(UUID().uuidString).json")
                try original.write(to: backup, options: .atomic)
            }
        }
        try data.write(to: url, options: .atomic)
    }
    private func decode(_ data: Data) throws -> Snapshot {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.version == 1 else {
            throw NSError(domain: "PianoPractice.Library", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "数据版本暂不支持，将保留恢复副本。"])
        }
        return snapshot
    }
}
