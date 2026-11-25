import Foundation
import Testing
import QinXuCore
@testable import QinXuApp

@Suite @MainActor struct PracticeViewModelTests {
    private final class Clock { var now: TimeInterval = 0 }

    private func score() -> PianoScore {
        PianoScore(id: "app-test-score", title: "应用会话测试", tempoBPM: 60,
                   beatsPerMeasure: 4, beatUnit: 4,
                   notes: [ScoreNote(id: "app-c", midi: 60, startBeat: 0, durationBeats: 1, step: "C", octave: 4),
                           ScoreNote(id: "app-d", midi: 62, startBeat: 1, durationBeats: 1, step: "D", octave: 4)],
                   measures: [ScoreMeasure(number: 1, startBeat: 0, durationBeats: 2)])
    }

    private func makeModel(in directory: URL, clock: Clock) throws -> PracticeViewModel {
        let store = LocalLibraryStore(url: directory.appendingPathComponent("library.json"))
        let piece = score()
        try store.save(scores: [piece], history: [], lastScoreID: piece.id)
        return PracticeViewModel(storage: store, clock: { clock.now }, automaticTimer: false, deviceAccessEnabled: false)
    }

    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("qinxu-app-test-" + UUID().uuidString) }

    @Test func rhythmCountInIgnoresInputAndResumeFreezesMusicalTime() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.mode = .rhythm; model.reconfigure(); model.togglePlayback()
        #expect(model.isPlaying && !model.engine.isRunning)
        #expect(model.countdown == 4)
        clock.now = 2; model.tick(); model.press(60); model.release(60)
        #expect(model.engine.correctCount == 0 && model.engine.heldPitches.isEmpty)
        #expect(model.countdown == 2)
        clock.now = 4; model.tick(); model.press(60)
        #expect(model.countdown == nil && model.engine.correctCount == 1)
        clock.now = 4.25; model.release(60)
        clock.now = 4.5; model.togglePlayback()
        let pausedBeat = model.engine.currentBeat
        clock.now = 100; model.tick()
        #expect(!model.isPlaying && model.engine.currentBeat == pausedBeat)
        model.togglePlayback()
        #expect(model.countdown == 4)
        clock.now = 104.5; model.tick(); model.press(62)
        #expect(abs(model.engine.currentBeat - 1) < 0.0001)
        #expect(model.engine.correctCount == 2 && model.engine.missedCount == 0)
    }

    @Test func cancellingCountInOrBackgroundingCannotResumeLater() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.mode = .rhythm; model.reconfigure(); model.togglePlayback()
        clock.now = 1; model.togglePlayback()
        clock.now = 20; model.tick()
        #expect(!model.isPlaying && model.countdown == nil)
        model.togglePlayback(); model.suspendForBackground()
        clock.now = 40; model.tick()
        #expect(!model.isPlaying && model.engine.correctCount == 0)
    }

    @Test func pauseOnFinalBeatSavesOnceWithoutRestartingEnabledLoop() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.mode = .rhythm; model.loopEnabled = true; model.reconfigure(); model.togglePlayback()
        clock.now = 4; model.tick(); model.press(60)
        clock.now = 4.5; model.release(60)
        clock.now = 5; model.press(62)
        clock.now = 5.5; model.release(62)
        clock.now = 6; model.togglePlayback()
        #expect(model.engine.isFinished && !model.isPlaying)
        #expect(model.history.count == 1)
        clock.now = 20; model.tick()
        #expect(!model.isPlaying && model.engine.isFinished && model.history.count == 1)
        let loaded = LocalLibraryStore(url: folder.appendingPathComponent("library.json")).load()
        #expect(loaded.history.count == 1 && loaded.history[0].correct == 2)
    }

    @Test func switchingInputsClearsHeldNotesAndPauses() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.togglePlayback(); model.press(60)
        #expect(model.engine.heldPitches == [60])
        model.setInputMode(.midi)
        #expect(!model.isPlaying && model.engine.heldPitches.isEmpty)
        model.press(62)
        #expect(model.engine.correctCount == 0)
        model.togglePlayback()
        #expect(!model.isPlaying && model.errorMessage?.contains("MIDI") == true)
    }

    @Test func microphonePendingStartCanBeCancelledBeforeDeviceWork() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.setInputMode(.microphone); model.togglePlayback()
        #expect(model.isStartingInput && model.isPlaying)
        model.togglePlayback()
        #expect(!model.isStartingInput && !model.isPlaying)
        await Task.yield()
        #expect(!model.microphone.isActive && !model.engine.isRunning)
        // The cancelled task must not even call the disabled service's start method.
        #expect(!model.microphone.status.contains("已停用"))
    }

    @Test func polyphonicInputKeepsBothHandsButCannotStartAfterCancellation() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.mode = .rhythm
        model.setInputMode(.microphonePolyphonic)
        #expect(model.mode == .wait && model.hand == .both)
        model.togglePlayback()
        #expect(model.isStartingInput)
        model.suspendForBackground()
        await Task.yield()
        #expect(!model.polyphonicMicrophone.isActive && !model.engine.isRunning && !model.isStartingInput)
        #expect(!model.polyphonicMicrophone.status.contains("已停用"))
    }

    @Test func polyphonicSourceAcceptsBothHandsChordEventsAndPausesOnFailure() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        var chord = score()
        chord.id = "both-hand-chord"
        chord.notes[1].startBeat = 0
        chord.notes[1].midi = 48
        chord.notes[1].staff = 2
        model.scores.append(chord); model.selectScore(chord.id)
        model.setInputMode(.microphonePolyphonic)
        model.engine.start(at: 0)
        model.polyphonicMicrophone.onEvent?(.on(pitch: 48, velocity: 80), 0)
        model.polyphonicMicrophone.onEvent?(.on(pitch: 60, velocity: 80), 0)
        #expect(model.engine.correctCount == 2)
        model.restart(); model.engine.start(at: 1)
        model.polyphonicMicrophone.stop()
        #expect(!model.engine.isRunning && !model.isPlaying)
    }

    @Test func microphoneRejectsPolyphonyWithoutOpeningDevice() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        var chord = score(); chord.id = "test-chord"
        chord.notes[1].startBeat = 0
        model.scores.append(chord); model.selectScore(chord.id); model.setInputMode(.microphone)
        model.togglePlayback()
        #expect(!model.isPlaying && !model.microphone.isActive)
        #expect(model.errorMessage?.contains("和弦") == true)
    }

    @Test func completedWaitSessionPersistsOnlyOnce() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.togglePlayback(); clock.now = 0.2; model.press(60)
        clock.now = 1.2; model.release(60); model.press(62)
        #expect(model.engine.isFinished && model.history.count == 1)
        clock.now = 2.2; model.release(62); model.tick(); model.tick()
        #expect(model.history.count == 1)
        #expect(model.engine.durationFeedback?.contains("合适") == true)
        let restored = PracticeViewModel(storage: LocalLibraryStore(url: folder.appendingPathComponent("library.json")), automaticTimer: false, deviceAccessEnabled: false)
        #expect(restored.selectedScoreID == model.selectedScoreID && restored.history.count == 1)
    }

    @Test func waitingLoopKeepsFinalLongNoteUntilItsWrittenEnd() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        var long = score()
        long.id = "long-loop"
        long.notes = [.init(id: "whole", midi: 60, startBeat: 0, durationBeats: 4)]
        long.measures = [.init(number: 1, startBeat: 0, durationBeats: 4)]
        model.scores.append(long); model.selectScore(long.id)
        model.loopEnabled = true; model.reconfigure(); model.togglePlayback()
        clock.now = 0.1; model.press(60); model.release(60)
        #expect(model.engine.isFinished && model.sustainedPitches == [60])
        #expect(model.engine.heldPitches.isEmpty)
        model.press(62)
        #expect(model.engine.heldPitches.isEmpty && model.engine.wrongCount == 0)
        clock.now = 2; model.tick()
        #expect(model.engine.isFinished && model.sustainedPitches == [60])
        clock.now = 4.1; model.tick()
        #expect(model.engine.isRunning && !model.engine.isFinished)
        #expect(model.sustainedPitches.isEmpty && model.engine.correctCount == 0)
        #expect(model.history.count == 1)
    }

    @Test func microphoneStoppingDuringLoopTailCannotRestartTheEngine() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        var long = score()
        long.id = "microphone-long-loop"
        long.notes = [.init(id: "whole", midi: 60, startBeat: 0, durationBeats: 4)]
        model.scores.append(long); model.selectScore(long.id)
        model.loopEnabled = true; model.setInputMode(.microphonePolyphonic)
        model.engine.start(at: 0)
        clock.now = 0.1
        model.polyphonicMicrophone.onEvent?(.on(pitch: 60, velocity: 80), 0.1)
        #expect(model.engine.isFinished && model.isPlaying)
        model.polyphonicMicrophone.stop()
        #expect(!model.isPlaying && model.sustainedPitches.isEmpty)
        clock.now = 10; model.tick()
        #expect(!model.engine.isRunning)
    }

    @Test func failedImportWritePreservesCurrentSelectionAndSession() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blockedDirectory = folder.appendingPathComponent("not-a-directory")
        try Data("keep".utf8).write(to: blockedDirectory)
        let model = PracticeViewModel(storage: LocalLibraryStore(url: blockedDirectory.appendingPathComponent("library.json")), automaticTimer: false, deviceAccessEnabled: false)
        model.togglePlayback()
        let originalID = model.selectedScoreID, count = model.scores.count
        let xml = folder.appendingPathComponent("valid.musicxml")
        try Data(Self.validXML.utf8).write(to: xml)
        model.importScore(from: xml)
        #expect(model.errorMessage != nil)
        #expect(model.scores.count == count && model.selectedScoreID == originalID && model.isPlaying)
        #expect(try String(contentsOf: blockedDirectory, encoding: .utf8) == "keep")
    }

    @Test func validImportPersistsAndOversizedImportKeepsPreviousScore() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        let xml = folder.appendingPathComponent("valid.musicxml")
        try Data(Self.validXML.utf8).write(to: xml)
        model.importScore(from: xml)
        #expect(model.errorMessage == nil)
        #expect(model.selectedScore.title == "导入测试" && model.selectedScore.notes.first?.midi == 60)
        let selected = model.selectedScoreID, count = model.scores.count
        let loaded = LocalLibraryStore(url: folder.appendingPathComponent("library.json")).load()
        #expect(loaded.lastScoreID == selected && loaded.scores.contains(where: { $0.id == selected }))
        let large = folder.appendingPathComponent("too-large.musicxml")
        try Data(repeating: 32, count: 5_000_001).write(to: large)
        model.importScore(from: large)
        #expect(model.errorMessage?.contains("5 MB") == true)
        #expect(model.selectedScoreID == selected && model.scores.count == count)
    }

    private static let validXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <score-partwise version="4.0"><work><work-title>导入测试</work-title></work>
    <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
    <part id="P1"><measure number="1"><attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>
    <note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration><type>whole</type></note>
    </measure></part></score-partwise>
    """
}
