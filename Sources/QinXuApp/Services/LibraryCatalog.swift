import Foundation
import Combine

enum LibraryEntryReference: Codable, Equatable, Hashable, Identifiable {
    case score(String)
    case document(String)
    var sourceID: String {
        switch self { case .score(let id), .document(let id): return id }
    }
    var id: String {
        switch self { case .score(let id): return "score:" + id; case .document(let id): return "document:" + id }
    }
}

enum LibraryCollectionKind: String, Codable, CaseIterable {
    case book, collection
    var title: String { self == .book ? "教材" : "曲集" }
    var symbol: String { self == .book ? "books.vertical" : "rectangle.stack" }
}

struct LibraryCollection: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var kind: LibraryCollectionKind
    var entries: [LibraryEntryReference]
    init(id: String = UUID().uuidString, title: String, subtitle: String = "",
         kind: LibraryCollectionKind = .collection, entries: [LibraryEntryReference] = []) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.kind = kind; self.entries = entries
    }
}

enum CatalogDifficulty: String, Codable, CaseIterable {
    case unspecified, beginner, easy, intermediate, advanced
    var title: String {
        switch self {
        case .unspecified: return "未标注"
        case .beginner: return "入门"
        case .easy: return "初级"
        case .intermediate: return "中级"
        case .advanced: return "进阶"
        }
    }
}

/// Descriptive tags never alter a score's musical or evaluated contents.
struct ScoreCatalogMetadata: Codable, Equatable {
    var difficulty: CatalogDifficulty
    var genre: String
    var authorOverride: String?
    init(difficulty: CatalogDifficulty = .unspecified, genre: String = "", authorOverride: String? = nil) {
        self.difficulty = difficulty; self.genre = genre; self.authorOverride = authorOverride
    }
}

struct LibraryCatalogStore {
    struct Snapshot: Codable, Equatable {
        var version = 1
        var collections: [LibraryCollection] = []
        var metadata: [String: ScoreCatalogMetadata] = [:]
    }
    struct LoadResult { var snapshot = Snapshot(); var error: String? }
    let url: URL
    private static let maximumBytes = 4 * 1024 * 1024

    init(libraryURL: URL) { url = libraryURL.deletingPathExtension().appendingPathExtension("catalog.json") }

    func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return LoadResult() }
        do { return LoadResult(snapshot: try decode(read())) }
        catch { return LoadResult(error: "曲集与分类读取失败，原文件已保留：\(error.localizedDescription)") }
    }

    func save(_ snapshot: Snapshot) throws {
        try validate(snapshot)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= Self.maximumBytes else { throw CatalogError("曲集与分类数据过大。") }
        let files = FileManager.default
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if files.fileExists(atPath: url.path) {
            var recover = false
            do { _ = try decode(read()) } catch { recover = true }
            if recover {
                try files.copyItem(at: url, to: url.deletingLastPathComponent()
                    .appendingPathComponent("catalog-recovery-\(UUID().uuidString).json"))
            }
        }
        try data.write(to: url, options: .atomic)
    }

    private func read() throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard data.count <= Self.maximumBytes else { throw CatalogError("分类文件超过支持大小。") }
        return data
    }

    private func decode(_ data: Data) throws -> Snapshot {
        let value = try JSONDecoder().decode(Snapshot.self, from: data)
        try validate(value)
        return value
    }

    private func validate(_ value: Snapshot) throws {
        guard value.version == 1 else { throw CatalogError("分类文件版本暂不支持。") }
        guard value.collections.count <= 500, value.metadata.count <= 10_000,
              Set(value.collections.map(\.id)).count == value.collections.count else {
            throw CatalogError("曲集数量超出支持范围，或标识重复。")
        }
        for collection in value.collections {
            guard validID(collection.id), !collection.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  collection.title.count <= 80, collection.subtitle.count <= 200,
                  collection.entries.count <= 10_000,
                  Set(collection.entries).count == collection.entries.count,
                  collection.entries.allSatisfy({ validID($0.sourceID) }) else {
                throw CatalogError("曲集名称或条目无效。")
            }
        }
        guard value.metadata.allSatisfy({ validID($0.key, maximum: 270) && $0.value.genre.count <= 40 && ($0.value.authorOverride?.count ?? 0) <= 120 }) else {
            throw CatalogError("分类标签过长或无效。")
        }
    }
    private func validID(_ value: String, maximum: Int = 256) -> Bool { !value.isEmpty && value.count <= maximum }
}

struct CatalogError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
final class LibraryCatalogController: ObservableObject {
    @Published private(set) var collections: [LibraryCollection]
    @Published private(set) var metadata: [String: ScoreCatalogMetadata]
    @Published var errorMessage: String?
    private let store: LibraryCatalogStore

    init(libraryURL: URL) {
        store = LibraryCatalogStore(libraryURL: libraryURL)
        let loaded = store.load()
        collections = loaded.snapshot.collections; metadata = loaded.snapshot.metadata
        errorMessage = loaded.error
    }

    func metadata(for entry: LibraryEntryReference, fallback: ScoreCatalogMetadata = .init()) -> ScoreCatalogMetadata {
        metadata[entry.id] ?? fallback
    }
    func collectionIDs(containing entry: LibraryEntryReference) -> Set<String> {
        Set(collections.filter { $0.entries.contains(entry) }.map(\.id))
    }

    @discardableResult
    func createCollection(title: String, kind: LibraryCollectionKind) -> LibraryCollection? {
        let value = LibraryCollection(title: title.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind)
        var next = snapshot; next.collections.append(value)
        return persist(next) ? value : nil
    }

    @discardableResult
    func updateCollection(_ collection: LibraryCollection) -> Bool {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return false }
        var next = snapshot; next.collections[index] = collection
        return persist(next)
    }

    @discardableResult
    func deleteCollection(id: String) -> Bool {
        var next = snapshot; next.collections.removeAll { $0.id == id }
        return persist(next)
    }

    /// Membership and tags are one transaction; a failed save publishes neither change.
    @discardableResult
    func organize(_ entry: LibraryEntryReference, collectionIDs: Set<String>, metadata: ScoreCatalogMetadata) -> Bool {
        guard collectionIDs.isSubset(of: Set(collections.map(\.id))) else {
            errorMessage = "部分曲集已不存在，请重新选择。"; return false
        }
        var next = snapshot
        for index in next.collections.indices {
            if collectionIDs.contains(next.collections[index].id) {
                if !next.collections[index].entries.contains(entry) { next.collections[index].entries.append(entry) }
            } else { next.collections[index].entries.removeAll { $0 == entry } }
        }
        next.metadata[entry.id] = metadata
        return persist(next)
    }

    private var snapshot: LibraryCatalogStore.Snapshot { .init(collections: collections, metadata: metadata) }
    private func persist(_ value: LibraryCatalogStore.Snapshot) -> Bool {
        do {
            try store.save(value)
            collections = value.collections; metadata = value.metadata
            errorMessage = nil
            return true
        } catch {
            errorMessage = "整理未保存：\(error.localizedDescription)"
            return false
        }
    }
}
