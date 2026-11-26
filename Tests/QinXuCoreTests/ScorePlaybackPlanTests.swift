import Testing
@testable import QinXuCore

@Suite struct ScorePlaybackPlanTests {
    @Test func preservesChordTimingTiedDurationAndTrailingRest() throws {
        let score = PianoScore(title: "试听", tempoBPM: 80, notes: [
            ScoreNote(midi: 60, startBeat: 1, durationBeats: 4),
            ScoreNote(midi: 48, startBeat: 1, durationBeats: 1.5, staff: 2),
            ScoreNote(midi: 64, startBeat: 1, durationBeats: 1),
            ScoreNote(midi: 60, startBeat: 2, durationBeats: 1, staff: 2),
            ScoreNote(midi: 67, startBeat: 5, durationBeats: 0.5, measure: 2)
        ], measures: [
            ScoreMeasure(number: 1, startBeat: 0, durationBeats: 4),
            ScoreMeasure(number: 2, startBeat: 4, durationBeats: 4)
        ])
        let plan = try ScorePlaybackPlan(score: score)

        #expect(plan.notes.map(\.midi) == [60, 64, 48, 60, 67])
        #expect(plan.notes.map(\.staff) == [1, 1, 2, 2, 1])
        #expect(plan.notes.map(\.startBeat) == [1, 1, 1, 2, 5])
        #expect(plan.notes.map(\.endBeat) == [5, 2, 2.5, 3, 5.5])
        #expect(plan.notes[0].durationBeats == 4)
        #expect(plan.secondsPerBeat == 0.75)
        #expect(plan.durationBeats == 8)
        #expect(plan.durationSeconds == 6)
    }

    @Test func bundledDemosUseTheirScoreTempo() throws {
        for score in DemoScores.all {
            let plan = try ScorePlaybackPlan(score: score)
            #expect(plan.notes.count == score.notes.count)
            #expect(plan.tempoBPM == score.tempoBPM)
            #expect(plan.durationBeats == score.durationBeats)
        }
    }

    @Test func refusesCorruptStoredNotesWithoutTruncatingTheScore() throws {
        var score = try #require(DemoScores.all.first)
        score.notes[0].midi = 128
        #expect(throws: ScorePlaybackError.invalidTimeline) { try ScorePlaybackPlan(score: score) }
        score.notes[0].midi = 60
        score.notes[0].durationBeats = .infinity
        #expect(throws: ScorePlaybackError.invalidTimeline) { try ScorePlaybackPlan(score: score) }
        score.notes[0].durationBeats = 1
        score.tempoBPM = .nan
        #expect(throws: ScorePlaybackError.invalidTempo) { try ScorePlaybackPlan(score: score) }
    }
}
