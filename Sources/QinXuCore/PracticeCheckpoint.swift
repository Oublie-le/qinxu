import Foundation
import CryptoKit

/// A resumable position is a measure boundary, never a partially evaluated chord.
public struct PracticeCheckpoint: Codable, Equatable, Sendable {
    public var scoreID: String
    public var scoreFingerprint: String
    public var measure: Int
    public var hand: PracticeHand
    public var mode: PracticeMode
    public var tempoBPM: Double
    public var updatedAt: Date
    public var isCompleted: Bool

    public init(scoreID: String, scoreFingerprint: String, measure: Int, hand: PracticeHand,
                mode: PracticeMode, tempoBPM: Double, updatedAt: Date = Date(), isCompleted: Bool = false) {
        self.scoreID = scoreID
        self.scoreFingerprint = scoreFingerprint
        self.measure = measure
        self.hand = hand
        self.mode = mode
        self.tempoBPM = tempoBPM
        self.updatedAt = updatedAt
        self.isCompleted = isCompleted
    }

    /// Returns nil instead of silently clamping an invalid position or configuration.
    /// A valid position crossed by a sustained/tied note moves back to its onset measure.
    public static func make(score: PianoScore, measure: Int, hand: PracticeHand,
                            mode: PracticeMode, tempoBPM: Double, updatedAt: Date = Date(),
                            isCompleted: Bool = false) -> PracticeCheckpoint? {
        guard let fingerprint = fingerprint(for: score), (1...score.measures.count).contains(measure),
              let safeMeasure = isCompleted ? measure : PracticeTiming.safeStartMeasure(score: score, hand: hand, requestedMeasure: measure) else { return nil }
        let checkpoint = PracticeCheckpoint(scoreID: score.id, scoreFingerprint: fingerprint,
                                            measure: safeMeasure, hand: hand, mode: mode, tempoBPM: tempoBPM,
                                            updatedAt: updatedAt, isCompleted: isCompleted)
        return checkpoint.isValid ? checkpoint : nil
    }

    public func matches(_ score: PianoScore) -> Bool {
        isValid && scoreID == score.id && score.measures.contains(where: { $0.number == measure }) &&
            scoreFingerprint == Self.fingerprint(for: score)
    }

    public func resumeMeasure(in score: PianoScore) -> Int? {
        guard !isCompleted, matches(score) else { return nil }
        return PracticeTiming.safeStartMeasure(score: score, hand: hand, requestedMeasure: measure)
    }

    /// Stable across launches and regenerated note IDs. Titles, author and warnings
    /// are presentation metadata; every evaluated pitch/timing/staff value is included.
    public static func fingerprint(for score: PianoScore) -> String? {
        guard hasValidTimeline(score) else { return nil }
        struct Content: Encodable {
            let format = "QinXuPracticeScoreV1"
            let tempo: Double
            let beatsPerMeasure: Int
            let beatUnit: Int
            let measures: [[Double]]
            let notes: [[Double]]
        }
        let content = Content(tempo: score.tempoBPM, beatsPerMeasure: score.beatsPerMeasure, beatUnit: score.beatUnit,
            measures: score.measures.map { [Double($0.number), $0.startBeat, $0.durationBeats] },
            notes: score.notes.map { [Double($0.midi), $0.startBeat, $0.durationBeats, Double($0.staff), Double($0.measure)] }
                .sorted { $0.lexicographicallyPrecedes($1) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(content) else { return nil }
        return "v1:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    var isValid: Bool {
        let suffix = scoreFingerprint.dropFirst(3)
        return !scoreID.isEmpty && scoreID.utf8.count <= 256 &&
            scoreFingerprint.hasPrefix("v1:") && suffix.count == 64 &&
            suffix.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } &&
            (1...1_000).contains(measure) && tempoBPM.isFinite && (20...300).contains(tempoBPM) &&
            updatedAt.timeIntervalSince1970.isFinite && (0...253_402_300_799).contains(updatedAt.timeIntervalSince1970)
    }

    fileprivate static func hasValidTimeline(_ score: PianoScore) -> Bool {
        guard !score.id.isEmpty, score.id.utf8.count <= 256,
              (1...1_000).contains(score.measures.count), score.notes.count <= 20_000,
              score.tempoBPM.isFinite, (20...300).contains(score.tempoBPM),
              (1...32).contains(score.beatsPerMeasure), [1, 2, 4, 8, 16, 32].contains(score.beatUnit) else { return false }
        var end = 0.0
        for (index, measure) in score.measures.enumerated() {
            guard measure.number == index + 1,
                  measure.startBeat.isFinite, measure.durationBeats.isFinite,
                  abs(measure.startBeat - end) < 0.000001,
                  measure.durationBeats > 0, measure.durationBeats <= 128 else { return false }
            end = measure.startBeat + measure.durationBeats
        }
        for note in score.notes {
            guard (0...127).contains(note.midi), (1...2).contains(note.staff),
                  (1...score.measures.count).contains(note.measure),
                  note.startBeat.isFinite, note.durationBeats.isFinite, note.durationBeats > 0,
                  note.startBeat + note.durationBeats <= end + 0.000001 else { return false }
            let measure = score.measures[note.measure - 1]
            guard note.startBeat >= measure.startBeat - 0.000001,
                  note.startBeat < measure.startBeat + measure.durationBeats - 0.000001 else { return false }
        }
        return true
    }
}

extension PracticeTiming {
    /// Walks backwards until no selected-hand note crosses the proposed boundary.
    /// Repeating the check also handles overlapping ties whose onsets span multiple bars.
    public static func safeStartMeasure(score: PianoScore, hand: PracticeHand, requestedMeasure: Int) -> Int? {
        guard PracticeCheckpoint.hasValidTimeline(score),
              (1...score.measures.count).contains(requestedMeasure) else { return nil }
        let notes = score.notes.filter { hand.includes(staff: $0.staff) }
        var candidate = requestedMeasure
        while candidate > 1 {
            let start = score.measures[candidate - 1].startBeat
            let crossing = notes.filter {
                $0.startBeat < start - 0.000001 && $0.startBeat + $0.durationBeats > start + 0.000001
            }
            guard let earlier = crossing.map(\.measure).min() else { break }
            guard earlier < candidate else { return nil }
            candidate = earlier
        }
        // A hand with no remaining onsets has no resumable exercise.
        guard notes.contains(where: { $0.measure >= candidate }) else { return nil }
        return candidate
    }
}
