import Foundation
import Testing
@testable import PianoCore

@Suite struct PracticePipelineTests {
    @Test func originalMusicXMLThroughMIDIToRhythmScoring() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Scores")
        for demo in DemoScores.all {
            let score = try MusicXMLParser().parse(data: Data(contentsOf: fixtures.appendingPathComponent(demo.id + ".musicxml")))
            var engine = PracticeEngine(score: score, mode: .rhythm)
            var decoder = MIDIStreamDecoder()
            var events: [(beat: Double, on: Bool, pitch: Int)] = []
            for note in score.notes {
                events.append((note.startBeat, true, note.midi))
                events.append((note.startBeat + note.durationBeats, false, note.midi))
            }
            events.sort {
                if abs($0.beat - $1.beat) > 0.00001 { return $0.beat < $1.beat }
                return !$0.on && $1.on
            }
            engine.start(at: 100)
            for event in events {
                let bytes: [UInt8] = [event.on ? 0x90 : 0x80, UInt8(event.pitch), event.on ? 90 : 0]
                for input in decoder.feed(bytes) {
                    engine.receive(input, at: 100 + event.beat * 60 / score.tempoBPM)
                }
            }
            engine.tick(at: 100 + score.durationBeats * 60 / score.tempoBPM + 0.5)
            #expect(engine.isFinished)
            #expect(engine.correctCount == score.notes.count)
            #expect(engine.missedCount == 0)
            #expect(engine.wrongCount == 0)
        }
    }

    @Test func correctWaitSequenceRecoversAfterExtraWrongKey() {
        let score = DemoScores.all[0]
        var engine = PracticeEngine(score: score)
        engine.start(at: 0)
        engine.receive(.on(pitch: 61, velocity: 80), at: 0)
        engine.receive(.off(pitch: 61), at: 0.1)
        var time = 0.2
        for note in score.notes {
            engine.receive(.on(pitch: note.midi, velocity: 80), at: time)
            time += note.durationBeats * 60 / score.tempoBPM
            engine.receive(.off(pitch: note.midi), at: time)
        }
        #expect(engine.isFinished)
        #expect(engine.correctCount == score.notes.count)
        #expect(engine.wrongCount == 1)
        #expect(engine.missedCount == 0)
    }
}
