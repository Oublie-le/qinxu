import Foundation

/// An intentionally monophonic detector. Returns nil for silence/unpitched input;
/// it is not a polyphonic piano transcription model or a key-release detector.
public struct PitchEstimate: Equatable, Sendable {
    public let midi: Int
    public let frequency: Double
    public let confidence: Double
    public let rms: Double
}

public enum MonophonicPitchDetector {
    public static func detect(samples: [Float], sampleRate: Double) -> PitchEstimate? {
        guard sampleRate.isFinite, sampleRate >= 8_000, samples.count >= 1024,
              samples.allSatisfy({ $0.isFinite }) else { return nil }
        // Downsample before YIN's difference calculation. This is a practice subset C3–C6.
        let stride = max(1, Int(sampleRate / 12_000))
        let rate = sampleRate / Double(stride)
        let count = min(samples.count / stride, 2048)
        guard count >= 512 else { return nil }
        var data = [Double](repeating: 0, count: count)
        for i in 0..<count {
            var sum = 0.0
            for j in 0..<stride { sum += Double(samples[i * stride + j]) }
            data[i] = sum / Double(stride)
        }
        let mean = data.reduce(0, +) / Double(count)
        for i in data.indices { data[i] -= mean }
        let rms = sqrt(data.reduce(0) { $0 + $1 * $1 } / Double(count))
        guard rms >= 0.008 else { return nil }
        let minLag = max(2, Int(rate / 1150))
        let maxLag = min(count / 2 - 1, Int(rate / 120))
        guard maxLag > minLag + 2 else { return nil }
        let window = count - maxLag
        var normalized = [Double](repeating: 1, count: maxLag + 1)
        var cumulative = 0.0
        for lag in 1...maxLag {
            var difference = 0.0
            for i in 0..<window {
                let delta = data[i] - data[i + lag]
                difference += delta * delta
            }
            cumulative += difference
            normalized[lag] = cumulative > 0 ? difference * Double(lag) / cumulative : 1
        }
        var best: Int?
        var lag = minLag
        while lag < maxLag {
            if normalized[lag] < 0.15 {
                while lag + 1 <= maxLag && normalized[lag + 1] < normalized[lag] { lag += 1 }
                best = lag; break
            }
            lag += 1
        }
        guard let tau = best, normalized[tau] < 0.15 else { return nil }
        var refined = Double(tau)
        if tau > 0 && tau < maxLag {
            let a = normalized[tau - 1], b = normalized[tau], c = normalized[tau + 1]
            let denominator = 2 * (2 * b - a - c)
            if abs(denominator) > 0.000001 { refined += (c - a) / denominator }
        }
        let frequency = rate / refined
        let midiFloat = 69 + 12 * log2(frequency / 440)
        let midi = Int(midiFloat.rounded())
        guard (48...84).contains(midi), abs(midiFloat - Double(midi)) < 0.4 else { return nil }
        return PitchEstimate(midi: midi, frequency: frequency, confidence: 1 - normalized[tau], rms: rms)
    }
}
