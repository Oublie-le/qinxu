import Foundation
import Combine
import SwiftUI
import AVFoundation
import PianoCore

enum InputMode: String, CaseIterable {
    case midi, touch, microphone
    var title: String {
        switch self { case .midi: return "MIDI 钢琴"; case .touch: return "屏幕琴键"; case .microphone: return "麦克风（实验）" }
    }
}

@MainActor
final class PracticeViewModel: ObservableObject {
    @Published var scores: [PianoScore]
    @Published var selectedScoreID: String
    @Published var mode: PracticeMode = .wait
    @Published var hand: PracticeHand = .both
    @Published var tempo: Double
    @Published var loopEnabled = false
    @Published var loopStart = 1
    @Published var loopEnd = 1
    @Published var history: [PracticeSummary] = []
    @Published var engine: PracticeEngine
    @Published var midi: MIDIService
    @Published var microphone: MicrophoneService
    @Published var errorMessage: String?
    @Published var isImporting = false
    @Published var inputMode: InputMode = .touch
    @Published var countdown: Int?
    @Published var metronomeEnabled = true
    private var countdownEnd: TimeInterval?
    private var loopRestartAt: TimeInterval?
    private var sessionSaved = false
    private var lastMetronomeBeat: String?
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private let metronome = Metronome()
    private let storage: LocalLibraryStore
    private var transitionID = 0

    init(storage: LocalLibraryStore = LocalLibraryStore()) {
        self.storage = storage
        let library = storage.load()
        let all = DemoScores.all + library.scores
        scores = all
        let initial = all.first(where: { $0.id == library.lastScoreID }) ?? all[0]
        selectedScoreID = initial.id; tempo = initial.tempoBPM
        loopEnd = max(1, initial.measures.count)
        engine = PracticeEngine(score: initial)
        history = library.history
        midi = MIDIService(); microphone = MicrophoneService()
        if midi.connected { inputMode = .midi }
        if let error = library.error { errorMessage = error }
        midi.onEvent = { [weak self] event, time in
            guard let self, self.inputMode == .midi else { return }
            self.receive(event, at: time)
        }
        microphone.onEvent = { [weak self] event, time in
            guard let self, self.inputMode == .microphone else { return }
            self.receive(event, at: time)
        }
        midi.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        microphone.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        midi.$connected.dropFirst().sink { [weak self] connected in
            guard let self, !connected, self.inputMode == .midi else { return }
            self.stopTransport()
        }.store(in: &cancellables)
        #if os(iOS)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.stopTransport() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] notification in
                guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                self?.stopTransport()
            }.store(in: &cancellables)
        #endif
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var selectedScore: PianoScore { scores.first(where: { $0.id == selectedScoreID }) ?? scores[0] }
    var isPlaying: Bool { engine.isRunning || countdownEnd != nil || loopRestartAt != nil }
    var midiStatus: String { midi.status }
    var inputStatus: String {
        switch inputMode {
        case .midi: return midi.status
        case .touch: return "屏幕琴键用于练习与调试 · 不输出钢琴音色"
        case .microphone: return microphone.status
        }
    }

    func selectScore(_ id: String) {
        guard scores.contains(where: { $0.id == id }) else { return }
        selectedScoreID = id; tempo = min(300, max(20, selectedScore.tempoBPM))
        loopStart = 1; loopEnd = max(1, selectedScore.measures.count)
        if hand == .left && !selectedScore.notes.contains(where: { $0.staff == 2 }) { hand = .both }
        reconfigure(); saveLibrary()
    }

    func reconfigure() {
        stopTransport()
        tempo = tempo.isFinite ? min(300, max(20, tempo)) : 80
        let total = max(1, selectedScore.measures.count)
        loopStart = min(total, max(1, loopStart)); loopEnd = min(total, max(loopStart, loopEnd))
        if inputMode == .microphone { mode = .wait }
        engine = PracticeEngine(score: selectedScore, mode: mode, hand: hand, tempoBPM: tempo,
                                measureRange: loopEnabled ? loopStart...loopEnd : nil)
        sessionSaved = false; lastMetronomeBeat = nil
    }

    func togglePlayback() {
        if isPlaying { stopTransport(); return }
        if loopEnabled, let issue = PracticeTiming.loopStartIssue(score: selectedScore, hand: hand, startMeasure: loopStart) {
            errorMessage = issue; return
        }
        if engine.isFinished { reconfigure() }
        guard !engine.isFinished else {
            errorMessage = "所选声部或小节没有音符，请换一个练习范围。"; return
        }
        if inputMode == .midi && !midi.connected {
            errorMessage = "还没有连接 MIDI 钢琴。连接后刷新设备，或切换为屏幕琴键。"; return
        }
        if inputMode == .microphone {
            guard validateMicrophoneSubset() else { return }
            transitionID += 1
            let token = transitionID
            Task { [weak self] in
                guard let self else { return }
                await self.microphone.start()
                guard self.transitionID == token, self.inputMode == .microphone, self.microphone.isActive else { return }
                self.engine.start(at: ProcessInfo.processInfo.systemUptime)
            }
        } else if mode == .rhythm {
            metronome.prepareSession()
            let pulses = selectedScore.beatsPerMeasure
            let secondsPerPulse = 4.0 / Double(selectedScore.beatUnit) * 60 / tempo
            countdownEnd = ProcessInfo.processInfo.systemUptime + Double(pulses) * secondsPerPulse
            countdown = pulses; lastMetronomeBeat = nil
        } else {
            engine.start(at: ProcessInfo.processInfo.systemUptime)
        }
    }

    func restart() { reconfigure() }
    func press(_ pitch: Int) {
        guard inputMode == .touch else { return }
        receive(.on(pitch: pitch, velocity: 90), at: ProcessInfo.processInfo.systemUptime)
    }
    func release(_ pitch: Int) {
        guard inputMode == .touch else { return }
        receive(.off(pitch: pitch), at: ProcessInfo.processInfo.systemUptime)
    }
    func refreshMIDI() { midi.refresh() }

    func setInputMode(_ newMode: InputMode) {
        stopTransport()
        inputMode = newMode
        if newMode == .microphone { mode = .wait }
        reconfigure()
    }

    func importScore(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 5_000_000 else { throw LibraryError.message("曲谱超过 5 MB，请选择较小的 MusicXML 文件。") }
            let data = try Data(contentsOf: url)
            var score = try MusicXMLParser().parse(data: data)
            // Each import is independent; imported notes keep their stable IDs within this score.
            score.id = UUID().uuidString
            if scores.count >= 103 { throw LibraryError.message("当前最多保存 100 首导入曲谱。") }
            scores.append(score)
            selectScore(score.id)
        } catch { errorMessage = error.localizedDescription }
    }

    func suspendForBackground() { stopTransport() }

    private func stopTransport() {
        transitionID += 1
        countdownEnd = nil; countdown = nil; loopRestartAt = nil
        engine.pause(at: ProcessInfo.processInfo.systemUptime)
        engine.receive(.allNotesOff, at: ProcessInfo.processInfo.systemUptime)
        microphone.stop()
    }

    private func receive(_ event: NoteInput, at time: TimeInterval) {
        guard countdownEnd == nil, loopRestartAt == nil else { return }
        engine.receive(event, at: time)
        finishIfNeeded(at: ProcessInfo.processInfo.systemUptime)
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if let end = countdownEnd {
            if now >= end {
                countdownEnd = nil; countdown = nil; lastMetronomeBeat = nil
                engine.start(at: end)
            } else {
                let secondsPerPulse = 4.0 / Double(selectedScore.beatUnit) * 60 / tempo
                let count = max(1, Int(ceil((end - now) / secondsPerPulse)))
                if countdown != count { countdown = count }
                if lastMetronomeBeat != "count-\(count)" {
                    if metronomeEnabled { metronome.play(accented: count == selectedScore.beatsPerMeasure) }
                    lastMetronomeBeat = "count-\(count)"
                }
                return
            }
        }
        if let restartTime = loopRestartAt {
            guard now >= restartTime else { return }
            loopRestartAt = nil
            engine.reset(); sessionSaved = false; lastMetronomeBeat = nil
            engine.start(at: now)
        }
        if engine.isRunning {
            engine.tick(at: now)
            if engine.isRunning && mode == .rhythm && inputMode != .microphone {
                if let position = PracticeTiming.metronomePosition(atQuarterBeat: engine.currentBeat, score: selectedScore),
                   lastMetronomeBeat != position.id {
                    if metronomeEnabled { metronome.play(accented: position.accented) }
                    lastMetronomeBeat = position.id
                }
            }
        }
        finishIfNeeded(at: now)
    }

    private func finishIfNeeded(at now: TimeInterval) {
        guard engine.isFinished, !sessionSaved, engine.correctCount + engine.wrongCount + engine.missedCount > 0 else { return }
        sessionSaved = true
        history.insert(engine.summary(), at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
        saveLibrary()
        if loopEnabled { loopRestartAt = now + 1 }
        else if inputMode == .microphone { microphone.stop() }
    }

    private func validateMicrophoneSubset() -> Bool {
        let notes = selectedScore.notes.filter {
            hand.includes(staff: $0.staff) && (!loopEnabled || (loopStart...loopEnd).contains($0.measure))
        }.sorted { $0.startBeat < $1.startBeat }
        guard notes.allSatisfy({ (48...84).contains($0.midi) }) else {
            errorMessage = "麦克风实验模式只覆盖 C3–C6，请选择合适音域的单音曲目。"; return false
        }
        for pair in zip(notes, notes.dropFirst()) {
            if pair.1.startBeat < pair.0.startBeat + pair.0.durationBeats - 0.001 {
                errorMessage = "麦克风实验模式暂不支持和弦或重叠音。请选择右手单旋律，逐个音练习，不踩踏板。"; return false
            }
        }
        return true
    }

    private func saveLibrary() {
        do {
            try storage.save(scores: scores.filter { !DemoScores.all.map(\.id).contains($0.id) }, history: history, lastScoreID: selectedScoreID)
        } catch { errorMessage = "保存练习数据失败：\(error.localizedDescription)" }
    }
}

enum LibraryError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
