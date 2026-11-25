import Testing
@testable import QinXuCore

@Suite struct PracticeSustainGuidanceTests {
    private var piece: PianoScore {
        PianoScore(title: "长音与换指", tempoBPM: 60, notes: [
            .init(id: "bass", midi: 48, startBeat: 0, durationBeats: 4, staff: 2),
            .init(id: "first", midi: 60, startBeat: 0, durationBeats: 1),
            .init(id: "next", midi: 62, startBeat: 1, durationBeats: 1)
        ], measures: [.init(number: 1, startBeat: 0, durationBeats: 4)])
    }

    @Test func leftHandLongNoteRemainsWhenRightHandAdvancesAndSoundReleases() {
        var engine = PracticeEngine(score: piece)
        engine.start(at: 10)
        engine.receive(.on(pitch: 48, velocity: 80), at: 10.1)
        engine.receive(.on(pitch: 60, velocity: 80), at: 10.1)
        #expect(engine.expectedNotes.map(\.midi) == [62])
        engine.receive(.off(pitch: 48), at: 10.5)
        engine.receive(.off(pitch: 60), at: 10.5)
        #expect(engine.heldPitches.isEmpty)
        #expect(engine.sustainedPitches(at: 10.8) == [48, 60])
        engine.receive(.on(pitch: 62, velocity: 80), at: 11.1)
        #expect(engine.isFinished && engine.correctCount == 3)
        #expect(engine.sustainedPitches(at: 11.2) == [48, 62])
        #expect(engine.sustainedPitches(at: 12.2) == [48])
        #expect(engine.sustainedPitches(at: 14.1).isEmpty)
    }

    @Test func microphoneBufferDoesNotRestartWrittenDurationAtDeliveryTime() {
        var engine = PracticeEngine(score: piece, inputLagTolerance: 3, evaluatesNoteDuration: false)
        engine.start(at: 10)
        engine.tick(at: 12.4)
        engine.receive(.on(pitch: 48, velocity: 80), at: 10.1)
        engine.receive(.on(pitch: 60, velocity: 80), at: 10.1)
        #expect(engine.sustainedPitches(at: 12.4) == [48])
        // The sounding bass does not repeatedly score or consume the next note.
        engine.receive(.on(pitch: 48, velocity: 80), at: 12.5)
        #expect(engine.correctCount == 2 && engine.wrongCount == 0)
        #expect(engine.sustainedPitches(at: 14.1).isEmpty)
        #expect(engine.durationFeedback == nil)
    }

    @Test func tempoPauseResetAndAllNotesOffBoundTheVisualGuide() {
        var engine = PracticeEngine(score: piece, tempoBPM: 120)
        engine.start(at: 10)
        engine.receive(.on(pitch: 48, velocity: 80), at: 10)
        engine.receive(.on(pitch: 60, velocity: 80), at: 10)
        #expect(engine.sustainedPitches(at: 10.6) == [48])
        #expect(engine.sustainedPitches(at: 12).isEmpty)
        engine.pause(at: 10.7)
        #expect(engine.sustainedPitches(at: 10.8).isEmpty)
        engine.reset(); engine.start(at: 20)
        engine.receive(.allNotesOff, at: 20)
        #expect(engine.sustainedPitches(at: 20).isEmpty)
        #expect(engine.sustainedPitches(at: .nan).isEmpty)
    }
}
