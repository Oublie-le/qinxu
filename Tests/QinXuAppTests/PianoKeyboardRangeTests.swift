import Testing
import QinXuCore
@testable import QinXuApp

@Suite struct PianoKeyboardRangeTests {
    @Test func sustainedAndHeldNotesKeepTheNextTargetMarker() {
        let sustainWithNextTarget = PianoKeyHighlight(expected: true, held: false, sustained: true)
        #expect(sustainWithNextTarget.fill == .sustained)
        #expect(sustainWithNextTarget.showsExpectedMarker)
        let soundingTarget = PianoKeyHighlight(expected: true, held: true, sustained: true)
        #expect(soundingTarget.fill == .held)
        #expect(soundingTarget.showsExpectedMarker)
        let releasedSustain = PianoKeyHighlight(expected: false, held: false, sustained: true)
        #expect(releasedSustain.fill == .sustained && !releasedSustain.showsExpectedMarker)
        #expect(PianoKeyHighlight(expected: false, held: false, sustained: false).fill == .plain)
    }

    @Test func rangeIncludesLaterNotesAndRespectsSelectedHand() {
        let score = piece(notes: [
            ScoreNote(id: "right-first", midi: 60, startBeat: 0, durationBeats: 1, staff: 1),
            ScoreNote(id: "right-last", midi: 90, startBeat: 4, durationBeats: 1, staff: 1, measure: 2),
            ScoreNote(id: "left-first", midi: 24, startBeat: 0, durationBeats: 1, staff: 2),
            ScoreNote(id: "left-last", midi: 36, startBeat: 4, durationBeats: 1, staff: 2, measure: 2)
        ])
        let right = PianoKeyboardRange.forScore(score, hand: .right)
        let left = PianoKeyboardRange.forScore(score, hand: .left)
        let both = PianoKeyboardRange.forScore(score, hand: .both)
        // Late high/low notes must already fit before the first target is played.
        #expect(right.lowerBound <= 57 && right.upperBound >= 93)
        #expect(!right.contains(24))
        #expect(left.lowerBound <= 21 && left.upperBound >= 39)
        #expect(!left.contains(90))
        #expect(score.notes.allSatisfy { both.contains($0.midi) })
    }

    @Test(arguments: [0, 60, 127])
    func shortExercisesKeepSeveralOctavesWithinMIDIBounds(pitch: Int) {
        let score = piece(notes: [ScoreNote(id: "one", midi: pitch, startBeat: 0, durationBeats: 1)])
        let range = PianoKeyboardRange.forScore(score, hand: .both)
        #expect(range.contains(pitch))
        #expect(range.lowerBound >= 0 && range.upperBound <= 127)
        #expect(range.upperBound - range.lowerBound >= 36)
        // No left-hand notes has a stable, usable default as well.
        #expect(PianoKeyboardRange.forScore(score, hand: .left) == 48...84)
    }

    private func piece(notes: [ScoreNote]) -> PianoScore {
        PianoScore(id: "keyboard-range", title: "固定键盘音域", notes: notes,
                   measures: [ScoreMeasure(number: 1, startBeat: 0, durationBeats: 4),
                              ScoreMeasure(number: 2, startBeat: 4, durationBeats: 4)])
    }
}
