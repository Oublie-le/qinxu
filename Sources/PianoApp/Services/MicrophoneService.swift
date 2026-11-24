import Foundation
import Combine
import AVFoundation
import PianoCore

@MainActor
final class MicrophoneService: ObservableObject {
    @Published private(set) var status = "实验模式 · 仅支持 C3–C6 的逐个单音"
    @Published private(set) var isActive = false
    @Published private(set) var detectedPitch: Int?
    @Published private(set) var level = 0.0
    var onEvent: ((NoteInput, TimeInterval) -> Void)?
    private let audioEngine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "PianoPractice.pitch", qos: .userInitiated)
    private var candidate: Int?
    private var candidateFrames = 0
    private var silentFrames = 0
    private var generation = 0
    private var hasTap = false

    func start() async {
        guard !isActive else { return }
        generation += 1
        let token = generation
        #if os(iOS)
        let allowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        #else
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        #endif
        guard token == generation else { return }
        guard allowed else { status = "麦克风权限未开启，请在系统设置中允许访问"; return }
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
            #endif
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                status = "没有可用的麦克风输入"; deactivateAudioSession(); return
            }
            let window = AudioAnalysisWindow()
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                guard let channel = buffer.floatChannelData?[0] else { return }
                let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                let rate = buffer.format.sampleRate
                let capturedAt = ProcessInfo.processInfo.systemUptime
                // A serial queue preserves window order; the bounded analysis window avoids unbounded audio storage.
                self?.analysisQueue.async { [weak self] in
                    guard let block = window.append(samples, sampleRate: rate) else { return }
                    let estimate = MonophonicPitchDetector.detect(samples: block, sampleRate: rate)
                    let rms = sqrt(block.reduce(0.0) { $0 + Double($1 * $1) } / Double(block.count))
                    Task { @MainActor in
                        guard let self, self.isActive, self.generation == token else { return }
                        self.consume(estimate, rms: rms, at: capturedAt)
                    }
                }
            }
            hasTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isActive = true
            status = "正在听单音 · 请逐音弹奏，间隔短暂停顿，不踩踏板"
        } catch {
            if hasTap { audioEngine.inputNode.removeTap(onBus: 0); hasTap = false }
            audioEngine.stop(); deactivateAudioSession()
            status = "麦克风启动失败：\(error.localizedDescription)"
        }
    }

    func stop() {
        generation += 1
        audioEngine.stop()
        if hasTap { audioEngine.inputNode.removeTap(onBus: 0); hasTap = false }
        if let pitch = detectedPitch { onEvent?(.off(pitch: pitch), ProcessInfo.processInfo.systemUptime) }
        isActive = false; detectedPitch = nil; candidate = nil; candidateFrames = 0; silentFrames = 0; level = 0
        status = "实验模式 · 仅支持 C3–C6 的逐个单音"
        deactivateAudioSession()
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func consume(_ estimate: PitchEstimate?, rms: Double, at time: TimeInterval) {
        level = min(1, rms * 8)
        guard let estimate else {
            candidate = nil; candidateFrames = 0
            silentFrames += 1
            if silentFrames >= 2, let pitch = detectedPitch {
                detectedPitch = nil; onEvent?(.off(pitch: pitch), time)
            }
            return
        }
        silentFrames = 0
        if candidate == estimate.midi { candidateFrames += 1 } else { candidate = estimate.midi; candidateFrames = 1 }
        guard candidateFrames >= 2, detectedPitch != estimate.midi else { return }
        if let pitch = detectedPitch { onEvent?(.off(pitch: pitch), time) }
        detectedPitch = estimate.midi
        onEvent?(.on(pitch: estimate.midi, velocity: 80), time)
    }
}

private final class AudioAnalysisWindow: @unchecked Sendable {
    private var samples: [Float] = []
    func append(_ incoming: [Float], sampleRate: Double) -> [Float]? {
        samples.append(contentsOf: incoming)
        // ~90 ms gives low notes enough periods. Frames overlap for stable classification.
        let count = max(2048, Int(sampleRate * 0.09))
        guard samples.count >= count else { return nil }
        let result = Array(samples.suffix(count))
        samples = Array(samples.suffix(count / 2))
        return result
    }
}
