import Foundation
import Testing
@testable import QinXuApp

@Suite @MainActor struct LibraryCatalogTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("qinxu-catalog-\(UUID().uuidString)")
    }

    @Test func groupsAndTagsSurviveReloadWithoutChangingScoreOrDocumentFiles() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let library = directory.appendingPathComponent("library.json")
        let coreBytes = Data("existing library".utf8)
        try coreBytes.write(to: library)
        let controller = LibraryCatalogController(libraryURL: library)
        let book = try #require(controller.createCollection(title: "我的教材", kind: .book))
        let set = try #require(controller.createCollection(title: "周末练习", kind: .collection))
        let tags = ScoreCatalogMetadata(difficulty: .easy, genre: "流行", authorOverride: "本地作者")
        #expect(controller.organize(.score("one"), collectionIDs: [book.id, set.id], metadata: tags))
        #expect(controller.organize(.document("pdf-one"), collectionIDs: [book.id], metadata: .init()))
        let reloaded = LibraryCatalogController(libraryURL: library)
        #expect(reloaded.collections == controller.collections)
        #expect(reloaded.metadata(for: .score("one")) == tags)
        #expect(reloaded.collectionIDs(containing: .document("pdf-one")) == [book.id])
        #expect(try Data(contentsOf: library) == coreBytes)
        #expect(reloaded.deleteCollection(id: book.id))
        #expect(reloaded.collectionIDs(containing: .score("one")) == [set.id])
        #expect(reloaded.metadata(for: .score("one")) == tags)
        #expect(try Data(contentsOf: library) == coreBytes)
    }

    @Test func editingTagsPreservesOrderAndUnknownMembershipCannotEraseState() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let controller = LibraryCatalogController(libraryURL: directory.appendingPathComponent("library.json"))
        let group = try #require(controller.createCollection(title: "顺序练习", kind: .collection))
        #expect(controller.organize(.score("first"), collectionIDs: [group.id], metadata: .init()))
        #expect(controller.organize(.score("second"), collectionIDs: [group.id], metadata: .init()))
        #expect(controller.organize(.score("first"), collectionIDs: [group.id], metadata: .init(difficulty: .beginner)))
        #expect(controller.collections.first?.entries == [.score("first"), .score("second")])
        let before = controller.collections
        #expect(!controller.organize(.score("first"), collectionIDs: ["missing"], metadata: .init()))
        #expect(controller.collections == before)
        #expect(controller.metadata(for: .score("first")).difficulty == .beginner)
    }

    @Test(arguments: ["damaged", #"{"version":42,"collections":[],"metadata":{}}"#])
    func futureOrCorruptCatalogGetsExactRecoveryCopyBeforeNewWrite(original: String) throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = LibraryCatalogStore(libraryURL: directory.appendingPathComponent("library.json"))
        let bytes = Data(original.utf8)
        try bytes.write(to: store.url)
        #expect(store.load().error != nil)
        #expect(try Data(contentsOf: store.url) == bytes)
        try store.save(.init(collections: [.init(title: "新的分组")]))
        let recoveries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("catalog-recovery-") }
        #expect(recoveries.count == 1)
        #expect(try Data(contentsOf: #require(recoveries.first)) == bytes)
        #expect(store.load().snapshot.collections.first?.title == "新的分组")
    }

    @Test func failedAtomicWriteDoesNotPublishNewMembershipOrTags() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let library = directory.appendingPathComponent("library.json")
        let controller = LibraryCatalogController(libraryURL: library)
        let group = try #require(controller.createCollection(title: "保留", kind: .collection))
        let old = controller.collections
        let storeURL = LibraryCatalogStore(libraryURL: library).url
        try FileManager.default.removeItem(at: storeURL)
        try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: false)
        #expect(!controller.organize(.document("unwritten"), collectionIDs: [group.id], metadata: .init(genre: "古典")))
        #expect(controller.collections == old)
        #expect(controller.metadata.isEmpty)
        #expect(controller.errorMessage != nil)
    }

    @Test func olderTagsWithoutAuthorRemainReadableAndInvalidReplacementKeepsSavedData() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = LibraryCatalogStore(libraryURL: directory.appendingPathComponent("library.json"))
        let bytes = Data(#"{"version":1,"collections":[],"metadata":{"score:one":{"difficulty":"easy","genre":"古典"}}}"#.utf8)
        try bytes.write(to: store.url)
        #expect(store.load().error == nil)
        #expect(store.load().snapshot.metadata["score:one"]?.authorOverride == nil)
        var invalid = LibraryCatalogStore.Snapshot(collections: [.init(id: "duplicate", title: "一"), .init(id: "duplicate", title: "二")])
        do { try store.save(invalid); Issue.record("Duplicate IDs must be rejected") } catch { }
        invalid.collections = [.init(title: "重复条目", entries: [.score("a"), .score("a")])]
        do { try store.save(invalid); Issue.record("Duplicate references must be rejected") } catch { }
        #expect(try Data(contentsOf: store.url) == bytes)
    }
}
