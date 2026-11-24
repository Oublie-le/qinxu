import Testing
@testable import PianoCore

@Suite struct PracticeTimingTests {
    @Test func eighthNoteMeterAccentsEveryMeasureIncludingHalfQuarterBoundaries() {
        let score = PianoScore(title: "3/8", beatsPerMeasure: 3, beatUnit: 8, notes: [], measures: [
            ScoreMeasure(number: 1, startBeat: 0, durationBeats: 1.5),
            ScoreMeasure(number: 2, startBeat: 1.5, durationBeats: 1.5)
        ])
        #expect(PracticeTiming.metronomePosition(atQuarterBeat: 0.5, score: score)?.pulse == 1)
        #expect(PracticeTiming.metronomePosition(atQuarterBeat: 1.51, score: score)?.accented == true)
        #expect(PracticeTiming.metronomePosition(atQuarterBeat: 1.51, score: score)?.measure == 2)
    }
    @Test func pickupResetsMetronomeToActualMeasureStart() {
        let score = PianoScore(title: "pickup", notes: [], measures: [
            ScoreMeasure(number: 1, startBeat: 0, durationBeats: 0.5),
            ScoreMeasure(number: 2, startBeat: 0.5, durationBeats: 4)
        ])
        #expect(PracticeTiming.metronomePosition(atQuarterBeat: 0.51, score: score)?.accented == true)
    }
    @Test func loopCannotSilentlyDiscardATiedNoteAtItsStart() {
        let score = PianoScore(title: "tie", notes: [ScoreNote(midi: 60, startBeat: 0, durationBeats: 8, staff: 1, measure: 1)], measures: [
            ScoreMeasure(number: 1, startBeat: 0, durationBeats: 4),
            ScoreMeasure(number: 2, startBeat: 4, durationBeats: 4)
        ])
        #expect(PracticeTiming.loopStartIssue(score: score, hand: .right, startMeasure: 2) != nil)
        #expect(PracticeTiming.loopStartIssue(score: score, hand: .right, startMeasure: 1) == nil)
        #expect(PracticeTiming.loopStartIssue(score: score, hand: .left, startMeasure: 2) == nil)
    }
}
