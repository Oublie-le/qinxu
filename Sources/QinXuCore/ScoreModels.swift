import Foundation

public enum PracticeHand: String, Codable, CaseIterable, Sendable {
    case both, right, left
    public var title: String {
        switch self { case .both: return "双手"; case .right: return "右手"; case .left: return "左手" }
    }
    public func includes(staff: Int) -> Bool {
        self == .both || (self == .right && staff == 1) || (self == .left && staff == 2)
    }
}

public struct ScoreNote: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var midi: Int
    public var startBeat: Double
    public var durationBeats: Double
    public var staff: Int
    public var measure: Int
    public var step: String
    public var alter: Int
    public var octave: Int
    public init(id: String = UUID().uuidString, midi: Int, startBeat: Double, durationBeats: Double, staff: Int = 1, measure: Int = 1, step: String = "", alter: Int = 0, octave: Int = 4) {
        self.id = id; self.midi = midi; self.startBeat = startBeat; self.durationBeats = durationBeats
        self.staff = staff; self.measure = measure; self.step = step; self.alter = alter; self.octave = octave
    }
    public var name: String { NoteNames.name(midi) }
}

/// A clef locates written pitches; it never changes staff/hand assignment or MIDI pitch.
public enum ScoreClef: String, Codable, Equatable, Sendable {
    case treble, bass
    public var bottomLineDiatonic: Int { self == .treble ? 30 : 18 } // E4 / G2
    public var title: String { self == .treble ? "高音谱号" : "低音谱号" }
    public func staffSteps(for note: ScoreNote) -> Int { note.diatonicPitch - bottomLineDiatonic }
}

extension ScoreNote {
    /// C0 = 0; one step is one staff line/space, independent of accidentals.
    public var diatonicPitch: Int {
        if let offset = ["C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6][step.uppercased()] {
            return octave * 7 + offset
        }
        return (midi / 12 - 1) * 7 + [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6][((midi % 12) + 12) % 12]
    }
}

public struct ScoreMeasure: Identifiable, Codable, Equatable, Sendable {
    public var number: Int
    public var startBeat: Double
    public var durationBeats: Double
    public var upperClef: ScoreClef
    public var lowerClef: ScoreClef
    public var id: Int { number }
    public init(number: Int, startBeat: Double, durationBeats: Double,
                upperClef: ScoreClef = .treble, lowerClef: ScoreClef = .bass) {
        self.number = number; self.startBeat = startBeat; self.durationBeats = durationBeats
        self.upperClef = upperClef; self.lowerClef = lowerClef
    }
    public func clef(for staff: Int) -> ScoreClef { staff == 2 ? lowerClef : upperClef }

    private enum CodingKeys: String, CodingKey { case number, startBeat, durationBeats, upperClef, lowerClef }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        number = try values.decode(Int.self, forKey: .number)
        startBeat = try values.decode(Double.self, forKey: .startBeat)
        durationBeats = try values.decode(Double.self, forKey: .durationBeats)
        // Existing user libraries used the fixed treble/bass rendering. Keep them readable.
        upperClef = try values.decodeIfPresent(ScoreClef.self, forKey: .upperClef) ?? .treble
        lowerClef = try values.decodeIfPresent(ScoreClef.self, forKey: .lowerClef) ?? .bass
    }
}

public struct PianoScore: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var composer: String
    public var tempoBPM: Double
    public var beatsPerMeasure: Int
    public var beatUnit: Int
    public var notes: [ScoreNote]
    public var measures: [ScoreMeasure]
    public var warnings: [String]
    public init(id: String = UUID().uuidString, title: String, composer: String = "", tempoBPM: Double = 80, beatsPerMeasure: Int = 4, beatUnit: Int = 4, notes: [ScoreNote], measures: [ScoreMeasure], warnings: [String] = []) {
        self.id = id; self.title = title; self.composer = composer; self.tempoBPM = tempoBPM
        self.beatsPerMeasure = beatsPerMeasure; self.beatUnit = beatUnit
        self.notes = notes; self.measures = measures; self.warnings = warnings
    }
    public var durationBeats: Double {
        max(measures.map { $0.startBeat + $0.durationBeats }.max() ?? 0, notes.map { $0.startBeat + $0.durationBeats }.max() ?? 0)
    }
    public func clef(for staff: Int, inMeasure number: Int) -> ScoreClef {
        if number > 0, number <= measures.count, measures[number - 1].number == number {
            return measures[number - 1].clef(for: staff)
        }
        return measures.first(where: { $0.number == number })?.clef(for: staff) ?? (staff == 2 ? .bass : .treble)
    }
}

public enum NoteNames {
    public static func name(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return names[((midi % 12) + 12) % 12] + String(midi / 12 - 1)
    }
}

public enum NoteInput: Equatable, Sendable {
    case on(pitch: Int, velocity: Int)
    case off(pitch: Int)
    case sustain(Bool)
    case allNotesOff
}

public enum PracticeMode: String, CaseIterable, Codable, Sendable {
    case wait, rhythm
    public var title: String { self == .wait ? "识谱模式" : "节奏模式" }
}

public enum NoteVerdict: String, Codable, Sendable {
    case pending, correct, wrong, missed, early, late
}

public struct PracticeSummary: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var date: Date
    public var scoreTitle: String
    public var correct: Int
    public var wrong: Int
    public var missed: Int
    public var durationSeconds: Double
    public var mode: PracticeMode
    public var report: PracticeReport?
    public init(id: String = UUID().uuidString, date: Date = Date(), scoreTitle: String, correct: Int, wrong: Int, missed: Int, durationSeconds: Double, mode: PracticeMode, report: PracticeReport? = nil) {
        self.id = id; self.date = date; self.scoreTitle = scoreTitle; self.correct = correct
        self.wrong = wrong; self.missed = missed; self.durationSeconds = durationSeconds; self.mode = mode
        self.report = report
    }
    public var accuracy: Double {
        let total = correct + wrong + missed
        return total == 0 ? 0 : Double(correct) / Double(total)
    }
}
