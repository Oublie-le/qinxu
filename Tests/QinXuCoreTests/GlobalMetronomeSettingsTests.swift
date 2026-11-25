import Foundation
import Testing
@testable import QinXuCore

@Suite struct GlobalMetronomeSettingsTests {
    @Test func defaultsAndAbsolutePositionsRespectBarAndBeatBoundaries() throws {
        let settings = GlobalMetronomeSettings()
        #expect(settings.isValid && settings.validationMessage == nil && settings.soundEnabled)
        #expect(settings.tempoNote == .quarter && settings.clickNote == .quarter)
        #expect(settings.quarterBPM == 80 && settings.beatSeconds == 0.75)
        #expect(settings.pulseSeconds == 0.75 && settings.measureSeconds == 3)
        #expect(settings.pulsesPerBeat == 1 && settings.pulsesPerMeasure == 4)
        let first = try #require(settings.position(atElapsedSeconds: 0))
        #expect(first.index == 0 && first.measure == 1 && first.beat == 1 && first.subdivision == 1)
        #expect(first.isDownbeat && first.isBeat)
        #expect(settings.position(atElapsedSeconds: 0.749999)?.index == 0)
        let second = try #require(settings.position(atElapsedSeconds: 0.75))
        #expect(second.index == 1 && second.beat == 2 && second.isBeat && !second.isDownbeat)
        let nextBar = try #require(settings.position(atElapsedSeconds: 3))
        #expect(nextBar.index == 4 && nextBar.measure == 2 && nextBar.isDownbeat)
    }

    @Test func bpmReferenceMeterAndClickSubdivisionHaveSeparateMeanings() throws {
        let compound = GlobalMetronomeSettings(beatsPerMeasure: 6, beatUnit: 8, tempoBPM: 60,
                                               tempoNote: .dottedQuarter, clickNote: .sixteenth)
        #expect(compound.isValid && compound.quarterBPM == 90)
        #expect(abs(compound.beatSeconds - 1.0 / 3) < 0.000001)
        #expect(abs(compound.pulseSeconds - 1.0 / 6) < 0.000001)
        #expect(compound.pulsesPerBeat == 2 && compound.pulsesPerMeasure == 12 && compound.measureSeconds == 2)
        let subdivision = try #require(compound.position(atElapsedSeconds: 1.0 / 6))
        #expect(subdivision.beat == 1 && subdivision.subdivision == 2 && !subdivision.isBeat && !subdivision.isDownbeat)
        let fourthBeat = try #require(compound.position(atElapsedSeconds: 1))
        #expect(fourthBeat.beat == 4 && fourthBeat.subdivision == 1 && fourthBeat.isBeat && !fourthBeat.isDownbeat)
        #expect(compound.position(atElapsedSeconds: 2)?.measure == 2)
        let cutTime = GlobalMetronomeSettings(beatsPerMeasure: 2, beatUnit: 2, tempoBPM: 60,
                                              tempoNote: .half, clickNote: .eighth)
        #expect(cutTime.isValid && cutTime.quarterBPM == 120)
        #expect(cutTime.beatSeconds == 1 && cutTime.pulseSeconds == 0.25 && cutTime.measureSeconds == 2)
        #expect(cutTime.pulsesPerBeat == 4 && cutTime.pulsesPerMeasure == 8)
    }

    @Test func supportedCombinationsDeriveLongRunningPositionsWithoutAccumulatedDrift() throws {
        for beats in [1, 3, 5, 6, 16] {
            for unit in [2, 4, 8, 16] {
                for tempoNote in MetronomeNoteValue.allCases {
                    for clickNote in MetronomeNoteValue.allCases {
                        let settings = GlobalMetronomeSettings(beatsPerMeasure: beats, beatUnit: unit,
                            tempoBPM: 80, tempoNote: tempoNote, clickNote: clickNote)
                        guard settings.isValid else { continue }
                        #expect(settings.pulsesPerMeasure == beats * settings.pulsesPerBeat)
                        #expect(abs(settings.measureSeconds - settings.pulseSeconds * Double(settings.pulsesPerMeasure)) < 0.000001)
                        let index = 1_000_003
                        let elapsed = Double(index) * settings.pulseSeconds
                        let position = try #require(settings.position(atElapsedSeconds: elapsed))
                        #expect(position.index == index)
                        #expect(position.measure == index / settings.pulsesPerMeasure + 1)
                        #expect(position.beat == (index % settings.pulsesPerMeasure) / settings.pulsesPerBeat + 1)
                        #expect(position.subdivision == index % settings.pulsesPerBeat + 1)
                        #expect(position.isDownbeat == (index % settings.pulsesPerMeasure == 0))
                        #expect(settings.position(atElapsedSeconds: elapsed - settings.pulseSeconds * 0.00000001)?.index == index - 1)
                    }
                }
            }
        }
        let dense = GlobalMetronomeSettings(beatsPerMeasure: 16, beatUnit: 2, tempoBPM: 20, clickNote: .sixteenth)
        #expect(dense.pulsesPerMeasure == 128 && dense.measureSeconds == 96)
        #expect(dense.position(atElapsedSeconds: 96)?.index == 128)
    }

    @Test func invalidDraftsAndUnrepresentableTimesAreRejectedWithoutChangingValues() {
        let invalid: [GlobalMetronomeSettings] = [
            .init(beatsPerMeasure: 0), .init(beatsPerMeasure: 17), .init(beatUnit: 0), .init(beatUnit: 3),
            .init(tempoBPM: .nan), .init(tempoBPM: .infinity), .init(tempoBPM: 19), .init(tempoBPM: 301),
            .init(tempoBPM: 151, tempoNote: .half), .init(tempoBPM: 39, tempoNote: .eighth),
            .init(tempoBPM: 79, tempoNote: .sixteenth), .init(tempoBPM: 201, tempoNote: .dottedQuarter),
            .init(clickNote: .dottedQuarter), .init(clickNote: .half), .init(beatUnit: 8, clickNote: .quarter)
        ]
        for settings in invalid {
            #expect(!settings.isValid && settings.validationMessage != nil)
            #expect(settings.position(atElapsedSeconds: 0) == nil)
            #expect(settings.pulseSeconds.isNaN && settings.beatSeconds.isNaN && settings.measureSeconds.isNaN)
        }
        var draft = GlobalMetronomeSettings()
        draft.tempoNote = .half; draft.tempoBPM = 200
        _ = draft.validationMessage
        #expect(draft.tempoBPM == 200 && draft.tempoNote == .half && draft.quarterBPM == 400)
        #expect(GlobalMetronomeSettings(tempoBPM: 150, tempoNote: .half).isValid)
        #expect(GlobalMetronomeSettings(tempoBPM: 40, tempoNote: .eighth).isValid)
        #expect(GlobalMetronomeSettings(tempoBPM: 80, tempoNote: .sixteenth).isValid)
        #expect(GlobalMetronomeSettings(tempoBPM: 200, tempoNote: .dottedQuarter).isValid)
        let settings = GlobalMetronomeSettings()
        for time in [-1.0, .nan, .infinity, .greatestFiniteMagnitude, Double(Int.max) * settings.pulseSeconds] {
            #expect(settings.position(atElapsedSeconds: time) == nil)
        }
    }
}

@Suite struct MetronomeSettingsStoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("qinxu-metronome-\(UUID().uuidString)")
    }

    private func recoveryCopies(in directory: URL) throws -> [Data] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("metronome-settings-recovery-") }
            .map { try Data(contentsOf: $0) }
    }

    @Test func firstUpgradeUsesDefaultsAndRoundTripIsIndependentOfScoresAndOtherContainers() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let libraryURL = folder.appendingPathComponent("library.json")
        let library = LocalLibraryStore(url: libraryURL)
        try library.save(scores: [DemoScores.all[1]], history: [], lastScoreID: DemoScores.all[1].id)
        let original = try Data(contentsOf: libraryURL)
        let store = MetronomeSettingsStore(libraryURL: libraryURL)
        #expect(store.url == folder.appendingPathComponent("metronome-settings.json"))
        #expect(store.load().settings == GlobalMetronomeSettings() && store.load().error == nil)
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        let settings = GlobalMetronomeSettings(beatsPerMeasure: 6, beatUnit: 8, tempoBPM: 60,
                                              tempoNote: .dottedQuarter, clickNote: .sixteenth, soundEnabled: false)
        try store.save(settings)
        let relaunched = MetronomeSettingsStore(libraryURL: libraryURL)
        #expect(relaunched.load().error == nil && relaunched.load().settings == settings)
        #expect(try Data(contentsOf: libraryURL) == original)
        let isolated = MetronomeSettingsStore(libraryURL: folder.appendingPathComponent("ui-test/library.json"))
        #expect(isolated.load().settings == GlobalMetronomeSettings())
        #expect(!FileManager.default.fileExists(atPath: isolated.url.path))
    }

    @Test func futureCorruptInvalidAndOversizedFilesKeepExactRecoveryCopies() throws {
        let valid: [String: Any] = ["beatsPerMeasure": 4, "beatUnit": 4, "tempoBPM": 80,
                                   "tempoNote": "quarter", "clickNote": "quarter", "soundEnabled": true]
        var invalid = valid; invalid["beatUnit"] = 0
        var futureNote = valid; futureNote["tempoNote"] = "future-note"
        let examples = [Data("partial settings".utf8),
            try JSONSerialization.data(withJSONObject: ["version": 2, "settings": valid, "futureData": [1, 2, 3]]),
            try JSONSerialization.data(withJSONObject: ["version": 1, "settings": invalid]),
            try JSONSerialization.data(withJSONObject: ["version": 1, "settings": futureNote]),
            Data(repeating: 65, count: MetronomeSettingsStore.maximumBytes + 1)]
        for original in examples {
            let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let store = MetronomeSettingsStore(libraryURL: folder.appendingPathComponent("library.json"))
            try original.write(to: store.url)
            #expect(store.load().error != nil && store.load().settings == GlobalMetronomeSettings())
            #expect(try Data(contentsOf: store.url) == original)
            // This fresh instance must preserve the bad bytes even without a prior load.
            let writer = MetronomeSettingsStore(libraryURL: folder.appendingPathComponent("library.json"))
            let settings = GlobalMetronomeSettings(tempoBPM: 92, clickNote: .eighth, soundEnabled: false)
            try writer.save(settings)
            #expect(try recoveryCopies(in: folder) == [original])
            #expect(writer.load().settings == settings && writer.load().error == nil)
        }
    }

    @Test func rejectedSettingsNeverReplaceTheLastCommittedFile() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = MetronomeSettingsStore(libraryURL: folder.appendingPathComponent("library.json"))
        let settings = GlobalMetronomeSettings(tempoBPM: 90)
        try store.save(settings)
        let original = try Data(contentsOf: store.url)
        for invalid in [GlobalMetronomeSettings(tempoBPM: .nan), .init(tempoBPM: .infinity),
                        .init(tempoBPM: 300, tempoNote: .half), .init(beatUnit: 0), .init(clickNote: .dottedQuarter)] {
            #expect(throws: (any Error).self) { try store.save(invalid) }
            #expect(try Data(contentsOf: store.url) == original)
            #expect(store.load().settings == settings)
        }
        #expect(try recoveryCopies(in: folder).isEmpty)
    }

    @Test func filesystemFailureDoesNotDamageExistingPathsOrLibrary() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let libraryURL = folder.appendingPathComponent("library.json")
        let original = Data("existing user data".utf8)
        try original.write(to: libraryURL)
        let store = MetronomeSettingsStore(libraryURL: libraryURL)
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: false)
        let nested = store.url.appendingPathComponent("preserve")
        try original.write(to: nested)
        #expect(store.load().error != nil)
        #expect(throws: (any Error).self) { try store.save(.init()) }
        #expect(try Data(contentsOf: libraryURL) == original)
        #expect(try Data(contentsOf: nested) == original)
        #expect(try recoveryCopies(in: folder).isEmpty)
    }
}
