import Foundation

public enum MetronomeNoteValue: String, Codable, CaseIterable, Sendable {
    case half, quarter, eighth, sixteenth, dottedQuarter

    public var title: String {
        switch self {
        case .half: return "二分音符"
        case .quarter: return "四分音符"
        case .eighth: return "八分音符"
        case .sixteenth: return "十六分音符"
        case .dottedQuarter: return "附点四分音符"
        }
    }

    /// Standard Unicode labels for tempo annotations, not engraved score glyphs.
    public var symbol: String {
        switch self {
        case .half: return "𝅗𝅥"
        case .quarter: return "♩"
        case .eighth: return "♪"
        case .sixteenth: return "𝅘𝅥𝅯"
        case .dottedQuarter: return "♩·"
        }
    }

    public var quarterBeats: Double { Double(sixteenthTicks) / 4 }

    fileprivate var sixteenthTicks: Int {
        switch self {
        case .half: return 8
        case .quarter: return 4
        case .eighth: return 2
        case .sixteenth: return 1
        case .dottedQuarter: return 6
        }
    }
}

public struct GlobalMetronomePosition: Equatable, Sendable {
    /// Zero-based absolute click index. Other indices are one-based for presentation.
    public let index: Int
    public let measure: Int
    public let beat: Int
    public let subdivision: Int
    public let isDownbeat: Bool
    public let isBeat: Bool
}

/// Meter, the BPM reference note and click subdivisions are independent settings.
/// This value never reads a score and never silently changes an invalid draft.
public struct GlobalMetronomeSettings: Codable, Equatable, Sendable {
    public var beatsPerMeasure: Int
    public var beatUnit: Int
    public var tempoBPM: Double
    public var tempoNote: MetronomeNoteValue
    public var clickNote: MetronomeNoteValue
    public var soundEnabled: Bool

    public init(beatsPerMeasure: Int = 4, beatUnit: Int = 4, tempoBPM: Double = 80,
                tempoNote: MetronomeNoteValue = .quarter, clickNote: MetronomeNoteValue = .quarter,
                soundEnabled: Bool = true) {
        self.beatsPerMeasure = beatsPerMeasure
        self.beatUnit = beatUnit
        self.tempoBPM = tempoBPM
        self.tempoNote = tempoNote
        self.clickNote = clickNote
        self.soundEnabled = soundEnabled
    }

    public var quarterBPM: Double { tempoBPM * tempoNote.quarterBeats }

    public var validationMessage: String? {
        guard (1...16).contains(beatsPerMeasure) else { return "每小节拍数须为 1–16。" }
        guard [2, 4, 8, 16].contains(beatUnit) else { return "拍号分母须为 2、4、8 或 16。" }
        guard tempoBPM.isFinite, (20...300).contains(tempoBPM) else {
            return "速度须为每分钟 20–300 个所选音符。"
        }
        guard quarterBPM.isFinite, (20...300).contains(quarterBPM) else {
            return "换算后的四分音符速度须为每分钟 20–300 拍，请调整速度或速度单位。"
        }
        guard clickNote != .dottedQuarter else { return "点击分拍暂不支持附点音符。" }
        let beatTicks = 16 / beatUnit
        guard clickNote.sixteenthTicks <= beatTicks else { return "分拍单位不能长于拍号中的一拍。" }
        guard beatTicks.isMultiple(of: clickNote.sixteenthTicks) else { return "每拍须包含整数个分拍。" }
        return nil
    }

    public var isValid: Bool { validationMessage == nil }

    /// Invalid drafts have no usable timing; callers must validate before publishing.
    public var beatSeconds: Double { isValid ? 60 / quarterBPM * 4 / Double(beatUnit) : .nan }
    public var pulseSeconds: Double { isValid ? 60 / quarterBPM * clickNote.quarterBeats : .nan }
    public var measureSeconds: Double { isValid ? beatSeconds * Double(beatsPerMeasure) : .nan }

    public var pulsesPerBeat: Int {
        guard [2, 4, 8, 16].contains(beatUnit), clickNote != .dottedQuarter else { return 0 }
        let beatTicks = 16 / beatUnit
        guard clickNote.sixteenthTicks <= beatTicks,
              beatTicks.isMultiple(of: clickNote.sixteenthTicks) else { return 0 }
        return beatTicks / clickNote.sixteenthTicks
    }

    public var pulsesPerMeasure: Int {
        guard (1...16).contains(beatsPerMeasure) else { return 0 }
        return beatsPerMeasure * pulsesPerBeat
    }

    /// Derive position from an elapsed monotonic duration, never accumulated timer ticks.
    /// Only the first subdivision is a beat; only the first beat is the bar downbeat.
    public func position(atElapsedSeconds elapsed: Double) -> GlobalMetronomePosition? {
        guard isValid, elapsed.isFinite, elapsed >= 0 else { return nil }
        let rawIndex = elapsed / pulseSeconds
        guard rawIndex.isFinite else { return nil }
        let nearest = rawIndex.rounded()
        // Correct floating-point noise at exact boundaries without a musical early window.
        let stableIndex = abs(rawIndex - nearest) <= 4 * max(rawIndex.ulp, nearest.ulp) ? nearest : rawIndex
        guard stableIndex >= 0, stableIndex < Double(Int.max) else { return nil }
        let index = Int(floor(stableIndex))
        let withinMeasure = index % pulsesPerMeasure
        let subdivision = withinMeasure % pulsesPerBeat + 1
        let beat = withinMeasure / pulsesPerBeat + 1
        return GlobalMetronomePosition(index: index, measure: index / pulsesPerMeasure + 1,
                                       beat: beat, subdivision: subdivision,
                                       isDownbeat: withinMeasure == 0, isBeat: subdivision == 1)
    }
}
