import Foundation

/// Acoustic note activity, not physical key releases or pedal state.
/// Each frame carries all 88 independent probabilities; no score pitches are used.
public struct PolyphonicNoteTracker: Sendable {
    public struct Event: Equatable, Sendable {
        public let pitch: Int
        public let isOn: Bool
        public let time: TimeInterval
        public init(pitch: Int, isOn: Bool, time: TimeInterval) {
            self.pitch = pitch; self.isOn = isOn; self.time = time
        }
    }
    private struct State: Sendable {
        var active = false
        var candidateFrames = 0
        var onsetTime: TimeInterval = 0
        var quietFrames = 0
        var onsetArmed = true
        var lowOnsetFrames = 0
    }
    private var states = Array(repeating: State(), count: 88)
    private var lastFrameTime: TimeInterval?
    public var activePitches: Set<Int> {
        Set(states.indices.filter { states[$0].active }.map { $0 + 21 })
    }
    public init() {}

    /// Uses Basic Pitch's published onset/frame thresholds and ~128ms minimum note.
    /// A new acoustic onset while a note rings generates off/on for repeated keys.
    public mutating func consume(notes: [Float], onsets: [Float], at time: TimeInterval) -> [Event] {
        guard notes.count == 88, onsets.count == 88, time.isFinite,
              lastFrameTime.map({ time > $0 }) ?? true,
              notes.allSatisfy({ $0.isFinite }), onsets.allSatisfy({ $0.isFinite }) else { return [] }
        var events: [Event] = []
        if let last = lastFrameTime, time - last > 0.1 {
            events = reset(at: time)
        }
        lastFrameTime = time
        for index in 0..<88 {
            var state = states[index]
            let pitch = index + 21
            if onsets[index] < 0.3 {
                state.lowOnsetFrames += 1
                if state.lowOnsetFrames >= 3 { state.onsetArmed = true }
            } else { state.lowOnsetFrames = 0 }
            if onsets[index] >= 0.5, notes[index] >= 0.3, state.onsetArmed {
                state.onsetArmed = false
                state.candidateFrames = 1
                state.onsetTime = time
            } else if state.candidateFrames > 0 {
                if notes[index] >= 0.3 { state.candidateFrames += 1 }
                else { state.candidateFrames = 0 }
            }
            if state.candidateFrames >= 11 {
                if state.active { events.append(Event(pitch: pitch, isOn: false, time: state.onsetTime)) }
                events.append(Event(pitch: pitch, isOn: true, time: state.onsetTime))
                state.active = true
                state.candidateFrames = 0
                state.quietFrames = 0
            }
            if state.active {
                state.quietFrames = notes[index] < 0.2 ? state.quietFrames + 1 : 0
                if state.quietFrames >= 5 {
                    events.append(Event(pitch: pitch, isOn: false, time: time))
                    state.active = false
                }
            }
            states[index] = state
        }
        return events
    }

    @discardableResult public mutating func reset(at time: TimeInterval) -> [Event] {
        let events = activePitches.sorted().map { Event(pitch: $0, isOn: false, time: time) }
        states = Array(repeating: State(), count: 88)
        lastFrameTime = nil
        return events
    }
}
