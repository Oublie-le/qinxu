import Foundation
import AVFoundation
import QinXuCore

/// Audio loops on the device's audio clock. The UI timer only updates the lights.
@MainActor
final class Metronome {
    private var player: AVAudioPlayer?
    private var preparedSettings: GlobalMetronomeSettings?
    private let deviceAccessEnabled: Bool
    private let clock: () -> TimeInterval
    private var ownsAudioSession = false

    init(deviceAccessEnabled: Bool = true,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.deviceAccessEnabled = deviceAccessEnabled
        self.clock = clock
    }

    func prepare(settings: GlobalMetronomeSettings) throws {
        guard settings.isValid else { throw LibraryError.message(settings.validationMessage ?? "节拍设置无效。") }
        guard deviceAccessEnabled else { return }
        var soundIndependent = settings
        soundIndependent.soundEnabled = true
        guard preparedSettings != soundIndependent || player == nil else { return }
        player?.stop()
        let next = try AVAudioPlayer(data: Self.audioData(for: soundIndependent))
        next.numberOfLoops = -1
        guard next.prepareToPlay() else { throw LibraryError.message("无法准备节拍音频。") }
        player = next; preparedSettings = soundIndependent
    }

    func start(settings: GlobalMetronomeSettings, anchor: TimeInterval) throws {
        guard deviceAccessEnabled else { return }
        try prepare(settings: settings)
        if !ownsAudioSession { try prepareSession() }
        guard let player else { throw LibraryError.message("无法创建节拍音频。") }
        player.stop()
        // Opening the audio session can take time; seek using the same monotonic
        // anchor as the lights rather than playing stale catch-up clicks.
        let elapsed = max(0, clock() - anchor)
        player.currentTime = elapsed.truncatingRemainder(dividingBy: settings.measureSeconds)
        guard player.play() else {
            stop(); throw LibraryError.message("无法播放节拍音频。")
        }
    }

    private func prepareSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        #endif
        ownsAudioSession = true
    }

    func stop() {
        player?.stop()
        #if os(iOS)
        if ownsAudioSession { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        #endif
        ownsAudioSession = false
    }

    /// One complete bar of mono PCM, with a strong downbeat, normal beats and
    /// softer subdivisions. Bar/click boundaries are rounded to audio samples,
    /// never to the 30 Hz UI refresh. This is synthesis, not an acoustic test.
    static func audioData(for settings: GlobalMetronomeSettings) throws -> Data {
        guard settings.isValid else { throw LibraryError.message(settings.validationMessage ?? "节拍设置无效。") }
        let sampleRate = 44_100
        let frameCount = Int((settings.measureSeconds * Double(sampleRate)).rounded())
        var samples = [Int16](repeating: 0, count: frameCount)
        for index in 0..<settings.pulsesPerMeasure {
            let start = Int((Double(index) * settings.pulseSeconds * Double(sampleRate)).rounded())
            let isDownbeat = index == 0
            let isBeat = index % settings.pulsesPerBeat == 0
            let frequency: Double = isDownbeat ? 1_400 : isBeat ? 1_000 : 700
            let amplitude: Double = isDownbeat ? 10_000 : isBeat ? 7_000 : 4_500
            let count = min(2_205, frameCount - start)
            guard count > 0 else { continue }
            for offset in 0..<count {
                let t = Double(offset) / Double(sampleRate)
                samples[start + offset] = Int16(amplitude * sin(2 * .pi * frequency * t) * exp(-t * 95))
            }
        }
        var data = Data(capacity: 44 + frameCount * 2)
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); word(UInt32(36 + frameCount * 2))
        data.append(contentsOf: "WAVEfmt ".utf8); word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
        word(UInt32(sampleRate)); word(UInt32(sampleRate * 2)); word(UInt16(2)); word(UInt16(16))
        data.append(contentsOf: "data".utf8); word(UInt32(frameCount * 2))
        for sample in samples { word(sample) }
        return data
    }
}
