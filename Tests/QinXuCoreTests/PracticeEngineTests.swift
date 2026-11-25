import Foundation
import Testing
@testable import QinXuCore

@Suite struct PracticeEngineTests {
    private func note(_ id: String, _ pitch: Int, _ beat: Double, staff: Int = 1, measure: Int = 1) -> ScoreNote {
        .init(id: id, midi: pitch, startBeat: beat, durationBeats: 1, staff: staff, measure: measure)
    }
    private func score(_ notes: [ScoreNote]) -> PianoScore {
        .init(title: "测试", tempoBPM: 60, notes: notes,
              measures: [.init(number: 1, startBeat: 0, durationBeats: 4)])
    }

    @Test func bufferedWaitingPreservesSpacingAndDoesNotMergeSeparateNotesIntoChord() {
        let chord = score([note("left", 48, 0, staff: 2), note("right", 60, 0)])
        var e = PracticeEngine(score: chord, inputLagTolerance: 3, evaluatesNoteDuration: false)
        e.start(at: 10); e.tick(at: 12.4)
        e.receive(.on(pitch: 48, velocity: 80), at: 10.1)
        e.receive(.off(pitch: 48), at: 10.3)
        e.receive(.on(pitch: 60, velocity: 80), at: 11.3)
        #expect(e.correctCount == 0 && !e.isFinished)
        e.receive(.off(pitch: 60), at: 11.5)
        e.receive(.on(pitch: 48, velocity: 80), at: 11.8)
        e.receive(.on(pitch: 60, velocity: 80), at: 11.85)
        #expect(e.correctCount == 2 && e.isFinished)
        e.receive(.off(pitch: 48), at: 12)
        e.receive(.off(pitch: 60), at: 12)
        #expect(e.durationFeedback == nil)
    }

    @Test func bufferedWaitingRejectsPreviousRunAndBoundedlyOldEvents() {
        let piece = score([note("first", 60, 0), note("next", 62, 1)])
        var e = PracticeEngine(score: piece, inputLagTolerance: 3, evaluatesNoteDuration: false)
        e.start(at: 10); e.tick(at: 14)
        e.receive(.on(pitch: 60, velocity: 80), at: 10.1)
        #expect(e.correctCount == 0)
        e.receive(.off(pitch: 60), at: 10.2)
        e.pause(at: 14); e.receive(.allNotesOff, at: 14); e.start(at: 20)
        e.receive(.on(pitch: 60, velocity: 80), at: 13)
        #expect(e.correctCount == 0 && e.heldPitches.isEmpty)
        e.tick(at: 21)
        e.receive(.on(pitch: 60, velocity: 80), at: 20.1)
        #expect(e.correctCount == 1)
    }

    @Test func realtimeDefaultsAndRhythmCannotOptIntoLongBufferedInput() {
        let piece = score([note("first", 60, 0), note("next", 62, 1)])
        var waiting = PracticeEngine(score: piece)
        waiting.start(at: 0); waiting.tick(at: 2)
        waiting.receive(.on(pitch: 60, velocity: 80), at: 0.1)
        #expect(waiting.correctCount == 0)
        var rhythm = PracticeEngine(score: piece, mode: .rhythm, inputLagTolerance: 3)
        rhythm.start(at: 0); rhythm.tick(at: 1)
        rhythm.receive(.on(pitch: 60, velocity: 80), at: 0.1)
        #expect(rhythm.correctCount == 0)
    }

    @Test func chordCompletionAndFreshRepeatedOnset() {
        var e = PracticeEngine(score: score([note("c", 60, 0), note("e", 64, 0), note("repeat", 60, 1)]))
        e.start(at: 10)
        e.receive(.on(pitch: 60, velocity: 90), at: 10)
        expectEqual(e.correctCount, 0)
        e.receive(.on(pitch: 64, velocity: 90), at: 10.2)
        expectEqual(e.correctCount, 2)
        expectEqual(e.expectedNotes.map(\.id), ["repeat"])
        e.receive(.on(pitch: 60, velocity: 90), at: 10.3)
        expectFalse(e.isFinished)
        e.receive(.off(pitch: 60), at: 10.4)
        e.receive(.on(pitch: 60, velocity: 90), at: 10.5)
        expectTrue(e.isFinished)
        expectEqual(e.correctCount, 3)
    }

    @Test func wrongAndMissedNotesDoNotShiftTimeline() {
        var e = PracticeEngine(score: score([note("c", 60, 0), note("d", 62, 1), note("e", 64, 2)]), mode: .rhythm)
        e.start(at: 100)
        e.receive(.on(pitch: 61, velocity: 90), at: 100.05)
        e.tick(at: 100.4)
        expectEqual(e.verdicts["c"], .missed)
        e.receive(.on(pitch: 62, velocity: 90), at: 101)
        e.receive(.on(pitch: 64, velocity: 90), at: 102.2)
        expectEqual(e.verdicts["d"], .correct)
        expectEqual(e.verdicts["e"], .late)
        expectEqual(e.correctCount, 2)
        expectEqual(e.missedCount, 1)
        expectEqual(e.wrongCount, 1)
        e.tick(at: 104)
        expectTrue(e.isFinished)
    }

    @Test func pauseFreezesClockAndSuppressesInterruptedDuration() {
        var e = PracticeEngine(score: score([note("first", 60, 0), note("later", 62, 2)]), mode: .rhythm)
        e.start(at: 10)
        e.receive(.on(pitch: 60, velocity: 90), at: 10)
        e.pause(at: 10.1)
        e.receive(.off(pitch: 60), at: 40)
        expectNil(e.durationFeedback)
        expectEqual(e.currentBeat, 0.1, accuracy: 0.0001)
        e.start(at: 50)
        e.receive(.on(pitch: 62, velocity: 90), at: 51.9)
        expectEqual(e.correctCount, 2)
        expectEqual(e.summary().durationSeconds, 2, accuracy: 0.0001)
    }

    @Test func finalNoteReleaseStillMeasuresDurationAndMentionsPedal() {
        var e = PracticeEngine(score: score([note("c", 60, 0)]))
        e.start(at: 10)
        e.receive(.sustain(true), at: 10)
        e.receive(.on(pitch: 60, velocity: 90), at: 10)
        expectTrue(e.isFinished)
        e.receive(.off(pitch: 60), at: 11)
        expectTrue(e.durationFeedback?.contains("合适") == true)
        expectTrue(e.durationFeedback?.contains("松键不代表声音结束") == true)
    }

    @Test func rangeAndHandUseOriginalScoreBeats() {
        let source = PianoScore(title: "范围", tempoBPM: 60,
            notes: [note("old", 60, 0), note("right", 64, 8, measure: 3), note("left", 48, 8, staff: 2, measure: 3)],
            measures: [.init(number: 1, startBeat: 0, durationBeats: 4), .init(number: 3, startBeat: 8, durationBeats: 4)])
        var e = PracticeEngine(score: source, mode: .rhythm, hand: .left, measureRange: 3...3)
        expectEqual(e.currentBeat, 8)
        expectEqual(e.expectedNotes.map(\.id), ["left"])
        e.start(at: 5)
        e.receive(.on(pitch: 48, velocity: 90), at: 5)
        expectEqual(e.correctCount, 1)
        expectNil(e.verdicts["right"])
        e.tick(at: 9)
        expectTrue(e.isFinished)
        expectEqual(e.currentBeat, 12)
    }

    @Test func queuedMIDIOnsetUsesAcquisitionTimeWithoutRewindingTransport() {
        var e = PracticeEngine(score: score([note("c", 60, 0), note("d", 62, 1)]), mode: .rhythm)
        e.start(at: 10)
        e.tick(at: 10.18)
        e.receive(.on(pitch: 60, velocity: 90), at: 10.02)
        expectEqual(e.verdicts["c"], .correct)
        expectEqual(e.currentBeat, 0.18, accuracy: 0.00001)
        expectEqual(e.summary().durationSeconds, 0.18, accuracy: 0.00001)
    }

    @Test func queuedOnsetCanCorrectRecentMissButCannotResurrectFinishedRun() {
        var e = PracticeEngine(score: score([note("c", 60, 0), note("d", 62, 1)]), mode: .rhythm)
        e.start(at: 10)
        e.tick(at: 10.31)
        expectEqual(e.missedCount, 1)
        e.receive(.on(pitch: 60, velocity: 90), at: 10.10)
        expectEqual(e.correctCount, 1)
        expectEqual(e.missedCount, 0)
        e.tick(at: 14)
        expectTrue(e.isFinished)
        e.receive(.on(pitch: 62, velocity: 90), at: 11)
        expectEqual(e.correctCount, 1)
        expectEqual(e.missedCount, 1)
    }

    @Test func staleOrPreviousRunOnsetsAreNotGraded() {
        var e = PracticeEngine(score: score([note("c", 60, 0), note("d", 62, 1)]), mode: .rhythm)
        e.start(at: 10)
        e.tick(at: 10.8)
        e.receive(.on(pitch: 60, velocity: 90), at: 10.1)
        expectEqual(e.correctCount, 0)
        expectEqual(e.wrongCount, 0)
        expectEqual(e.missedCount, 1)
        e.reset()
        e.start(at: 20)
        e.receive(.on(pitch: 60, velocity: 90), at: 10)
        expectTrue(e.heldPitches.isEmpty)
        e.receive(.on(pitch: 60, velocity: 90), at: 20)
        expectEqual(e.correctCount, 1)
    }

    @Test func queuedReleaseUsesAcquisitionTimeForDuration() {
        var e = PracticeEngine(score: score([note("c", 60, 0), note("d", 62, 2)]), mode: .rhythm)
        e.start(at: 10)
        e.receive(.on(pitch: 60, velocity: 90), at: 10)
        e.tick(at: 11.4)
        e.receive(.off(pitch: 60), at: 11)
        expectTrue(e.durationFeedback?.contains("合适") == true)
        expectEqual(e.currentBeat, 1.4, accuracy: 0.00001)
    }

    @Test func queuedRolledChordAndSustainDoNotInventHeldKeys() {
        let chord = score([note("c", 60, 0), note("e", 64, 0)])
        var e = PracticeEngine(score: chord)
        e.start(at: 10)
        e.receive(.on(pitch: 60, velocity: 90), at: 10)
        e.receive(.off(pitch: 60), at: 10.1)
        e.tick(at: 10.5)
        e.receive(.on(pitch: 64, velocity: 90), at: 10.3)
        expectTrue(e.isFinished)

        e.reset()
        e.start(at: 20)
        e.receive(.sustain(true), at: 20)
        e.receive(.on(pitch: 60, velocity: 90), at: 20)
        e.receive(.off(pitch: 60), at: 20.1)
        e.receive(.on(pitch: 64, velocity: 90), at: 20.6)
        expectFalse(e.isFinished)
        expectFalse(e.heldPitches.contains(60))
        e.receive(.on(pitch: 60, velocity: 90), at: 23)
        expectTrue(e.isFinished, "E remained physically held, so its chord candidate is valid")
    }

    @Test func nonFiniteEventTimeCannotScoreOrCorruptHeldState() {
        var e = PracticeEngine(score: score([note("c", 60, 0)]))
        e.start(at: 10)
        e.receive(.on(pitch: 60, velocity: 90), at: .nan)
        expectFalse(e.isFinished)
        expectTrue(e.heldPitches.isEmpty)
        e.receive(.on(pitch: 60, velocity: 90), at: 10)
        expectTrue(e.isFinished)
    }

}
