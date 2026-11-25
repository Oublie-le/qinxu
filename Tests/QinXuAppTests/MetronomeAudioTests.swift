import Foundation
import AVFoundation
import Testing
import QinXuCore
@testable import QinXuApp

@Suite @MainActor struct MetronomeAudioTests {
    @Test func renderedBarContainsTimedDownbeatsAndQuieterSubdivisions() throws {
        let settings = GlobalMetronomeSettings(beatsPerMeasure: 3, tempoBPM: 90, clickNote: .eighth)
        let data = try Metronome.audioData(for: settings)
        // AVAudioPlayer must parse the generated container without opening a session.
        let player = try AVAudioPlayer(data: data)
        #expect(abs(player.duration - 2) <= 1.0 / 44_100)
        let bytes = [UInt8](data.dropFirst(44))
        let samples = stride(from: 0, to: bytes.count, by: 2).map {
            Double(Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8))
        }
        func energy(start: Double, duration: Double) -> Double {
            let first = Int((start * 44_100).rounded())
            let end = min(samples.count, first + Int(duration * 44_100))
            return samples[first..<end].reduce(0) { $0 + $1 * $1 }
        }
        let downbeat = energy(start: 0, duration: 0.05)
        let offbeat = energy(start: 1.0 / 3, duration: 0.05)
        let beat = energy(start: 2.0 / 3, duration: 0.05)
        #expect(downbeat > beat && beat > offbeat && offbeat > 1_000_000)
        for click in 0..<6 {
            #expect(energy(start: Double(click) / 3, duration: 0.05) > 1_000_000)
            #expect(energy(start: Double(click) / 3 + 0.1, duration: 0.05) == 0)
        }
    }

    @Test func compoundMeterTempoUnitProducesExactlyOneBar() throws {
        let settings = GlobalMetronomeSettings(beatsPerMeasure: 6, beatUnit: 8, tempoBPM: 80,
            tempoNote: .dottedQuarter, clickNote: .sixteenth)
        let player = try AVAudioPlayer(data: Metronome.audioData(for: settings))
        #expect(abs(player.duration - 1.5) <= 1.0 / 44_100)
        #expect(settings.pulsesPerMeasure == 12)
        #expect(throws: (any Error).self) { try Metronome.audioData(for: .init(tempoBPM: .nan)) }
    }
}
