import Foundation
import Testing
@testable import PianoCore

@Suite struct LocalLibraryStoreTests {
    @Test func testLibraryRoundTripPreservesImportedScoreAndSummary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("library.json")
        let badData = Data("truncated user data".utf8)
        try badData.write(to: url)
        let store = LocalLibraryStore(url: url)
        expectNotNil(store.load().error)
        try store.save(scores: [], history: [], lastScoreID: "demo-melody")
        let backup = try requireValue(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("library-recovery-") })
        expectEqual(try Data(contentsOf: backup), badData)
        expectNil(store.load().error)
    }
}
