import Foundation

/// A deterministic practice state machine. All times supplied by the caller must
/// come from the same monotonic clock; no wall clock or audio thread is required.
public struct PracticeEngine {
    public let score: PianoScore
    public let mode: PracticeMode
    public let hand: PracticeHand
    public let tempoBPM: Double
    public private(set) var currentBeat: Double
    public private(set) var verdicts: [String: NoteVerdict] = [:]
    public private(set) var heldPitches: Set<Int> = []
    public private(set) var isFinished = false
    public private(set) var isRunning = false
    public private(set) var correctCount = 0
    public private(set) var wrongCount = 0
    public private(set) var missedCount = 0
    public private(set) var feedback = "准备好后开始练习"
    public private(set) var durationFeedback: String?

    private let groups: [[ScoreNote]]
    private let rangeStart: Double
    private let rangeEnd: Double
    private var groupIndex = 0
    private var elapsedSeconds: Double = 0
    private var lastTime: TimeInterval?
    private var runStartTime: TimeInterval?
    private var runStartElapsed: Double = 0
    private var pedalDown = false
    private var candidates: [Int: Candidate] = [:]
    private var durationChecks: [Int: DurationCheck] = [:]
    // A visual reminder of the written duration, independent from key release,
    // acoustic decay and which onset the waiting evaluator expects next.
    private var holdGuideEnds: [Int: Double] = [:]
    private let onsetWindow: Double = 0.30
    private let maximumInputLag: Double
    private let evaluatesNoteDuration: Bool
    private let chordReleaseWindow: Double = 0.35

    private struct Candidate {
        var onset: Double
        var release: Double?
        var usedPedal: Bool
    }
    private struct DurationCheck {
        var onset: Double
        var expected: Double
        var usedPedal: Bool
    }

    public init(score: PianoScore, mode: PracticeMode = .wait, hand: PracticeHand = .both,
                tempoBPM: Double? = nil, measureRange: ClosedRange<Int>? = nil,
                inputLagTolerance: TimeInterval = 0.25, evaluatesNoteDuration: Bool = true) {
        self.score = score
        self.mode = mode
        self.hand = hand
        // Buffered acoustic input can opt in only for waiting, with a hard bound.
        self.maximumInputLag = mode == .wait && inputLagTolerance.isFinite
            ? min(3, max(0, inputLagTolerance)) : 0.25
        self.evaluatesNoteDuration = evaluatesNoteDuration
        let proposedTempo = tempoBPM ?? score.tempoBPM
        self.tempoBPM = proposedTempo.isFinite && proposedTempo > 0 ? proposedTempo : 80
        let selected = score.notes.filter {
            hand.includes(staff: $0.staff) && (measureRange?.contains($0.measure) ?? true)
        }.sorted {
            if abs($0.startBeat - $1.startBeat) > 0.000001 { return $0.startBeat < $1.startBeat }
            if $0.midi != $1.midi { return $0.midi < $1.midi }
            return $0.id < $1.id
        }
        let measures = score.measures.filter { measureRange?.contains($0.number) ?? true }
        self.rangeStart = measures.map(\.startBeat).min() ?? selected.first?.startBeat ?? 0
        self.rangeEnd = max(rangeStart, measures.map { $0.startBeat + $0.durationBeats }.max()
            ?? selected.map { $0.startBeat + $0.durationBeats }.max() ?? rangeStart)
        self.currentBeat = rangeStart
        var grouped: [[ScoreNote]] = []
        for note in selected {
            if let previous = grouped.last?.first, abs(previous.startBeat - note.startBeat) < 0.000001 {
                grouped[grouped.count - 1].append(note)
            } else {
                grouped.append([note])
            }
        }
        self.groups = grouped
        self.verdicts = Dictionary(selected.map { ($0.id, NoteVerdict.pending) }, uniquingKeysWith: { first, _ in first })
        self.isFinished = grouped.isEmpty
        if grouped.isEmpty { self.feedback = "所选范围和声部没有可练习的音符" }
    }

    public var expectedNotes: [ScoreNote] {
        guard !isFinished else { return [] }
        if mode == .wait { return groups.indices.contains(groupIndex) ? groups[groupIndex] : [] }
        return groups.first { $0.contains { !isResolved($0) } } ?? []
    }

    /// Uses the same capture clock as evaluation. A buffered microphone result
    /// must not restart a whole note's written duration when it is delivered.
    public func sustainedPitches(at time: TimeInterval) -> Set<Int> {
        guard time.isFinite, let start = runStartTime, time >= start else { return [] }
        let elapsed = runStartElapsed + time - start
        return Set(holdGuideEnds.filter { $0.value > elapsed + 0.000001 }.map(\.key))
    }

    public var sustainGuidanceEndTime: TimeInterval? {
        guard let start = runStartTime, let end = holdGuideEnds.values.max() else { return nil }
        return start + end - runStartElapsed
    }

    public mutating func start(at time: TimeInterval) {
        guard time.isFinite, !isFinished, !isRunning else { return }
        lastTime = time
        runStartTime = time
        runStartElapsed = elapsedSeconds
        isRunning = true
        if mode == .wait, let onset = expectedNotes.first?.startBeat { currentBeat = onset }
        feedback = mode == .wait ? "弹奏高亮音符，弹对后继续" : "跟随节拍弹奏；漏音后会继续前进"
    }

    public mutating func pause(at time: TimeInterval) {
        tick(at: time)
        isRunning = false
        lastTime = nil
        candidates.removeAll()
        // A hold interrupted by a pause has no meaningful duration verdict.
        durationChecks.removeAll()
        holdGuideEnds.removeAll()
        runStartTime = nil
        if !isFinished { feedback = "已暂停，继续后从当前位置练习" }
    }

    public mutating func tick(at time: TimeInterval) {
        guard isRunning, time.isFinite, let previous = lastTime, time >= previous else { return }
        elapsedSeconds += time - previous
        lastTime = time
        if mode == .wait { return }
        let beat = rangeStart + elapsedSeconds * tempoBPM / 60
        currentBeat = min(beat, rangeEnd)
        for group in groups {
            for note in group where !isResolved(note) {
                if beat - note.startBeat > onsetWindow * tempoBPM / 60 + 0.000001 {
                    verdicts[note.id] = .missed
                    missedCount += 1
                    feedback = "有漏音，继续跟随当前位置"
                }
            }
        }
        let lastDeadline = (groups.last?.first?.startBeat ?? rangeEnd) + onsetWindow * tempoBPM / 60
        if beat >= max(rangeEnd, lastDeadline), groups.allSatisfy({ $0.allSatisfy(isResolved) }) {
            finish()
        }
    }

    public mutating func receive(_ event: NoteInput, at time: TimeInterval) {
        guard time.isFinite else { return }
        // Queued events from before this start/resume cannot belong to this run.
        if let start = runStartTime, time < start { return }
        // MIDI acquisition time may precede the most recent UI timer tick. Keep
        // the transport monotonic, but grade against the original event time.
        let inputLag = max(0, (lastTime ?? time) - time)
        let inputSeconds = runStartTime.map { runStartElapsed + time - $0 } ?? elapsedSeconds
        tick(at: time)
        switch event {
        case .sustain(let down):
            pedalDown = down
            if down {
                for pitch in Array(durationChecks.keys) { durationChecks[pitch]?.usedPedal = true }
                for pitch in Array(candidates.keys) where candidates[pitch]?.release == nil { candidates[pitch]?.usedPedal = true }
            }
        case .allNotesOff:
            heldPitches.removeAll()
            candidates.removeAll()
            durationChecks.removeAll()
            holdGuideEnds.removeAll()
            pedalDown = false
        case .off(let pitch):
            heldPitches.remove(pitch)
            candidates[pitch]?.release = inputSeconds
            if let check = durationChecks.removeValue(forKey: pitch) {
                reportDuration(pitch: pitch, check: check, releasedAt: inputSeconds)
            }
        case .on(let pitch, let velocity):
            guard (0...127).contains(pitch) else { return }
            if velocity <= 0 {
                receive(.off(pitch: pitch), at: time)
                return
            }
            // An already held key is not a fresh onset, even after the cursor advances.
            guard heldPitches.insert(pitch).inserted, isRunning, !isFinished else { return }
            guard inputLag <= maximumInputLag else {
                feedback = "输入事件延迟过长，本次按键未评分；请松键后继续"
                return
            }
            if mode == .wait { receiveWaiting(pitch: pitch, at: inputSeconds) }
            else { receiveRhythm(pitch: pitch, at: inputSeconds) }
        }
    }

    public mutating func reset() {
        currentBeat = rangeStart
        groupIndex = 0
        elapsedSeconds = 0
        lastTime = nil
        runStartTime = nil
        runStartElapsed = 0
        heldPitches.removeAll()
        candidates.removeAll()
        durationChecks.removeAll()
        holdGuideEnds.removeAll()
        pedalDown = false
        correctCount = 0
        wrongCount = 0
        missedCount = 0
        isRunning = false
        isFinished = groups.isEmpty
        durationFeedback = nil
        for key in Array(verdicts.keys) { verdicts[key] = .pending }
        feedback = groups.isEmpty ? "所选范围和声部没有可练习的音符" : "准备好后开始练习"
    }

    public func summary(at date: Date = Date()) -> PracticeSummary {
        PracticeSummary(date: date, scoreTitle: score.title, correct: correctCount,
                        wrong: wrongCount, missed: missedCount, durationSeconds: elapsedSeconds, mode: mode)
    }

    private func isResolved(_ note: ScoreNote) -> Bool {
        switch verdicts[note.id] ?? .pending {
        case .correct, .early, .late, .missed: return true
        case .pending, .wrong: return false
        }
    }

    private mutating func pruneCandidates(at inputSeconds: Double) {
        for (pitch, candidate) in candidates {
            if !heldPitches.contains(pitch), inputSeconds - candidate.onset > chordReleaseWindow {
                candidates.removeValue(forKey: pitch)
            }
        }
    }

    private mutating func receiveWaiting(pitch: Int, at inputSeconds: Double) {
        let notes = expectedNotes
        guard notes.contains(where: { $0.midi == pitch }) else {
            wrongCount += 1
            for note in notes { verdicts[note.id] = .wrong }
            feedback = "弹了 \(NoteNames.name(pitch))，请弹 \(Set(notes.map(\.name)).sorted().joined(separator: "、"))"
            return
        }
        pruneCandidates(at: inputSeconds)
        candidates[pitch] = Candidate(onset: inputSeconds, release: nil, usedPedal: pedalDown)
        guard Set(notes.map(\.midi)).isSubset(of: Set(candidates.keys)) else {
            feedback = "继续弹出同组和弦的其他音"
            return
        }
        for note in notes { verdicts[note.id] = .correct }
        correctCount += notes.count
        for pitch in Set(notes.map(\.midi)) {
            guard let candidate = candidates[pitch] else { continue }
            let beats = notes.filter { $0.midi == pitch }.map(\.durationBeats).max() ?? 0
            let check = DurationCheck(onset: candidate.onset, expected: beats * 60 / tempoBPM, usedPedal: candidate.usedPedal)
            holdGuideEnds[pitch] = candidate.onset + check.expected
            if let release = candidate.release { reportDuration(pitch: pitch, check: check, releasedAt: release) }
            else { durationChecks[pitch] = check }
        }
        candidates.removeAll()
        groupIndex += 1
        if groupIndex >= groups.count { finish() }
        else {
            currentBeat = groups[groupIndex][0].startBeat
            feedback = "正确，继续下一个音组"
        }
    }

    private mutating func receiveRhythm(pitch: Int, at inputSeconds: Double) {
        let beat = rangeStart + inputSeconds * tempoBPM / 60
        var matching: [ScoreNote] = []
        for group in groups {
            for note in group {
                let difference = abs((note.startBeat - beat) * 60 / tempoBPM)
                if note.midi == pitch && (!isResolved(note) || verdicts[note.id] == .missed) && difference <= onsetWindow + 0.000001 {
                    matching.append(note)
                }
            }
        }
        guard let nearest = matching.min(by: { abs($0.startBeat - beat) < abs($1.startBeat - beat) }) else {
            wrongCount += 1
            for note in expectedNotes where abs((note.startBeat - beat) * 60 / tempoBPM) <= onsetWindow {
                if !isResolved(note) { verdicts[note.id] = .wrong }
            }
            feedback = "\(NoteNames.name(pitch)) 的音高或起音时间不符，继续跟随谱面"
            return
        }
        let sameOnset = matching.filter { abs($0.startBeat - nearest.startBeat) < 0.000001 }
        let difference = (beat - nearest.startBeat) * 60 / tempoBPM
        let verdict: NoteVerdict = difference < -0.10 ? .early : (difference > 0.10 ? .late : .correct)
        for note in sameOnset {
            // A timer can mark a note missed just before its queued on-time
            // input arrives. Only the bounded, active-run path reaches here.
            if verdicts[note.id] == .missed { missedCount -= 1 }
            verdicts[note.id] = verdict
        }
        correctCount += sameOnset.count
        durationChecks[pitch] = DurationCheck(onset: inputSeconds,
            expected: (sameOnset.map(\.durationBeats).max() ?? 0) * 60 / tempoBPM, usedPedal: pedalDown)
        holdGuideEnds[pitch] = inputSeconds + (sameOnset.map(\.durationBeats).max() ?? 0) * 60 / tempoBPM
        feedback = verdict == .early ? "音高正确，起音稍早" : (verdict == .late ? "音高正确，起音稍晚" : "音高与起音正确")
    }

    private mutating func reportDuration(pitch: Int, check: DurationCheck, releasedAt: Double) {
        guard evaluatesNoteDuration else { return }
        let actual = max(0, releasedAt - check.onset)
        let tolerance = max(0.20, check.expected * 0.25)
        let result = actual < check.expected - tolerance ? "偏短" : (actual > check.expected + tolerance ? "偏长" : "合适")
        durationFeedback = "\(NoteNames.name(pitch)) 按键时长\(result)（目标 \(String(format: "%.1f", check.expected)) 秒）"
        if check.usedPedal { durationFeedback! += "；已使用延音踏板，松键不代表声音结束" }
    }

    private mutating func finish() {
        isFinished = true
        isRunning = false
        // Retain the run time origin to measure the final key release.
        lastTime = nil
        feedback = "本段练习完成"
    }
}
