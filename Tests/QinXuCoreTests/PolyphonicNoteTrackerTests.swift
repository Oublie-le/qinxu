import Foundation
import Testing
@testable import QinXuCore

@Suite struct PolyphonicNoteTrackerTests {
    private let hop = 256.0 / 22_050
    private func probabilities(_ pitches: [Int], value: Float = 0.9) -> [Float] {
        var result = Array(repeating: Float(0), count: 88)
        for pitch in pitches { result[pitch - 21] = value }
        return result
    }

    @Test func bothHandsChordRequiresAcousticEvidenceForEveryPitch() {
        var tracker = PolyphonicNoteTracker()
        var events: [PolyphonicNoteTracker.Event] = []
        let pitches = [36, 48, 60, 64, 67]
        for frame in 0..<15 {
            events += tracker.consume(notes: probabilities(pitches),
                                      onsets: probabilities(frame == 0 ? pitches : []), at: Double(frame) * hop)
        }
        #expect(events.filter(\.isOn).map(\.pitch) == pitches)
        #expect(tracker.activePitches == Set(pitches))
        for frame in 15..<20 {
            events += tracker.consume(notes: probabilities([]), onsets: probabilities([]), at: Double(frame) * hop)
        }
        #expect(events.filter { !$0.isOn }.map(\.pitch) == pitches)
        #expect(tracker.activePitches.isEmpty)
    }

    @Test func frameEnergyAloneAndTransientOnsetsDoNotInventNotes() {
        var tracker = PolyphonicNoteTracker()
        for frame in 0..<20 {
            let notes = probabilities(frame < 4 ? [36, 60] : [36])
            let events = tracker.consume(notes: notes, onsets: probabilities(frame == 0 ? [60] : []), at: Double(frame) * hop)
            #expect(events.isEmpty)
        }
        #expect(tracker.activePitches.isEmpty)
    }

    @Test func repeatedChordProducesFreshOnsetsWithoutRequiringSilence() {
        var tracker = PolyphonicNoteTracker()
        var events: [PolyphonicNoteTracker.Event] = []
        for frame in 0..<35 {
            events += tracker.consume(notes: probabilities([48, 60]),
                                      onsets: probabilities(frame == 0 || frame == 20 ? [48, 60] : []), at: Double(frame) * hop)
        }
        #expect(events.filter(\.isOn).map(\.pitch) == [48, 60, 48, 60])
        #expect(events.filter { !$0.isOn }.map(\.pitch) == [48, 60])
    }

    @Test func overlapInvalidFramesAndDiscontinuityCannotDuplicateOrStickNotes() {
        var tracker = PolyphonicNoteTracker()
        for frame in 0..<12 {
            _ = tracker.consume(notes: probabilities([108]), onsets: probabilities(frame == 0 ? [108] : []), at: Double(frame) * hop)
        }
        #expect(tracker.consume(notes: probabilities([108]), onsets: probabilities([108]), at: 0).isEmpty)
        #expect(tracker.consume(notes: [1], onsets: [], at: 0.2).isEmpty)
        var invalid = probabilities([]); invalid[0] = .nan
        #expect(tracker.consume(notes: invalid, onsets: probabilities([]), at: 0.2).isEmpty)
        let gap = tracker.consume(notes: probabilities([]), onsets: probabilities([]), at: 1)
        #expect(gap.map(\.pitch) == [108] && gap.allSatisfy { !$0.isOn })
        #expect(tracker.activePitches.isEmpty)
        #expect(tracker.reset(at: 2).isEmpty)
    }
}
