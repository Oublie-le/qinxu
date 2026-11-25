import Foundation

/// Written-duration guidance, not a measurement of the sounding note or pedal.
public struct SustainGuidance: Identifiable, Codable, Equatable, Sendable {
    public var id: Int { pitch }
    public let pitch: Int
    public let noteIDs: [String]
    public let remainingSeconds: Double
    public let totalSeconds: Double
    public let remainingBeats: Double
    public let totalBeats: Double
    public var remainingFraction: Double {
        totalSeconds > 0 ? min(1, max(0, remainingSeconds / totalSeconds)) : 0
    }
}

public struct PracticeMeasureResult: Identifiable, Codable, Equatable, Sendable {
    public var id: Int { measure }
    public let measure: Int
    public let totalNotes: Int
    public let correct: Int
    /// Incorrect attacks, rather than a count of distinct score notes.
    public let wrong: Int
    public let early: Int?
    public let late: Int?
    public let missed: Int?
    public let timedNoteCount: Int
    public let meanAbsoluteOnsetErrorMilliseconds: Double?
    public let meanSignedOnsetErrorMilliseconds: Double?
    public var hasIssues: Bool { wrong > 0 || (early ?? 0) > 0 || (late ?? 0) > 0 || (missed ?? 0) > 0 }
}

/// Versioned, reproducible feedback from evaluated events. Percentages are 0...100.
/// Waiting mode has no timing or missed-note grade. A partial session has no final score.
/// Key-release duration is deliberately not part of this scoring formula.
public struct PracticeReport: Codable, Equatable, Sendable {
    public let version: Int
    public let scoreID: String
    public let mode: PracticeMode
    public let hand: PracticeHand
    public let tempoBPM: Double
    /// App-provided provenance; this does not enable an evaluation dimension.
    public let inputSource: String?
    public let startMeasure: Int
    public let endMeasure: Int
    public let isComplete: Bool
    public let totalNotes: Int
    public let evaluatedNotes: Int
    public let correct: Int
    public let wrong: Int
    public let early: Int?
    public let late: Int?
    public let missed: Int?
    public let timedNoteCount: Int
    public let pitchAccuracy: Double?
    public let meanAbsoluteOnsetErrorMilliseconds: Double?
    public let meanSignedOnsetErrorMilliseconds: Double?
    public let rhythmScore: Int?
    public let overallScore: Int?
    public let measureResults: [PracticeMeasureResult]
    public let suggestions: [String]
    public let formulaDescription: String

    init(scoreID: String, mode: PracticeMode, hand: PracticeHand, tempoBPM: Double,
         inputSource: String?, notes: [ScoreNote], measureNumbers: Set<Int>,
         verdicts: [String: NoteVerdict], onsetErrors: [String: Double], wrongByMeasure: [Int: Int],
         finished: Bool, isPartial: Bool) {
        version = 1
        self.scoreID = scoreID; self.mode = mode; self.hand = hand
        self.tempoBPM = tempoBPM; self.inputSource = inputSource
        startMeasure = measureNumbers.min() ?? notes.first?.measure ?? 1
        endMeasure = measureNumbers.max() ?? notes.last?.measure ?? startMeasure
        totalNotes = notes.count
        let rhythmic = mode == .rhythm
        func accepted(_ note: ScoreNote) -> Bool {
            [.correct, .early, .late].contains(verdicts[note.id] ?? .pending)
        }
        correct = notes.filter(accepted).count
        wrong = wrongByMeasure.values.reduce(0, +)
        early = rhythmic ? notes.filter { verdicts[$0.id] == .early }.count : nil
        late = rhythmic ? notes.filter { verdicts[$0.id] == .late }.count : nil
        missed = rhythmic ? notes.filter { verdicts[$0.id] == .missed }.count : nil
        evaluatedNotes = correct + (missed ?? 0)
        isComplete = finished && !isPartial && totalNotes > 0 && evaluatedNotes == totalNotes
        let attempts = evaluatedNotes + wrong
        pitchAccuracy = attempts > 0 ? 100 * Double(correct) / Double(attempts) : nil
        let errors = rhythmic ? notes.filter(accepted).compactMap { onsetErrors[$0.id] } : []
        timedNoteCount = errors.count
        meanAbsoluteOnsetErrorMilliseconds = Self.mean(errors.map(abs))
        meanSignedOnsetErrorMilliseconds = Self.mean(errors)
        // Match the engine's ±100 ms on-time band and ±300 ms acceptance window.
        // A missed note contributes zero. Use the unrounded components for total.
        let timing = totalNotes > 0
            ? 100 * errors.reduce(0) { $0 + Self.onsetCredit(milliseconds: $1) } / Double(totalNotes) : 0
        let canGrade = rhythmic && isComplete && timedNoteCount == correct
        rhythmScore = canGrade ? Int(timing.rounded()) : nil
        overallScore = canGrade ? Int((0.7 * (pitchAccuracy ?? 0) + 0.3 * timing).rounded()) : nil
        measureResults = measureNumbers.union(notes.map(\.measure)).sorted().map { number in
            let group = notes.filter { $0.measure == number }
            let groupErrors = rhythmic ? group.filter(accepted).compactMap { onsetErrors[$0.id] } : []
            return PracticeMeasureResult(measure: number, totalNotes: group.count,
                correct: group.filter(accepted).count, wrong: wrongByMeasure[number] ?? 0,
                early: rhythmic ? group.filter { verdicts[$0.id] == .early }.count : nil,
                late: rhythmic ? group.filter { verdicts[$0.id] == .late }.count : nil,
                missed: rhythmic ? group.filter { verdicts[$0.id] == .missed }.count : nil,
                timedNoteCount: groupErrors.count,
                meanAbsoluteOnsetErrorMilliseconds: Self.mean(groupErrors.map(abs)),
                meanSignedOnsetErrorMilliseconds: Self.mean(groupErrors))
        }
        formulaDescription = rhythmic
            ? "音高准确率 = 正确音符 ÷（正确音符 + 漏音 + 错音次数）× 100%。起音偏差在 ±100 ms 内记满分，100–300 ms 线性减至 0，漏音记 0；节奏分为全部谱面音符的平均得分。总分 = 70% 音高准确率 + 30% 节奏分。未完成只显示过程数据，不计算总分或节奏分；松键时长不计分。"
            : "识谱准确率 = 正确音符 ÷（正确音符 + 错音次数）× 100%。等待模式不评漏音、起音节奏或松键时长，不生成总分；未完成时仅统计本次已判定的音符。"
        suggestions = Self.advice(complete: isComplete, mode: mode, measures: measureResults,
                                  correct: correct, wrong: wrong, early: early ?? 0,
                                  late: late ?? 0, missed: missed ?? 0)
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func onsetCredit(milliseconds: Double) -> Double {
        min(1, max(0, (300 - abs(milliseconds)) / 200))
    }

    private static func advice(complete: Bool, mode: PracticeMode, measures: [PracticeMeasureResult],
                               correct: Int, wrong: Int, early: Int, late: Int, missed: Int) -> [String] {
        var result: [String] = []
        if !complete { result.append("本次为部分练习；不生成完整总分，结果仅覆盖所练范围。") }
        let trouble = measures.filter(\.hasIssues).sorted {
            let a = $0.wrong + ($0.missed ?? 0) + ($0.early ?? 0) + ($0.late ?? 0)
            let b = $1.wrong + ($1.missed ?? 0) + ($1.early ?? 0) + ($1.late ?? 0)
            return a == b ? $0.measure < $1.measure : a > b
        }
        if let first = trouble.first {
            result.append("优先复习第 \(first.measure) 小节；可以分手练习，再合手核对。")
        }
        if wrong > 0 { result.append("记录到 \(wrong) 次错音；先确认音名和手位，弹稳后再提高速度。") }
        if missed > 0 { result.append("有 \(missed) 个漏音；降低速度并跟随节拍，保留休止符的空拍。") }
        if mode == .rhythm, early > 0 || late > 0 {
            if early > late { result.append("抢拍较多；先听清拍点，再开始下一音。") }
            else if late > early { result.append("拖拍较多；放慢速度，提前准备下一音的手位。") }
            else { result.append("起音有早有晚；用较慢速度跟随节拍，练习均匀落键。") }
        }
        if complete && wrong == 0 && missed == 0 && early == 0 && late == 0 && correct > 0 {
            result.append(mode == .wait ? "本段未记录错音；可以重复巩固，或用 MIDI／触屏尝试节奏模式。"
                : "本段未记录错音、漏音或超出 ±100 ms 的起音；可保持当前速度再练一遍。")
        }
        return result
    }
}
