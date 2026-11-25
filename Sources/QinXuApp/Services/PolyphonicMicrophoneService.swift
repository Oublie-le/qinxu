import Foundation
import Combine
import AVFoundation
import Darwin
import QinXuCore

/// Buffered acoustic recognition. It does not estimate key release or grade rhythm.
@MainActor
final class PolyphonicMicrophoneService: ObservableObject {
    static let idleStatus = "双手与和弦 · 实验模式，约 2 秒音频窗口"
    @Published private(set) var status = idleStatus
    @Published private(set) var isActive = false
    @Published private(set) var detectedPitches: Set<Int> = []
    @Published private(set) var level = 0.0
    @Published private(set) var inferenceMilliseconds: Double?
    @Published private(set) var analysisDelayMilliseconds: Double?
    var onEvent: ((NoteInput, TimeInterval) -> Void)?
    private let deviceAccessEnabled: Bool
    private lazy var audioEngine = AVAudioEngine()
    private let queue = DispatchQueue(label: "QinXu.polyphonic", qos: .userInitiated)
    private let analysisSlot = DispatchSemaphore(value: 1)
    private var generation = 0
    private var isStarting = false
    private var hasTap = false
    private var ownsAudioSession = false
    private var configurationObserver: AnyCancellable?

    init(deviceAccessEnabled: Bool = true) { self.deviceAccessEnabled = deviceAccessEnabled }

    func start() async {
        guard deviceAccessEnabled else { status = "麦克风设备访问已停用"; return }
        guard !isActive, !isStarting else { return }
        guard BasicPitchModel.resourceURL != nil else { status = BasicPitchModel.ModelError.missing.localizedDescription; return }
        generation += 1
        let token = generation
        isStarting = true
        inferenceMilliseconds = nil; analysisDelayMilliseconds = nil
        status = "正在准备双手识音模型…"
        defer { if generation == token { isStarting = false } }
        let worker = PolyphonicAnalysisWorker()
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.queue.async {
                    do { try worker.prepare(); continuation.resume() }
                    catch { continuation.resume(throwing: error) }
                }
            }
            guard generation == token else { return }
            #if os(iOS)
            let allowed = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
            }
            #else
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            #endif
            guard generation == token else { return }
            guard allowed else { status = "麦克风权限未开启，请在系统设置中允许访问"; return }
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
            ownsAudioSession = true
            #endif
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                stop(); status = "没有可用的麦克风输入"; return
            }
            let hostBefore = AVAudioTime.seconds(forHostTime: mach_absolute_time())
            let uptime = ProcessInfo.processInfo.systemUptime
            let hostAfter = AVAudioTime.seconds(forHostTime: mach_absolute_time())
            guard hostAfter - hostBefore <= 0.01 else { throw PolyphonicAudioMailbox.TimelineError.invalidTimestamp }
            let captureClock = AudioCaptureClock(hostSeconds: (hostBefore + hostAfter) / 2, uptime: uptime)
            let mailbox = PolyphonicAudioMailbox(sampleRate: format.sampleRate)
            let queue = self.queue, slot = analysisSlot
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, when in
                guard let channel = buffer.floatChannelData?[0] else { return }
                do {
                    guard when.isSampleTimeValid, when.isHostTimeValid,
                          abs(when.sampleRate - buffer.format.sampleRate) < 0.01 else {
                        throw PolyphonicAudioMailbox.TimelineError.invalidTimestamp
                    }
                    // AVAudioTime describes capture time. Callback arrival time is never
                    // used to concatenate samples, schedule a window, or deduplicate frames.
                    try mailbox.append(channel, count: Int(buffer.frameLength), sampleTime: when.sampleTime,
                                       captureTime: captureClock.timestamp(hostSeconds: AVAudioTime.seconds(forHostTime: when.hostTime)))
                    guard mailbox.isReady(), slot.wait(timeout: .now()) == .success else { return }
                    let snapshot = mailbox.snapshot()
                    queue.async { [weak self] in
                        defer { slot.signal() }
                        do {
                            let result = try worker.process(snapshot)
                            Task { @MainActor in
                                guard let self, self.isActive, self.generation == token else { return }
                                self.consume(result)
                            }
                        } catch {
                            Task { @MainActor in
                                guard let self, self.isActive, self.generation == token else { return }
                                self.stop(); self.status = "双手识音停止：\(error.localizedDescription)"
                            }
                        }
                    }
                } catch {
                    Task { @MainActor in
                        guard let self, self.isActive, self.generation == token else { return }
                        self.stop(); self.status = "双手识音停止：\(error.localizedDescription)"
                    }
                }
            }
            hasTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isActive = true
            status = "正在听双手与和弦 · 首次约 2 秒，实琴准确率待验证"
            configurationObserver = NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange, object: audioEngine)
                .receive(on: RunLoop.main).sink { [weak self] _ in
                    guard let self, self.isActive else { return }
                    self.stop()
                    self.status = "音频设备发生变化，识音已停止，请重新开始"
                }
        } catch {
            guard generation == token else { return }
            stop(); status = "双手识音启动失败：\(error.localizedDescription)"
        }
    }

    func stop() {
        let hadActiveSession = isActive || isStarting || hasTap
        generation += 1
        isStarting = false
        configurationObserver = nil
        if isActive || hasTap { audioEngine.stop() }
        if hasTap { audioEngine.inputNode.removeTap(onBus: 0); hasTap = false }
        let time = ProcessInfo.processInfo.systemUptime
        for pitch in detectedPitches.sorted() { onEvent?(.off(pitch: pitch), time) }
        isActive = false; detectedPitches = []; level = 0
        // Keep the last real measurement visible after opening the device sheet.
        // A repeated inactive stop must also preserve a useful startup/failure message.
        if hadActiveSession { status = Self.idleStatus }
        #if os(iOS)
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
        #endif
    }

    private func consume(_ result: PolyphonicAnalysisWorker.Result) {
        level = min(1, result.rms * 8)
        inferenceMilliseconds = result.inferenceSeconds * 1_000
        analysisDelayMilliseconds = max(0, ProcessInfo.processInfo.systemUptime - result.latestFrameTime) * 1_000
        detectedPitches = result.activePitches
        let token = generation
        PolyphonicEventDelivery.deliver(result.events, while: { self.isActive && self.generation == token }) { event in
            self.onEvent?(event.isOn ? .on(pitch: event.pitch, velocity: 80) : .off(pitch: event.pitch), event.time)
        }
    }
}

/// Bridges the audio host clock to the engine's ProcessInfo.systemUptime clock once.
/// A later callback's arrival latency cannot change an event's capture timestamp.
struct AudioCaptureClock {
    let hostSeconds: TimeInterval
    let uptime: TimeInterval
    func timestamp(hostSeconds value: TimeInterval) -> TimeInterval { uptime + value - hostSeconds }
}

/// Stable ordering and cancellation are shared with the offline regression test.
enum PolyphonicEventDelivery {
    static func deliver(_ events: [PolyphonicNoteTracker.Event], while isCurrent: () -> Bool,
                        receive: (PolyphonicNoteTracker.Event) -> Void) {
        let ordered = events.enumerated().sorted {
            $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time
        }
        for (_, event) in ordered {
            guard isCurrent() else { return }
            receive(event)
        }
    }
}

final class PolyphonicAudioMailbox: @unchecked Sendable {
    struct Snapshot: Sendable {
        let samples: [Float]
        let sampleRate: Double
        let startSample: Int64
        let endSample: Int64
        let streamStartSample: Int64
        let streamStartTime: TimeInterval
        var startTime: TimeInterval { streamStartTime + Double(startSample - streamStartSample) / sampleRate }
    }
    enum TimelineError: LocalizedError {
        case invalidTimestamp, discontinuity
        var errorDescription: String? {
            switch self {
            case .invalidTimestamp: return "麦克风未提供可靠的采集时间，请重新开始。"
            case .discontinuity: return "音频采集中断或时钟发生变化，请重新开始。"
            }
        }
    }
    private let lock = NSLock()
    private let sampleRate: Double
    private var ring: [Float]
    private var position = 0
    private var filled = 0
    private var nextSample: Int64?
    private var streamStartSample: Int64?
    private var streamStartTime: TimeInterval?
    private var lastScheduledEnd: Int64?
    private var failed = false
    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        ring = Array(repeating: 0, count: Int(ceil(Double(BasicPitchModel.sampleCount) * sampleRate / BasicPitchModel.sampleRate)))
    }
    func append(_ pointer: UnsafePointer<Float>, count: Int, sampleTime: Int64, captureTime: TimeInterval) throws {
        lock.lock(); defer { lock.unlock() }
        guard !failed, count > 0, captureTime.isFinite, captureTime >= 0 else {
            failed = true; throw TimelineError.invalidTimestamp
        }
        if let nextSample, nextSample != sampleTime {
            failed = true; filled = 0; throw TimelineError.discontinuity
        }
        if let anchor = streamStartSample, let time = streamStartTime {
            let expected = time + Double(sampleTime - anchor) / sampleRate
            guard abs(captureTime - expected) <= 0.05 else {
                failed = true; filled = 0; throw TimelineError.discontinuity
            }
        } else { streamStartSample = sampleTime; streamStartTime = captureTime }
        for index in 0..<count { ring[position] = pointer[index]; position = (position + 1) % ring.count }
        filled = min(ring.count, filled + count)
        nextSample = sampleTime + Int64(count)
    }
    func isReady() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !failed, filled == ring.count, let nextSample else { return false }
        return lastScheduledEnd.map { nextSample - $0 >= Int64(sampleRate * 0.20) } ?? true
    }
    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        let end = nextSample!
        lastScheduledEnd = end
        return Snapshot(samples: Array(ring[position...] + ring[..<position]), sampleRate: sampleRate,
                        startSample: end - Int64(ring.count), endSample: end,
                        streamStartSample: streamStartSample!, streamStartTime: streamStartTime!)
    }
}

private final class PolyphonicAnalysisWorker: @unchecked Sendable {
    struct Result: Sendable {
        let events: [PolyphonicNoteTracker.Event]
        let activePitches: Set<Int>
        let rms: Double
        let inferenceSeconds: TimeInterval
        let latestFrameTime: TimeInterval
    }
    private var model: BasicPitchModel?
    private var tracker = PolyphonicNoteTracker()
    private var lastFrameIndex: Int64 = -1
    private var pendingEvents: [PolyphonicNoteTracker.Event] = []
    func prepare() throws { model = try BasicPitchModel() }
    func process(_ snapshot: PolyphonicAudioMailbox.Snapshot) throws -> Result {
        guard let model else { throw BasicPitchModel.ModelError.missing }
        let audio = try BasicPitchModel.resample(snapshot.samples, from: snapshot.sampleRate)
        let prediction = try model.predict(samples: audio)
        let baseFrame = Int64(floor(Double(snapshot.startSample - snapshot.streamStartSample) / snapshot.sampleRate / BasicPitchModel.frameHop))
        var latestTime = snapshot.startTime
        // Deduplicate by capture-sample position, unaffected by callback/inference jitter.
        for frame in BasicPitchModel.edgeFrames..<(BasicPitchModel.frameCount - BasicPitchModel.edgeFrames) {
            let index = baseFrame + Int64(frame)
            let time = snapshot.startTime + Double(frame) * BasicPitchModel.frameHop
            latestTime = time
            guard index > lastFrameIndex else { continue }
            pendingEvents += tracker.consume(notes: prediction.notes[frame], onsets: prediction.onsets[frame], at: time)
            lastFrameIndex = index
        }
        // Confirmed onsets are backdated by up to 10 frames. Hold newer releases
        // briefly so cross-window event order remains acoustic chronological order.
        let horizon = latestTime - 11 * BasicPitchModel.frameHop
        var events: [PolyphonicNoteTracker.Event] = []
        pendingEvents.removeAll { event in
            if event.time <= horizon { events.append(event); return true }
            return false
        }
        let recent = audio.suffix(4_410)
        let rms = sqrt(recent.reduce(0.0) { $0 + Double($1 * $1) } / Double(recent.count))
        return Result(events: events, activePitches: tracker.activePitches, rms: rms,
                      inferenceSeconds: prediction.inferenceSeconds, latestFrameTime: horizon)
    }
}
