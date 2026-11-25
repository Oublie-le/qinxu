import Foundation
import Testing
@testable import QinXuCore

@Suite struct PracticeProgressStoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("qinxu-progress-\(UUID().uuidString)")
    }

    private func checkpoint(_ score: PianoScore = DemoScores.all[0]) throws -> PracticeCheckpoint {
        try #require(PracticeCheckpoint.make(score: score, measure: 3, hand: .right, mode: .rhythm,
                                            tempoBPM: 64, updatedAt: Date(timeIntervalSince1970: 1_790_000_000)))
    }

    private func recoveryCopies(in directory: URL) throws -> [Data] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("practice-progress-recovery-") }
            .map { try Data(contentsOf: $0) }
    }

    @Test func firstUpgradeAndRoundTripLeaveExistingLibraryUntouched() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let library = LocalLibraryStore(url: folder.appendingPathComponent("library.json"))
        let score = DemoScores.all[0]
        try library.save(scores: [score], history: [], lastScoreID: score.id)
        let original = try Data(contentsOf: library.url)
        let store = PracticeProgressStore(libraryURL: library.url)
        #expect(store.url == folder.appendingPathComponent("practice-progress.json"))
        #expect(store.load().checkpoints.isEmpty && store.load().error == nil)
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        let value = try checkpoint(score)
        try store.save([value.scoreID: value])
        let restored = store.load()
        #expect(restored.error == nil)
        #expect(restored.checkpoints == [value.scoreID: value])
        #expect(restored.checkpoints[value.scoreID]?.resumeMeasure(in: score) == 3)
        #expect(try Data(contentsOf: library.url) == original)
        try store.save([:])
        #expect(store.load().checkpoints.isEmpty)
        #expect(try Data(contentsOf: library.url) == original)
    }

    @Test func corruptFutureAndOversizedFilesSurviveSavingWithoutPriorLoad() throws {
        let examples = [Data("partial progress".utf8),
                        Data(#"{"version":99,"checkpoints":{},"futureData":"preserve"}"#.utf8),
                        Data(repeating: 65, count: PracticeProgressStore.maximumBytes + 1)]
        for original in examples {
            let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let store = PracticeProgressStore(libraryURL: folder.appendingPathComponent("library.json"))
            try original.write(to: store.url)
            let loaded = store.load()
            #expect(loaded.checkpoints.isEmpty && loaded.error != nil)
            #expect(try Data(contentsOf: store.url) == original)
            // A fresh instance has never loaded the damaged file; save must still preserve it.
            let freshStore = PracticeProgressStore(libraryURL: folder.appendingPathComponent("library.json"))
            let value = try checkpoint()
            try freshStore.save([value.scoreID: value])
            #expect(try recoveryCopies(in: folder) == [original])
            #expect(freshStore.load().checkpoints == [value.scoreID: value])
        }
    }

    @Test func invalidCheckpointSaveNeverReplacesLastGoodData() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = PracticeProgressStore(libraryURL: folder.appendingPathComponent("library.json"))
        let value = try checkpoint()
        try store.save([value.scoreID: value])
        let original = try Data(contentsOf: store.url)
        var invalid: [PracticeCheckpoint] = []
        var changed = value; changed.measure = 0; invalid.append(changed)
        changed = value; changed.measure = 1_001; invalid.append(changed)
        changed = value; changed.tempoBPM = .nan; invalid.append(changed)
        changed = value; changed.tempoBPM = .infinity; invalid.append(changed)
        changed = value; changed.tempoBPM = 19; invalid.append(changed)
        changed = value; changed.updatedAt = Date(timeIntervalSince1970: .nan); invalid.append(changed)
        changed = value; changed.updatedAt = Date(timeIntervalSince1970: -1); invalid.append(changed)
        changed = value; changed.scoreID = String(repeating: "x", count: 257); invalid.append(changed)
        changed = value; changed.scoreFingerprint = "unsupported"; invalid.append(changed)
        for next in invalid {
            #expect(throws: (any Error).self) { try store.save([next.scoreID: next]) }
            #expect(try Data(contentsOf: store.url) == original)
        }
        #expect(throws: (any Error).self) { try store.save(["wrong-key": value]) }
        var oversized: [String: PracticeCheckpoint] = [:]
        for index in 0...PracticeProgressStore.maximumEntries {
            changed = value; changed.scoreID = "score-\(index)"; oversized[changed.scoreID] = changed
        }
        #expect(throws: (any Error).self) { try store.save(oversized) }
        #expect(try Data(contentsOf: store.url) == original)
        #expect(try recoveryCopies(in: folder).isEmpty)
    }

    @Test func invalidStoredRangeIsRetainedBeforeReplacement() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = PracticeProgressStore(libraryURL: folder.appendingPathComponent("library.json"))
        let value = try checkpoint()
        try store.save([value.scoreID: value])
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any])
        var checkpoints = try #require(object["checkpoints"] as? [String: [String: Any]])
        checkpoints[value.scoreID]?["measure"] = -4
        object["checkpoints"] = checkpoints
        let invalid = try JSONSerialization.data(withJSONObject: object)
        try invalid.write(to: store.url)
        #expect(store.load().error != nil)
        try store.save([value.scoreID: value])
        #expect(try recoveryCopies(in: folder) == [invalid])
    }

    @Test func filesystemFailurePreservesExistingPathsAndLibrary() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let libraryURL = folder.appendingPathComponent("library.json")
        let original = Data("existing library must remain".utf8)
        try original.write(to: libraryURL)
        let store = PracticeProgressStore(libraryURL: libraryURL)
        // A directory at the exact destination deterministically blocks a file write,
        // without permission assumptions that would behave differently under root.
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: false)
        let nested = store.url.appendingPathComponent("preserve")
        try original.write(to: nested)
        let value = try checkpoint()
        #expect(store.load().error != nil)
        #expect(throws: (any Error).self) { try store.save([value.scoreID: value]) }
        #expect(try Data(contentsOf: nested) == original)
        #expect(try Data(contentsOf: libraryURL) == original)
        #expect(try recoveryCopies(in: folder).isEmpty)
    }
}

@Suite struct PracticeCheckpointTests {
    @Test func contentChangesInvalidateProgressWhileMetadataAndNoteIDsDoNot() throws {
        let score = DemoScores.all[0]
        let checkpoint = try #require(PracticeCheckpoint.make(score: score, measure: 4, hand: .right,
                                                               mode: .wait, tempoBPM: 60))
        var renamed = score
        renamed.title = "中文标题"; renamed.composer = "新的署名"; renamed.warnings = []
        renamed.notes.reverse()
        for index in renamed.notes.indices { renamed.notes[index].id = UUID().uuidString }
        #expect(checkpoint.matches(renamed))
        #expect(checkpoint.resumeMeasure(in: renamed) == 4)
        var changed = score; changed.notes[0].midi += 1
        #expect(!checkpoint.matches(changed) && checkpoint.resumeMeasure(in: changed) == nil)
        changed = score; changed.notes[0].durationBeats = 0.5
        #expect(!checkpoint.matches(changed))
        changed = score; changed.notes[0].staff = 2
        #expect(!checkpoint.matches(changed))
        changed = score; changed.tempoBPM += 1
        #expect(!checkpoint.matches(changed))
        changed = score; changed.id = "another-score"
        #expect(!checkpoint.matches(changed))
        var completed = checkpoint; completed.isCompleted = true
        #expect(completed.matches(score) && completed.resumeMeasure(in: score) == nil)
        var outOfRange = checkpoint; outOfRange.measure = 999
        #expect(!outOfRange.matches(score) && outOfRange.resumeMeasure(in: score) == nil)
    }

    @Test func restorationWalksBackAcrossOverlappingTiesOnlyForSelectedHand() throws {
        let score = PianoScore(id: "ties", title: "跨小节", tempoBPM: 60, notes: [
            .init(id: "long-left", midi: 48, startBeat: 0, durationBeats: 6, staff: 2, measure: 1),
            .init(id: "overlap-left", midi: 52, startBeat: 4, durationBeats: 6, staff: 2, measure: 2),
            .init(id: "right", midi: 60, startBeat: 8, durationBeats: 1, staff: 1, measure: 3)
        ], measures: (1...3).map { .init(number: $0, startBeat: Double(($0 - 1) * 4), durationBeats: 4) })
        #expect(PracticeTiming.safeStartMeasure(score: score, hand: .both, requestedMeasure: 3) == 1)
        #expect(PracticeTiming.safeStartMeasure(score: score, hand: .right, requestedMeasure: 3) == 3)
        let checkpoint = try #require(PracticeCheckpoint.make(score: score, measure: 3, hand: .left,
                                                               mode: .wait, tempoBPM: 60))
        #expect(checkpoint.measure == 1 && checkpoint.resumeMeasure(in: score) == 1)
        #expect(PracticeTiming.loopStartIssue(score: score, hand: .left, startMeasure: checkpoint.measure) == nil)
        #expect(PracticeTiming.safeStartMeasure(score: score, hand: .both, requestedMeasure: 0) == nil)
        #expect(PracticeTiming.safeStartMeasure(score: score, hand: .both, requestedMeasure: 4) == nil)
        var noRemaining = score; noRemaining.notes.removeAll { $0.staff == 1 }
        #expect(PracticeTiming.safeStartMeasure(score: noRemaining, hand: .right, requestedMeasure: 3) == nil)
        // A completed score can end in a rest-only bar without losing its completion flag.
        var endingRest = DemoScores.all[0]
        let lastMeasure = endingRest.measures.count
        endingRest.notes.removeAll { $0.measure == lastMeasure }
        #expect(PracticeCheckpoint.make(score: endingRest, measure: endingRest.measures.count,
                                        hand: .right, mode: .wait, tempoBPM: 60, isCompleted: true) != nil)
    }

    @Test func malformedTimelineOrConfigurationCannotCreateAResumableCheckpoint() {
        let score = DemoScores.all[0]
        #expect(PracticeCheckpoint.make(score: score, measure: 1, hand: .right, mode: .wait, tempoBPM: .nan) == nil)
        var invalid = score; invalid.notes[0].startBeat = .nan
        #expect(PracticeCheckpoint.fingerprint(for: invalid) == nil)
        invalid = score; invalid.notes[0].measure = 999
        #expect(PracticeTiming.safeStartMeasure(score: invalid, hand: .right, requestedMeasure: 1) == nil)
        invalid = score; invalid.measures[1].number = 1
        #expect(PracticeCheckpoint.fingerprint(for: invalid) == nil)
    }
}
