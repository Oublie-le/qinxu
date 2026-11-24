import Foundation

public struct MetronomePosition: Equatable {
    public let measure: Int
    public let pulse: Int
    public var id: String { "\(measure):\(pulse)" }
    public var accented: Bool { pulse == 0 }
}

public enum PracticeTiming {
    public static func metronomePosition(atQuarterBeat beat: Double, score: PianoScore) -> MetronomePosition? {
        guard beat.isFinite, score.beatUnit > 0,
              let measure = score.measures.last(where: { $0.startBeat <= beat + 0.000001 }) else { return nil }
        let pulseLength = 4.0 / Double(score.beatUnit)
        return MetronomePosition(measure: measure.number, pulse: max(0, Int(floor((beat - measure.startBeat) / pulseLength + 0.000001))))
    }

    public static func loopStartIssue(score: PianoScore, hand: PracticeHand, startMeasure: Int) -> String? {
        guard let measure = score.measures.first(where: { $0.number == startMeasure }) else { return nil }
        let crossing = score.notes.filter {
            hand.includes(staff: $0.staff) && $0.startBeat < measure.startBeat - 0.000001 &&
            $0.startBeat + $0.durationBeats > measure.startBeat + 0.000001
        }
        guard let first = crossing.min(by: { $0.measure < $1.measure }) else { return nil }
        return "第 \(startMeasure) 小节包含前面延续的音。当前版本请从第 \(first.measure) 小节或更早开始循环，以保留完整时值。"
    }
}
