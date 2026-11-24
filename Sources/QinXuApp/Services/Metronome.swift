import Foundation
import AVFoundation

@MainActor
final class Metronome {
    private var soft: AVAudioPlayer?
    private var accent: AVAudioPlayer?
    private let deviceAccessEnabled: Bool
    private var ownsAudioSession = false
    init(deviceAccessEnabled: Bool = true) {
        self.deviceAccessEnabled = deviceAccessEnabled
        guard deviceAccessEnabled else { return }
        soft = try? AVAudioPlayer(data: Self.click(frequency: 900))
        accent = try? AVAudioPlayer(data: Self.click(frequency: 1400))
        soft?.prepareToPlay(); accent?.prepareToPlay()
    }
    func play(accented: Bool) {
        guard deviceAccessEnabled else { return }
        if !ownsAudioSession { prepareSession() }
        let player = accented ? accent : soft
        player?.currentTime = 0; player?.play()
    }
    func prepareSession() {
        guard deviceAccessEnabled else { return }
        ownsAudioSession = true
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
    func stop() {
        soft?.stop(); accent?.stop()
        #if os(iOS)
        if ownsAudioSession { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        #endif
        ownsAudioSession = false
    }
    private static func click(frequency: Double) -> Data {
        let sampleRate = 44_100
        let count = 2205
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); word(UInt32(36 + count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8); word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
        word(UInt32(sampleRate)); word(UInt32(sampleRate * 2)); word(UInt16(2)); word(UInt16(16))
        data.append(contentsOf: "data".utf8); word(UInt32(count * 2))
        for sample in 0..<count {
            let t = Double(sample) / Double(sampleRate)
            word(Int16(10000 * sin(2 * .pi * frequency * t) * exp(-t * 95)))
        }
        return data
    }
}
