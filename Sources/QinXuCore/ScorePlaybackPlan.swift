import Foundation

/// A sounding note in quarter-note beats. The score's parser has already
/// merged tied notes into one continuous interval.
public struct ScorePlaybackNote: Equatable, Sendable {
    public let midi: UInt8
    public let staff: Int
    public let startBeat: Double
    public let endBeat: Double

    public var durationBeats: Double { endBeat - startBeat }
}

public struct ScorePlaybackPlan: Equatable, Sendable {
    public let notes: [ScorePlaybackNote]
    public let tempoBPM: Double
    public let durationBeats: Double

    public var secondsPerBeat: Double { 60 / tempoBPM }
    public var durationSeconds: Double { durationBeats * secondsPerBeat }

    public init(score: PianoScore) throws {
        guard !score.notes.isEmpty else { throw ScorePlaybackError.emptyScore }
        guard (20...300).contains(score.tempoBPM) else { throw ScorePlaybackError.invalidTempo }
        // Use the imported score's bounds for legacy or programmatically constructed scores.
        guard score.notes.count <= 20_000, score.measures.count <= 1_000 else {
            throw ScorePlaybackError.invalidTimeline
        }
        let maximumBeat = 64_000.000_001
        guard score.measures.allSatisfy({
            $0.startBeat >= 0 && $0.durationBeats > 0 && $0.startBeat + $0.durationBeats <= maximumBeat
        }) else { throw ScorePlaybackError.invalidTimeline }
        notes = try score.notes.map { note in
            let end = note.startBeat + note.durationBeats
            guard (0...127).contains(note.midi), (1...2).contains(note.staff),
                  note.startBeat >= 0, end > note.startBeat, end <= maximumBeat else {
                throw ScorePlaybackError.invalidTimeline
            }
            return ScorePlaybackNote(midi: UInt8(note.midi), staff: note.staff, startBeat: note.startBeat, endBeat: end)
        }.sorted {
            ($0.startBeat, $0.staff, $0.midi, $0.endBeat) < ($1.startBeat, $1.staff, $1.midi, $1.endBeat)
        }
        tempoBPM = score.tempoBPM
        durationBeats = score.durationBeats
    }
}

public enum ScorePlaybackError: LocalizedError, Equatable {
    case emptyScore, invalidTempo, invalidTimeline

    public var errorDescription: String? {
        switch self {
        case .emptyScore: return "这份曲谱没有可试听的音符。"
        case .invalidTempo: return "曲谱的速度无效，无法试听。"
        case .invalidTimeline: return "曲谱的音高或时值无效，无法试听。"
        }
    }
}
