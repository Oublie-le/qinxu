import AVFoundation
import Testing
@testable import QinXuApp

@MainActor
struct ScoreAuditionAudioTests {
    @Test func bundledPianoRendersSoundAcrossTheKeyboard() throws {
        let bank = try #require(ScoreAuditionPlayer.soundBankURL)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        for pitch: UInt8 in [21, 60, 108] {
            let engine = AVAudioEngine()
            let sampler = AVAudioUnitSampler()
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: format)
            try ScoreAuditionPlayer.loadPiano(sampler, from: bank)
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
            try engine.start()
            defer { engine.stop() }
            sampler.startNote(pitch, withVelocity: 79, onChannel: 0)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
            var peak: Float = 0
            for _ in 0..<12 {
                let status = try engine.renderOffline(512, to: buffer)
                try #require(status == .success)
                let channel = try #require(buffer.floatChannelData?[0])
                for frame in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[frame])) }
            }
            #expect(peak > 0.0005, "The piano bank should output a signal for MIDI note \(pitch).")
        }
    }
}
