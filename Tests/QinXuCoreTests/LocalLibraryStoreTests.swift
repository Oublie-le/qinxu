import Foundation
import Testing
@testable import QinXuCore

@Suite struct LocalLibraryStoreTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("qinxu-library-test-\(UUID().uuidString)", isDirectory: true)
    }
    private func legacyURL(in base: URL) -> URL {
        base.appendingPathComponent("PianoPractice", isDirectory: true).appendingPathComponent("library.json")
    }
    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    private func recoveryData(in directory: URL) throws -> [Data] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("library-recovery-") }
            .map { try Data(contentsOf: $0) }
    }
    private var unsupportedData: [Data] {
        [Data("truncated user data".utf8), Data(#"{"version":99,"scores":[],"history":[],"lastScoreID":"future-score"}"#.utf8)]
    }

    @Test func testLibraryRoundTripPreservesImportedScoreAndSummary() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalLibraryStore(url: directory.appendingPathComponent("library.json"))
        let score = DemoScores.all[0]
        let summary = PracticeSummary(scoreTitle: score.title, correct: 12, wrong: 1, missed: 2, durationSeconds: 42, mode: .rhythm)
        try store.save(scores: [score], history: [summary], lastScoreID: score.id)
        let loaded = store.load()
        expectEqual(loaded.scores, [score]); expectEqual(loaded.history, [summary])
        expectEqual(loaded.lastScoreID, score.id); expectNil(loaded.error)
    }

    @Test func testCorruptDataSurvivesNextSaveAsRecoveryCopy() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        let badData = Data("truncated user data".utf8)
        try write(badData, to: url)
        let store = LocalLibraryStore(url: url)
        expectNotNil(store.load().error)
        try store.save(scores: [], history: [], lastScoreID: "demo-melody")
        expectEqual(try recoveryData(in: directory), [badData])
        expectNil(store.load().error)
    }

    @Test func testMigrationPreservesScoresHistorySelectionAndLegacyBytes() throws {
        let base = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let oldURL = legacyURL(in: base)
        let score = DemoScores.all[1]
        let summary = PracticeSummary(scoreTitle: score.title, correct: 21, wrong: 2, missed: 0, durationSeconds: 93, mode: .wait)
        try LocalLibraryStore(url: oldURL).save(scores: [score], history: [summary], lastScoreID: score.id)
        let original = try Data(contentsOf: oldURL)
        let store = LocalLibraryStore(baseDirectory: base)
        expectEqual(store.url, base.appendingPathComponent("QinXu", isDirectory: true).appendingPathComponent("library.json"))
        expectFalse(FileManager.default.fileExists(atPath: store.url.path))
        let loaded = store.load()
        expectNil(loaded.error)
        expectEqual(loaded.scores, [score]); expectEqual(loaded.history, [summary]); expectEqual(loaded.lastScoreID, score.id)
        expectEqual(try Data(contentsOf: store.url), original)
        expectEqual(try Data(contentsOf: oldURL), original)
        let files = try FileManager.default.contentsOfDirectory(at: store.url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        expectFalse(files.contains { $0.lastPathComponent.hasPrefix(".library-migration-") })
    }

    @Test func testExistingNewLibraryAlwaysWinsOverLegacy() throws {
        let base = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let oldURL = legacyURL(in: base)
        try LocalLibraryStore(url: oldURL).save(scores: [DemoScores.all[0]], history: [], lastScoreID: "old-selection")
        let oldData = try Data(contentsOf: oldURL)
        let store = LocalLibraryStore(baseDirectory: base)
        try LocalLibraryStore(url: store.url).save(scores: [DemoScores.all[2]], history: [], lastScoreID: "new-selection")
        let newData = try Data(contentsOf: store.url)
        let loaded = store.load()
        expectNil(loaded.error); expectEqual(loaded.scores, [DemoScores.all[2]])
        expectEqual(loaded.lastScoreID, "new-selection")
        expectEqual(try Data(contentsOf: store.url), newData)
        expectEqual(try Data(contentsOf: oldURL), oldData)
    }

    @Test func testCorruptAndNewerNewStoresDoNotFallBackOrLoseRecoveryCopy() throws {
        for invalid in unsupportedData {
            let base = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: base) }
            let oldURL = legacyURL(in: base)
            try LocalLibraryStore(url: oldURL).save(scores: [DemoScores.all[0]], history: [], lastScoreID: "old-selection")
            let oldData = try Data(contentsOf: oldURL)
            let store = LocalLibraryStore(baseDirectory: base)
            try write(invalid, to: store.url)
            let loaded = store.load()
            expectNotNil(loaded.error); expectTrue(loaded.scores.isEmpty)
            expectEqual(try Data(contentsOf: store.url), invalid)
            try store.save(scores: [], history: [], lastScoreID: "new-selection")
            expectEqual(try recoveryData(in: store.url.deletingLastPathComponent()), [invalid])
            expectEqual(try Data(contentsOf: oldURL), oldData)
            expectEqual(store.load().lastScoreID, "new-selection")
        }
    }

    @Test func testCorruptAndNewerLegacyBytesSurviveMigrationAndSubsequentSave() throws {
        for invalid in unsupportedData {
            let base = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: base) }
            let oldURL = legacyURL(in: base)
            try write(invalid, to: oldURL)
            let store = LocalLibraryStore(baseDirectory: base)
            expectNotNil(store.load().error)
            expectEqual(try Data(contentsOf: store.url), invalid)
            expectEqual(try Data(contentsOf: oldURL), invalid)
            try store.save(scores: [], history: [], lastScoreID: "new-selection")
            expectEqual(try recoveryData(in: store.url.deletingLastPathComponent()), [invalid])
            expectEqual(try Data(contentsOf: oldURL), invalid)
            expectNil(store.load().error)
        }
    }

    @Test func testMigrationWriteFailureStillLoadsRecoverableLegacyData() throws {
        let base = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let oldURL = legacyURL(in: base)
        let score = DemoScores.all[0]
        try LocalLibraryStore(url: oldURL).save(scores: [score], history: [], lastScoreID: score.id)
        let oldData = try Data(contentsOf: oldURL)
        // A file at the destination directory creates a deterministic failure, even as root.
        let blocker = base.appendingPathComponent("QinXu")
        let blockerData = Data("do not replace this file".utf8)
        try blockerData.write(to: blocker)
        let store = LocalLibraryStore(baseDirectory: base)
        let loaded = store.load()
        expectTrue(loaded.error?.contains("迁移失败") == true)
        expectEqual(loaded.scores, [score]); expectEqual(loaded.lastScoreID, score.id)
        expectThrows(try store.save(scores: [], history: [], lastScoreID: "failed-save"))
        expectEqual(try Data(contentsOf: oldURL), oldData)
        expectEqual(try Data(contentsOf: blocker), blockerData)
        expectFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    @Test func testSaveBeforeLoadPreservesUnsupportedLegacyData() throws {
        let base = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let oldURL = legacyURL(in: base)
        let invalid = unsupportedData[1]
        try write(invalid, to: oldURL)
        let store = LocalLibraryStore(baseDirectory: base)
        try store.save(scores: [DemoScores.all[0]], history: [], lastScoreID: "new-selection")
        expectEqual(try recoveryData(in: store.url.deletingLastPathComponent()), [invalid])
        expectEqual(try Data(contentsOf: oldURL), invalid)
        expectEqual(store.load().scores, [DemoScores.all[0]])
    }

    @Test func testExplicitFileURLDoesNotImportLegacyLibrary() throws {
        let base = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        try LocalLibraryStore(url: legacyURL(in: base)).save(scores: [DemoScores.all[0]], history: [], lastScoreID: "legacy")
        let explicitURL = base.appendingPathComponent("isolated.json")
        let store = LocalLibraryStore(url: explicitURL, baseDirectory: base)
        expectEqual(store.url, explicitURL)
        let loaded = store.load()
        expectTrue(loaded.scores.isEmpty); expectNil(loaded.error)
        expectFalse(FileManager.default.fileExists(atPath: explicitURL.path))
    }
}
