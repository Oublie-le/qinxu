import Foundation
import Testing
@testable import QinXuCore

@Suite struct PracticeReportTests {
    private var piece: PianoScore {
        PianoScore(id: "report-piece", title: "报告测试", tempoBPM: 60, notes: [
            .init(id: "c", midi: 60, startBeat: 0, durationBeats: 0.5, measure: 1),
            .init(id: "d", midi: 62, startBeat: 1, durationBeats: 0.5, measure: 1),
            .init(id: "e", midi: 64, startBeat: 2, durationBeats: 0.5, measure: 2),
            .init(id: "f", midi: 65, startBeat: 3, durationBeats: 0.5, measure: 2)
        ], measures: [
            .init(number: 1, startBeat: 0, durationBeats: 2),
            .init(number: 2, startBeat: 2, durationBeats: 2)
        ])
    }

    private func completedRhythm() -> PracticeEngine {
        var engine = PracticeEngine(score: piece, mode: .rhythm)
        engine.start(at: 10)
        engine.receive(.on(pitch: 60, velocity: 80), at: 10)
        engine.receive(.off(pitch: 60), at: 10.3)
        engine.tick(at: 10.95)
        engine.receive(.on(pitch: 62, velocity: 80), at: 10.85) // captured 150 ms early
        engine.receive(.off(pitch: 62), at: 11.1)
        engine.receive(.on(pitch: 67, velocity: 80), at: 11.5) // rest in measure 1
        engine.receive(.off(pitch: 67), at: 11.6)
        engine.tick(at: 12.31) // temporarily marks E missed before its queued input
        engine.receive(.on(pitch: 64, velocity: 80), at: 12.25)
        engine.receive(.off(pitch: 64), at: 12.5)
        engine.tick(at: 14)
        return engine
    }

    @Test func rhythmUsesCaptureOffsetsAndTransparentFormulaIncludingRecoveredMiss() throws {
        let engine = completedRhythm()
        let report = engine.report(inputSource: "midi")
        #expect(report.isComplete && report.mode == .rhythm)
        #expect(report.correct == 3 && report.wrong == 1 && report.missed == 1)
        #expect(report.early == 1 && report.late == 1 && report.timedNoteCount == 3)
        #expect(report.totalNotes == 4 && report.evaluatedNotes == 4)
        #expect(abs(try #require(report.pitchAccuracy) - 60) < 0.000001)
        #expect(abs(try #require(report.meanAbsoluteOnsetErrorMilliseconds) - 400.0 / 3) < 0.000001)
        #expect(abs(try #require(report.meanSignedOnsetErrorMilliseconds) - 100.0 / 3) < 0.000001)
        #expect(report.rhythmScore == 50 && report.overallScore == 57)
        #expect(report.inputSource == "midi" && report.scoreID == piece.id)
        #expect(report.startMeasure == 1 && report.endMeasure == 2)
        #expect(report.measureResults[0].wrong == 1) // attributed to capture-time bar, not next target
        #expect(report.measureResults[0].early == 1 && report.measureResults[0].missed == 0)
        #expect(report.measureResults[1].late == 1 && report.measureResults[1].missed == 1)
        #expect(report.suggestions.contains { $0.contains("漏音") })
        #expect(report.formulaDescription.contains("70%"))
    }

    @Test func waitingAndMicrophoneReportsNeverInferRhythmMissesOrReleaseGrades() throws {
        var engine = PracticeEngine(score: piece, inputLagTolerance: 3, evaluatesNoteDuration: false)
        engine.start(at: 10)
        engine.receive(.on(pitch: 61, velocity: 80), at: 10.1)
        engine.receive(.off(pitch: 61), at: 10.2)
        for (index, pitch) in [60, 62, 64, 65].enumerated() {
            let time = 20 + Double(index) * 20 // deliberately no relation to the written tempo
            engine.receive(.on(pitch: pitch, velocity: 80), at: time)
            engine.receive(.off(pitch: pitch), at: time + 0.01)
        }
        let report = engine.report(inputSource: "microphonePolyphonic")
        #expect(report.isComplete && report.correct == 4 && report.wrong == 1)
        #expect(report.pitchAccuracy == 80)
        #expect(report.early == nil && report.late == nil && report.missed == nil)
        #expect(report.rhythmScore == nil && report.overallScore == nil && report.timedNoteCount == 0)
        #expect(report.meanAbsoluteOnsetErrorMilliseconds == nil && report.meanSignedOnsetErrorMilliseconds == nil)
        #expect(report.measureResults.allSatisfy { $0.missed == nil && $0.early == nil && $0.late == nil })
        #expect(engine.durationFeedback == nil)
    }

    @Test func unfinishedAndResumedSegmentsHaveNoFinalScore() {
        var engine = PracticeEngine(score: piece, mode: .rhythm)
        #expect(engine.report().pitchAccuracy == nil)
        engine.start(at: 0)
        engine.receive(.on(pitch: 60, velocity: 80), at: 0)
        let ongoing = engine.report()
        #expect(!ongoing.isComplete && ongoing.evaluatedNotes == 1 && ongoing.totalNotes == 4)
        #expect(ongoing.overallScore == nil && ongoing.rhythmScore == nil)
        let segment = completedRhythm().report(isPartial: true)
        #expect(!segment.isComplete && segment.overallScore == nil && segment.rhythmScore == nil)
        #expect(segment.correct == 3 && segment.meanAbsoluteOnsetErrorMilliseconds != nil)
    }

    @Test func allMissedRhythmHasZeroScoreButNoInventedTimingMeasurement() {
        var engine = PracticeEngine(score: piece, mode: .rhythm)
        engine.start(at: 10); engine.tick(at: 14)
        let report = engine.report()
        #expect(report.isComplete && report.missed == 4)
        #expect(report.pitchAccuracy == 0 && report.rhythmScore == 0 && report.overallScore == 0)
        #expect(report.timedNoteCount == 0 && report.meanAbsoluteOnsetErrorMilliseconds == nil)
    }

    @Test func pauseResumeRetainsMeasuredResultsAndUsesOnlyRunningTime() throws {
        var engine = PracticeEngine(score: piece, mode: .rhythm)
        engine.start(at: 10); engine.receive(.on(pitch: 60, velocity: 80), at: 10)
        engine.pause(at: 10.4)
        engine.receive(.allNotesOff, at: 10.4)
        engine.start(at: 100)
        engine.receive(.on(pitch: 62, velocity: 80), at: 100.65) // 50 ms late, not 90 seconds
        let report = engine.report()
        #expect(report.correct == 2 && report.timedNoteCount == 2)
        #expect(abs(try #require(report.meanAbsoluteOnsetErrorMilliseconds) - 25) < 0.000001)
        engine.reset()
        let reset = engine.report()
        #expect(reset.correct == 0 && reset.wrong == 0 && reset.timedNoteCount == 0)
        #expect(reset.pitchAccuracy == nil && reset.meanAbsoluteOnsetErrorMilliseconds == nil)
    }

    @Test func selectedRangeAndHandAreExplicitInTheReport() {
        var score = piece
        score.notes[2].staff = 2; score.notes[3].staff = 2
        var engine = PracticeEngine(score: score, mode: .rhythm, hand: .left, measureRange: 2...2)
        engine.start(at: 10)
        engine.receive(.on(pitch: 64, velocity: 80), at: 10)
        engine.receive(.off(pitch: 64), at: 10.5)
        engine.receive(.on(pitch: 65, velocity: 80), at: 11)
        engine.tick(at: 12)
        let report = engine.report()
        #expect(report.isComplete && report.totalNotes == 2 && report.overallScore == 100)
        #expect(report.startMeasure == 2 && report.endMeasure == 2 && report.hand == .left)
        #expect(report.measureResults.map(\.measure) == [2])
    }

    @Test func legacySummaryDecodesWithoutReportAndNewReportRoundTrips() throws {
        let legacy = Data("""
            {"id":"old","date":0,"scoreTitle":"旧记录","correct":2,"wrong":1,"missed":0,"durationSeconds":4,"mode":"wait"}
            """.utf8)
        let old = try JSONDecoder().decode(PracticeSummary.self, from: legacy)
        #expect(old.report == nil && old.correct == 2 && old.accuracy == 2.0 / 3)
        let summary = completedRhythm().summary(at: Date(timeIntervalSince1970: 0), inputSource: "midi")
        let restored = try JSONDecoder().decode(PracticeSummary.self, from: JSONEncoder().encode(summary))
        #expect(restored == summary && restored.report?.overallScore == 57)
    }
}
