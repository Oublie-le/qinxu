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
        try MetronomeSettingsStore(libraryURL: store.url).save(.init(tempoBPM: 60))
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

    @Test func reenabledMetronomeKeepsTheCountInBeatAndSubdivision() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        #expect(model.updateMetronomeSettings(.init(tempoBPM: 60, clickNote: .eighth)))
        model.mode = .rhythm; model.reconfigure()
        clock.now = 10; model.togglePlayback()
        clock.now = 11.5; model.tick()
        #expect(model.countdown == 3 && !model.engine.isRunning)
        #expect(model.metronomeBeat == 2 && model.metronomeSubdivision == 2)
        model.toggleMetronome()
        #expect(!model.metronomeRunning && model.isPlaying)
        model.toggleMetronome()
        #expect(model.metronomeBeat == 2 && model.metronomeSubdivision == 2)
        clock.now = 12; model.tick()
        #expect(model.countdown == 2 && model.metronomeBeat == 3 && model.metronomeSubdivision == 1)
        clock.now = 14; model.tick()
        #expect(model.countdown == nil && model.engine.isRunning)
        #expect(model.metronomeBeat == 1 && model.metronomeSubdivision == 1)
        #expect(abs(model.engine.currentBeat) < 0.0001)
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

    @Test func holdCountdownShrinksAndReportWaitsForFinalWrittenDuration() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.togglePlayback(); model.press(60)
        #expect(model.sustainGuidance.first?.remainingSeconds == 1)
        clock.now = 0.4; model.tick()
        #expect(abs((model.sustainGuidance.first?.remainingFraction ?? 0) - 0.6) < 0.0001)
        model.release(60); clock.now = 1; model.press(62)
        #expect(model.engine.isFinished && !model.showingReport && model.isPlaying)
        clock.now = 1.8; model.tick()
        #expect(!model.showingReport && model.sustainedPitches == [62])
        clock.now = 2; model.tick()
        #expect(model.showingReport && !model.isPlaying && model.sustainGuidance.isEmpty)
        #expect(model.latestReport?.correct == 2 && model.latestReport?.overallScore == nil)
        #expect(model.history.first?.report?.correct == 2)
    }

    @Test func pausingDuringFinalHoldCancelsAutomaticReport() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.togglePlayback(); model.press(60); model.release(60); model.press(62)
        model.suspendForBackground()
        clock.now = 100; model.tick()
        #expect(!model.showingReport && !model.metronomeRunning && model.sustainGuidance.isEmpty)
        model.showCurrentReport()
        #expect(model.showingReport && model.latestReport?.correct == 2)
    }

    @Test func metronomeRunsIndependentlyAndStopsOnLifecycleChanges() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.toggleMetronome()
        #expect(model.metronomeRunning && model.metronomeBeat == 1 && !model.isPlaying)
        clock.now = 1; model.tick(); #expect(model.metronomeBeat == 2)
        clock.now = 4; model.tick(); #expect(model.metronomeBeat == 1)
        model.setInputMode(.microphonePolyphonic)
        #expect(!model.metronomeRunning && model.metronomeBeat == nil)
        model.toggleMetronome(); clock.now = 5; model.tick()
        #expect(model.metronomeRunning && model.metronomeBeat == 2)
        #expect(!model.polyphonicMicrophone.isActive && model.errorMessage == nil)
        model.suspendForBackground(); clock.now = 10; model.tick()
        #expect(!model.metronomeRunning && model.metronomeBeat == nil)
    }

    @Test func metronomeRemainsStoppedWhenUserDisablesItBeforePlaying() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.toggleMetronome(); model.toggleMetronome(); model.togglePlayback()
        clock.now = 1; model.tick()
        #expect(model.isPlaying && !model.metronomeRunning && model.metronomeBeat == nil)
    }

    @Test func globalMeterSpeedAndSubdivisionsSurviveSelectionAndRelaunch() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        let settings = GlobalMetronomeSettings(beatsPerMeasure: 3, tempoBPM: 90, clickNote: .eighth)
        #expect(model.updateMetronomeSettings(settings))
        model.toggleMetronome()
        clock.now = 1; model.tick()
        #expect(model.metronomeBeat == 2 && model.metronomeSubdivision == 2)
        model.selectScore("demo-chords")
        #expect(model.metronomeSettings == settings && model.tempo == 90)
        #expect(model.metronomeRunning && model.metronomeBeat == 2 && model.metronomeSubdivision == 2)
        model.pausePractice(); model.openMetronomeSettings()
        #expect(model.metronomeRunning)
        model.showingMetronomeSettings = false
        model.selectScore("demo-rhythm")
        clock.now = 2; model.tick()
        #expect(model.metronomeBeat == 1 && model.metronomeSubdivision == 1)
        #expect(model.engine.tempoBPM == 90 && model.selectedScore.tempoBPM == 66)
        model.suspendForBackground()
        #expect(!model.metronomeRunning)
        let restored = PracticeViewModel(storage: LocalLibraryStore(url: folder.appendingPathComponent("library.json")),
            clock: { clock.now }, automaticTimer: false, deviceAccessEnabled: false)
        #expect(restored.metronomeSettings == settings && restored.tempo == 90)
        #expect(!restored.metronomeRunning && restored.metronomeBeat == nil)
    }

    @Test func globalSoundPreferenceDoesNotResetCurrentPractice() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.togglePlayback(); model.press(60)
        model.metronomeEnabled = false
        #expect(model.isPlaying && model.engine.correctCount == 1 && model.metronomeRunning)
        #expect(model.metronomeSettings.soundEnabled == false)
        #expect(MetronomeSettingsStore(libraryURL: folder.appendingPathComponent("library.json")).load().settings.soundEnabled == false)
        model.metronomeEnabled = true
        #expect(model.isPlaying && model.engine.correctCount == 1)
        model.pausePractice()
        #expect(!model.metronomeRunning)
    }

    @Test func globalTempoReferenceControlsDurationAndRhythmCountIn() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        #expect(model.updateMetronomeSettings(.init(beatsPerMeasure: 6, beatUnit: 8, tempoBPM: 80,
                                                   tempoNote: .dottedQuarter, clickNote: .sixteenth)))
        #expect(model.tempo == 120 && model.selectedScore.beatsPerMeasure == 4)
        model.mode = .rhythm; model.reconfigure(); model.togglePlayback()
        #expect(model.countdown == 6)
        clock.now = 0.125; model.tick()
        #expect(model.metronomeBeat == 1 && model.metronomeSubdivision == 2)
        clock.now = 1.5; model.tick(); model.press(60)
        #expect(model.countdown == nil && model.engine.correctCount == 1)
        #expect(model.sustainGuidance.first?.totalSeconds == 0.5)
        #expect(model.metronomeBeat == 1 && model.metronomeSubdivision == 1)
    }

    @Test func invalidOrUnwritableGlobalSettingsPreservePublishedStateAndSession() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.togglePlayback(); model.press(60)
        let original = model.metronomeSettings
        #expect(!model.updateMetronomeSettings(.init(tempoBPM: 300, tempoNote: .half)))
        #expect(model.metronomeSettings == original && model.isPlaying && model.engine.correctCount == 1)
        let store = MetronomeSettingsStore(libraryURL: folder.appendingPathComponent("library.json"))
        try FileManager.default.removeItem(at: store.url)
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: false)
        #expect(!model.updateMetronomeSettings(.init(tempoBPM: 96)))
        #expect(model.metronomeSettings == original && model.tempo == 60)
        #expect(model.isPlaying && model.engine.correctCount == 1)
        #expect(model.errorMessage?.contains("保存全局节拍器失败") == true)
    }

    @Test func microphoneSelectionAllowsStandaloneSoundButStartingRecordingDisablesIt() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.setInputMode(.microphonePolyphonic)
        model.toggleMetronome()
        #expect(model.metronomeSoundAvailable && model.metronomeRunning)
        model.togglePlayback()
        #expect(model.isStartingInput && !model.metronomeSoundAvailable)
        model.suspendForBackground()
        await Task.yield()
        #expect(!model.polyphonicMicrophone.isActive && model.metronomeSoundAvailable && !model.metronomeRunning)
    }

    @Test func failedMicrophoneStartPreservesIndependentMetronomePhase() async throws {
        for input in [InputMode.microphone, .microphonePolyphonic] {
            let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
            let clock = Clock(), model = try makeModel(in: folder, clock: clock)
            #expect(model.updateMetronomeSettings(.init(tempoBPM: 60, clickNote: .eighth)))
            model.setInputMode(input)
            clock.now = 10; model.toggleMetronome()
            clock.now = 11.5; model.tick(); model.togglePlayback()
            #expect(model.isStartingInput && !model.metronomeSoundAvailable)
            // Disabled hardware makes both services fail before permissions or recording.
            for _ in 0..<100 where model.isStartingInput { await Task.yield() }
            #expect(!model.isStartingInput && !model.isPlaying)
            #expect(!model.microphone.isActive && !model.polyphonicMicrophone.isActive)
            let status = input == .microphone ? model.microphone.status : model.polyphonicMicrophone.status
            #expect(status.contains("已停用"))
            #expect(model.metronomeRunning && model.metronomeSoundAvailable && model.metronomeEnabled)
            #expect(model.metronomeBeat == 2 && model.metronomeSubdivision == 2)
            clock.now = 12; model.tick()
            #expect(model.metronomeBeat == 3 && model.metronomeSubdivision == 1)
            model.suspendForBackground()
            #expect(!model.metronomeRunning)
            // This checks lifecycle and phase only; actual sound recovery needs device access.
        }
    }

    @Test func resumingProgressKeepsTheNewGlobalSpeedAndRhythmPhase() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.togglePlayback(); model.press(60); model.pausePractice()
        #expect(model.progress(for: model.selectedScoreID)?.tempoBPM == 60)
        #expect(model.updateMetronomeSettings(.init(tempoBPM: 120, clickNote: .eighth)))
        model.resume(scoreID: model.selectedScoreID)
        #expect(model.tempo == 120 && model.engine.tempoBPM == 120)
        model.mode = .rhythm; model.reconfigure(); model.togglePlayback()
        clock.now = 2.125; model.tick(); model.pausePractice()
        #expect(abs(model.engine.currentBeat - 0.25) < 0.0001)
        clock.now = 10; model.togglePlayback()
        clock.now = 12; model.tick()
        #expect(model.metronomeBeat == 1 && model.metronomeSubdivision == 1)
        clock.now = 12.125; model.tick()
        #expect(model.metronomeBeat == 1 && model.metronomeSubdivision == 2)
    }

    @Test func savedProgressRestoresMeasureSettingsAndDoesNotGradeResumeAsWholePiece() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        var piece = score(); piece.id = "two-measures"
        piece.measures = [.init(number: 1, startBeat: 0, durationBeats: 1), .init(number: 2, startBeat: 1, durationBeats: 1)]
        piece.notes[1].measure = 2
        model.scores.append(piece); model.selectScore(piece.id)
        model.hand = .right
        #expect(model.updateMetronomeSettings(.init(tempoBPM: 72)))
        model.togglePlayback(); model.press(60)
        #expect(model.progress(for: piece.id)?.measure == 2)
        model.suspendForBackground()
        let restored = PracticeViewModel(storage: LocalLibraryStore(url: folder.appendingPathComponent("library.json")),
                                         clock: { clock.now }, automaticTimer: false, deviceAccessEnabled: false)
        restored.resume(scoreID: piece.id)
        #expect(restored.practiceStartMeasure == 2 && restored.hand == .right && restored.tempo == 72)
        #expect(restored.engine.expectedNotes.first?.midi == 62 && !restored.isPlaying)
        restored.togglePlayback(); restored.press(62)
        #expect(restored.latestReport?.startMeasure == 2 && restored.latestReport?.isComplete == false)
        #expect(restored.latestReport?.overallScore == nil && restored.progress(for: piece.id)?.isCompleted == true)
        clock.now = 5; restored.tick(); restored.showingReport = false
        restored.togglePlayback()
        #expect(restored.practiceStartMeasure == 1 && restored.engine.expectedNotes.first?.midi == 60)
        restored.restart()
        #expect(restored.practiceStartMeasure == 1 && restored.engine.expectedNotes.first?.midi == 60)
    }

    @Test func scoreChangeSavesOldScoreAndUnplayedSelectionDoesNotOverwriteProgress() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.togglePlayback(); model.press(60)
        let oldID = model.selectedScoreID
        let anotherID = DemoScores.all[0].id
        model.selectScore(anotherID)
        #expect(model.progress(for: oldID)?.scoreID == oldID)
        #expect(model.progress(for: anotherID) == nil)
        model.suspendForBackground()
        #expect(model.progress(for: anotherID) == nil)
    }

    @Test func completedShortLoopSavesItsActualMeasureNotScoreEnd() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        var piece = score(); piece.id = "short-loop-position"
        piece.measures = [.init(number: 1, startBeat: 0, durationBeats: 1), .init(number: 2, startBeat: 1, durationBeats: 1)]
        piece.notes[1].measure = 2
        model.scores.append(piece); model.selectScore(piece.id)
        model.practiceMeasure(1); model.togglePlayback(); model.press(60)
        #expect(model.progress(for: piece.id)?.measure == 1)
        #expect(model.progress(for: piece.id)?.isCompleted == false)
        #expect(model.latestReport?.endMeasure == 1 && !model.showingReport)
        model.practiceMeasure(2); model.togglePlayback(); model.press(62)
        #expect(model.progress(for: piece.id)?.measure == 2)
        #expect(model.progress(for: piece.id)?.isCompleted == false)
    }

    @Test func microphoneValidationUsesOnlyTheResumedRange() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        var piece = score(); piece.id = "resume-microphone-range"
        piece.measures = [.init(number: 1, startBeat: 0, durationBeats: 1), .init(number: 2, startBeat: 1, durationBeats: 1)]
        piece.notes[0].midi = 36; piece.notes[1].measure = 2
        model.scores.append(piece); model.selectScore(piece.id)
        model.togglePlayback(); model.press(36); model.suspendForBackground()
        model.resume(scoreID: piece.id); model.setInputMode(.microphone)
        model.togglePlayback()
        #expect(model.practiceStartMeasure == 2 && model.isStartingInput && model.errorMessage == nil)
        model.suspendForBackground()
        await Task.yield()
        #expect(!model.microphone.isActive && !model.isPlaying)
    }

    @Test func reportKeepsMeasuredRhythmAndHistoryPersistsItsBreakdown() throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock(), model = try makeModel(in: folder, clock: clock)
        model.mode = .rhythm; model.reconfigure(); model.togglePlayback()
        clock.now = 4; model.tick(); model.press(60); model.release(60)
        clock.now = 5.2; model.press(62); model.release(62)
        clock.now = 6.2; model.tick()
        let report = try #require(model.latestReport)
        #expect(report.isComplete && report.late == 1 && report.overallScore != nil)
        #expect(abs((report.meanAbsoluteOnsetErrorMilliseconds ?? 0) - 100) < 0.0001)
        let loaded = LocalLibraryStore(url: folder.appendingPathComponent("library.json")).load()
        #expect(loaded.history.first?.report == report)
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
