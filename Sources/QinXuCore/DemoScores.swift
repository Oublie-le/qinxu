import Foundation

/// Original, short public-domain practice material bundled with the application.
/// Matching editable MusicXML files are available in Resources/Scores.
public enum DemoScores {
    public static let all: [PianoScore] = [melody, chords, rhythm]

    private struct Event {
        let pitches: [Int]
        let duration: Double
        init(_ pitches: [Int], _ duration: Double = 1) { self.pitches = pitches; self.duration = duration }
    }
    private struct Voice {
        let staff: Int
        let events: [Event]
        init(_ staff: Int, _ events: [Event]) { self.staff = staff; self.events = events }
    }

    private static let melody = make(id: "demo-melody", title: "晨光 · 右手识谱", tempo: 72, bars: [
        [Voice(1, [Event([60]), Event([62]), Event([64]), Event([67])])],
        [Voice(1, [Event([69]), Event([67]), Event([64]), Event([62])])],
        [Voice(1, [Event([60], 2), Event([64]), Event([67])])],
        [Voice(1, [Event([65]), Event([64]), Event([62], 2)])],
        [Voice(1, [Event([64]), Event([65]), Event([67], 2)])],
        [Voice(1, [Event([69]), Event([67]), Event([65]), Event([64])])],
        [Voice(1, [Event([62], 2), Event([67], 2)])],
        [Voice(1, [Event([60], 4)])]
    ])

    private static let chords = make(id: "demo-chords", title: "并肩 · 双手和弦", tempo: 60, bars: [
        [Voice(1, [Event([60]), Event([64]), Event([67]), Event([64])]), Voice(2, [Event([48, 52, 55], 4)])],
        [Voice(1, [Event([65]), Event([69]), Event([72]), Event([69])]), Voice(2, [Event([41, 45, 48], 4)])],
        [Voice(1, [Event([67]), Event([71]), Event([74]), Event([71])]), Voice(2, [Event([43, 47, 50], 4)])],
        [Voice(1, [Event([72], 4)]), Voice(2, [Event([48, 52, 55], 4)])]
    ])

    private static let rhythm = make(id: "demo-rhythm", title: "轻步 · 节奏练习", tempo: 66, bars: [
        [Voice(1, [Event([60], 0.5), Event([62], 0.5), Event([64]), Event([], 1), Event([67])])],
        [Voice(1, [Event([65], 1.5), Event([64], 0.5), Event([62]), Event([], 1)])],
        [Voice(1, [Event([60], 1.0 / 3), Event([62], 1.0 / 3), Event([64], 1.0 / 3), Event([67]), Event([69], 2)])],
        [Voice(1, [Event([67]), Event([], 1), Event([60], 2)])]
    ])

    private static func make(id: String, title: String, tempo: Double, bars: [[Voice]]) -> PianoScore {
        var notes: [ScoreNote] = []
        var measures: [ScoreMeasure] = []
        let steps = [0: "C", 2: "D", 4: "E", 5: "F", 7: "G", 9: "A", 11: "B"]
        for (barIndex, voices) in bars.enumerated() {
            let start = Double(barIndex * 4)
            measures.append(ScoreMeasure(number: barIndex + 1, startBeat: start, durationBeats: 4))
            for voice in voices {
                var beat = start
                for event in voice.events {
                    for pitch in event.pitches {
                        notes.append(ScoreNote(id: "\(id)-n\(notes.count + 1)", midi: pitch, startBeat: beat, durationBeats: event.duration, staff: voice.staff, measure: barIndex + 1, step: steps[pitch % 12] ?? "C", alter: 0, octave: pitch / 12 - 1))
                    }
                    beat += event.duration
                }
            }
        }
        notes.sort {
            if abs($0.startBeat - $1.startBeat) > 0.000_001 { return $0.startBeat < $1.startBeat }
            if $0.staff != $1.staff { return $0.staff < $1.staff }
            return $0.midi < $1.midi
        }
        return PianoScore(id: id, title: title, composer: "原创练习 · 可自由使用", tempoBPM: tempo, notes: notes, measures: measures, warnings: ["练习谱面简化了排版、调号、连线、力度及文字指示；实际音高及节拍以曲谱数据为准。"])
    }
}
