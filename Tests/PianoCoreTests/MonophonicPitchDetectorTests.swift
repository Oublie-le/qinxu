import Foundation
import Testing
@testable import PianoCore

@Suite struct MonophonicPitchDetectorTests {
    @Test func testSilenceAndInvalidInput() {
        expectNil(MonophonicPitchDetector.detect(samples: Array(repeating: 0, count: 4096), sampleRate: 44100))
        expectNil(MonophonicPitchDetector.detect(samples: [.nan], sampleRate: 44100))
        expectNil(MonophonicPitchDetector.detect(samples: Array(repeating: 0.2, count: 4096), sampleRate: 44100))
    }
    @Test func testNotesAcrossSupportedRangeAndSampleRates() {
        for rate in [44100.0, 48000.0] {
            for midi in [48, 60, 69, 72, 84] {
                let f = 440 * pow(2, Double(midi - 69) / 12)
                let samples = (0..<Int(rate * 0.1)).map { i in Float(0.3 * sin(2 * .pi * f * Double(i) / rate)) }
                expectEqual(MonophonicPitchDetector.detect(samples: samples, sampleRate: rate)?.midi, midi, "midi=\(midi), rate=\(rate)")
            }
        }
    }
    @Test func testHarmonicPianoLikeTone() {
        let samples = (0..<4800).map { i -> Float in
            let phase = 2 * Double.pi * 261.6256 * Double(i) / 48000
            return Float(0.2 * sin(phase) + 0.12 * sin(2 * phase) + 0.05 * sin(3 * phase))
        }
        expectEqual(MonophonicPitchDetector.detect(samples: samples, sampleRate: 48000)?.midi, 60)
    }
}
