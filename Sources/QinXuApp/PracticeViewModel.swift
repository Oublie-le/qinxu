import Foundation
import Combine
import SwiftUI
import AVFoundation
import QinXuCore

enum InputMode: String, CaseIterable {
    case midi, touch, microphone, microphonePolyphonic
    var isMicrophone: Bool { self == .microphone || self == .microphonePolyphonic }
    var title: String {
        switch self { case .midi: return "MIDI 钢琴"; case .touch: return "屏幕琴键"; case .microphone: return "单音麦克风（实验）"; case .microphonePolyphonic: return "双手麦克风（实验）" }
    }
}

@MainActor
final class PracticeViewModel: ObservableObject {
    @Published var scores: [PianoScore]
    @Published var selectedScoreID: String
    @Published private(set) var favoriteScoreIDs: Set<String> = []
    @Published private(set) var scoreCoverData: [String: Data] = [:]
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
    @Published var polyphonicMicrophone: PolyphonicMicrophoneService
    @Published var errorMessage: String?
    @Published var isImporting = false
    @Published var inputMode: InputMode = .touch
    @Published var countdown: Int?
    @Published var metronomeEnabled = true
    @Published private(set) var isStartingInput = false
    @Published private(set) var sustainedPitches: Set<Int> = []
    private var countdownEnd: TimeInterval?
    private var loopRestartAt: TimeInterval?
    private var sessionSaved = false
    private var lastMetronomeBeat: String?
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private let metronome: Metronome
    private let clock: () -> TimeInterval
    private let storage: LocalLibraryStore
    private let presentationStore: ScorePresentationStore
    private var transitionID = 0

    init(storage: LocalLibraryStore = LocalLibraryStore(),
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         automaticTimer: Bool = true, deviceAccessEnabled: Bool = true) {
        self.storage = storage
        self.presentationStore = ScorePresentationStore(libraryURL: storage.url)
        self.clock = clock
        self.metronome = Metronome(deviceAccessEnabled: deviceAccessEnabled)
        let library = storage.load()
        let all = DemoScores.all + BundledPracticeLibrary.scores + library.scores
        scores = all
        let initial = all.first(where: { $0.id == library.lastScoreID }) ?? all[0]
        selectedScoreID = initial.id; tempo = initial.tempoBPM
        loopEnd = max(1, initial.measures.count)
        engine = PracticeEngine(score: initial)
        history = library.history
        midi = MIDIService(deviceAccessEnabled: deviceAccessEnabled)
        microphone = MicrophoneService(deviceAccessEnabled: deviceAccessEnabled)
        polyphonicMicrophone = PolyphonicMicrophoneService(deviceAccessEnabled: deviceAccessEnabled)
        if midi.connected { inputMode = .midi }
        let presentation = presentationStore.load()
        favoriteScoreIDs = presentation.snapshot.favoriteScoreIDs
        scoreCoverData = presentation.snapshot.scoreCoverData
        let loadErrors = [library.error, presentation.error, BundledPracticeLibrary.beyer.error].compactMap { $0 }
        if !loadErrors.isEmpty { errorMessage = loadErrors.joined(separator: "\n") }
        midi.onEvent = { [weak self] event, time in
            guard let self, self.inputMode == .midi else { return }
            self.receive(event, at: time)
        }
        microphone.onEvent = { [weak self] event, time in
            guard let self, self.inputMode == .microphone else { return }
            self.receive(event, at: time)
        }
        polyphonicMicrophone.onEvent = { [weak self] event, time in
            guard let self, self.inputMode == .microphonePolyphonic else { return }
            self.receive(event, at: time)
        }
        polyphonicMicrophone.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        midi.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        microphone.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        polyphonicMicrophone.$isActive.dropFirst().sink { [weak self] active in
            guard let self, !active, self.inputMode == .microphonePolyphonic, self.isPlaying else { return }
            self.stopTransport()
        }.store(in: &cancellables)
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
        if automaticTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    deinit { timer?.invalidate() }

    var selectedScore: PianoScore { scores.first(where: { $0.id == selectedScoreID }) ?? scores[0] }
    var isPlaying: Bool { engine.isRunning || isStartingInput || countdownEnd != nil || loopRestartAt != nil }
    var midiStatus: String { midi.status }
    var inputStatus: String {
        switch inputMode {
        case .midi: return midi.status
        case .touch: return "屏幕琴键用于练习与调试 · 不输出钢琴音色"
        case .microphone: return microphone.status
        case .microphonePolyphonic: return polyphonicMicrophone.status
        }
    }

    func selectScore(_ id: String) { activateScore(id, persist: true) }

    private func activateScore(_ id: String, persist: Bool) {
        guard scores.contains(where: { $0.id == id }) else { return }
        selectedScoreID = id; tempo = min(300, max(20, selectedScore.tempoBPM))
        loopStart = 1; loopEnd = max(1, selectedScore.measures.count)
        if hand == .left && !selectedScore.notes.contains(where: { $0.staff == 2 }) { hand = .both }
        reconfigure()
        if persist { saveLibrary() }
    }

    func reconfigure() {
        stopTransport()
        tempo = tempo.isFinite ? min(300, max(20, tempo)) : 80
        let total = max(1, selectedScore.measures.count)
        loopStart = min(total, max(1, loopStart)); loopEnd = min(total, max(loopStart, loopEnd))
        if inputMode.isMicrophone { mode = .wait }
        engine = PracticeEngine(score: selectedScore, mode: mode, hand: hand, tempoBPM: tempo,
                                measureRange: loopEnabled ? loopStart...loopEnd : nil,
                                inputLagTolerance: inputMode == .microphonePolyphonic ? 3 : 0.25,
                                evaluatesNoteDuration: inputMode != .microphonePolyphonic)
        sustainedPitches = []
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
        if inputMode.isMicrophone {
            if inputMode == .microphone, !validateMicrophoneSubset() { return }
            if inputMode == .microphonePolyphonic, !validatePolyphonicRange() { return }
            let startingMode = inputMode
            transitionID += 1
            let token = transitionID
            isStartingInput = true
            Task { [weak self] in
                guard let self, self.transitionID == token,
                      self.isStartingInput, self.inputMode == startingMode else { return }
                if startingMode == .microphonePolyphonic { await self.polyphonicMicrophone.start() }
                else { await self.microphone.start() }
                guard self.transitionID == token else { return }
                self.isStartingInput = false
                guard self.inputMode == startingMode,
                      startingMode == .microphonePolyphonic ? self.polyphonicMicrophone.isActive : self.microphone.isActive else { return }
                self.engine.start(at: self.clock())
            }
        } else if mode == .rhythm {
            if metronomeEnabled { metronome.prepareSession() }
            let pulses = selectedScore.beatsPerMeasure
            let secondsPerPulse = 4.0 / Double(selectedScore.beatUnit) * 60 / tempo
            countdownEnd = clock() + Double(pulses) * secondsPerPulse
            countdown = pulses; lastMetronomeBeat = nil
        } else {
            engine.start(at: clock())
        }
    }

    func restart() { reconfigure() }
    func press(_ pitch: Int) {
        guard inputMode == .touch else { return }
        receive(.on(pitch: pitch, velocity: 90), at: clock())
    }
    func release(_ pitch: Int) {
        guard inputMode == .touch else { return }
        receive(.off(pitch: pitch), at: clock())
    }
    func refreshMIDI() { midi.refresh() }

    func setInputMode(_ newMode: InputMode) {
        stopTransport()
        inputMode = newMode
        if newMode.isMicrophone { mode = .wait }
        reconfigure()
    }

    func importScore(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 5_000_000 else { throw LibraryError.message("曲谱超过 5 MB，请选择较小的 MusicXML 文件。") }
            // Bound the actual read too: file metadata can be absent or change before reading.
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 5_000_001) ?? Data()
            guard data.count <= 5_000_000 else { throw LibraryError.message("曲谱超过 5 MB，请选择较小的 MusicXML 文件。") }
            var score = try MusicXMLParser().parse(data: data)
            // Each import is independent; imported notes keep their stable IDs within this score.
            score.id = UUID().uuidString
            let imported = scores.filter { !BundledPracticeLibrary.allBundledIDs.contains($0.id) }
            guard imported.count < 100 else { throw LibraryError.message("当前最多保存 100 首导入曲谱。") }
            // A failed disk write must not replace the current exercise with an unsaved import.
            try storage.save(scores: imported + [score], history: history, lastScoreID: score.id)
            scores.append(score)
            activateScore(score.id, persist: false)
        } catch { errorMessage = error.localizedDescription }
    }

    func toggleFavorite(_ scoreID: String) {
        guard scores.contains(where: { $0.id == scoreID }) else { return }
        var next = favoriteScoreIDs
        if next.contains(scoreID) { next.remove(scoreID) } else { next.insert(scoreID) }
        savePresentation(favorites: next, covers: scoreCoverData)
    }

    func importCover(from url: URL, for scoreID: String) {
        guard scores.contains(where: { $0.id == scoreID }) else { return }
        do {
            let data = try ScorePresentationStore.normalizedCover(from: url)
            var next = scoreCoverData
            next[scoreID] = data
            savePresentation(favorites: favoriteScoreIDs, covers: next)
        } catch { errorMessage = error.localizedDescription }
    }

    func removeCover(for scoreID: String) {
        guard scores.contains(where: { $0.id == scoreID }), scoreCoverData[scoreID] != nil else { return }
        var next = scoreCoverData
        next.removeValue(forKey: scoreID)
        savePresentation(favorites: favoriteScoreIDs, covers: next)
    }

    private func savePresentation(favorites: Set<String>, covers: [String: Data]) {
        do {
            try presentationStore.save(.init(favoriteScoreIDs: favorites, scoreCoverData: covers))
            // Publish only committed state; a failed save keeps the previous cover and favorite.
            favoriteScoreIDs = favorites
            scoreCoverData = covers
        } catch { errorMessage = "保存收藏与封面失败：\(error.localizedDescription)" }
    }

    func suspendForBackground() { stopTransport() }

    private func stopTransport() {
        transitionID += 1
        countdownEnd = nil; countdown = nil; loopRestartAt = nil; isStartingInput = false
        let now = clock()
        engine.pause(at: now)
        engine.receive(.allNotesOff, at: now)
        sustainedPitches = []
        // Pausing on the final beat may complete the engine. Save it, but never auto-restart.
        finishIfNeeded(at: now, allowLoopRestart: false)
        microphone.stop()
        polyphonicMicrophone.stop()
        metronome.stop()
    }

    private func receive(_ event: NoteInput, at time: TimeInterval) {
        guard countdownEnd == nil else { return }
        if loopRestartAt != nil, case .on(let pitch, let velocity) = event {
            // Loop rests reject fresh attacks, but a velocity-zero release still
            // needs to clear the physical/acoustic state shown by the keyboard.
            if velocity <= 0 { engine.receive(.off(pitch: pitch), at: time) }
            return
        }
        engine.receive(event, at: time)
        updateSustainGuidance(at: clock())
        finishIfNeeded(at: clock())
    }

    func tick() {
        let now = clock()
        updateSustainGuidance(at: now)
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
            updateSustainGuidance(at: now)
        }
        if engine.isRunning {
            engine.tick(at: now)
            if engine.isRunning && mode == .rhythm && !inputMode.isMicrophone {
                if let position = PracticeTiming.metronomePosition(atQuarterBeat: engine.currentBeat, score: selectedScore),
                   lastMetronomeBeat != position.id {
                    if metronomeEnabled { metronome.play(accented: position.accented) }
                    lastMetronomeBeat = position.id
                }
            }
        }
        finishIfNeeded(at: now)
    }

    private func updateSustainGuidance(at time: TimeInterval) {
        let next = engine.sustainedPitches(at: time)
        if sustainedPitches != next { sustainedPitches = next }
    }

    private func finishIfNeeded(at now: TimeInterval, allowLoopRestart: Bool = true) {
        guard engine.isFinished, !sessionSaved, engine.correctCount + engine.wrongCount + engine.missedCount > 0 else { return }
        sessionSaved = true
        history.insert(engine.summary(), at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
        saveLibrary()
        if loopEnabled && allowLoopRestart {
            loopRestartAt = max(now + 1, engine.sustainGuidanceEndTime ?? now)
        }
        else {
            metronome.stop()
            if inputMode == .microphone { microphone.stop() }
            if inputMode == .microphonePolyphonic { polyphonicMicrophone.stop() }
        }
    }

    private func validatePolyphonicRange() -> Bool {
        let notes = selectedScore.notes.filter {
            hand.includes(staff: $0.staff) && (!loopEnabled || (loopStart...loopEnd).contains($0.measure))
        }
        guard notes.allSatisfy({ (21...108).contains($0.midi) }) else {
            errorMessage = "双手识音模型覆盖钢琴 A0–C8，请选择此音域内的曲谱。"; return false
        }
        return true
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
            try storage.save(scores: scores.filter { !BundledPracticeLibrary.allBundledIDs.contains($0.id) }, history: history, lastScoreID: selectedScoreID)
        } catch { errorMessage = "保存练习数据失败：\(error.localizedDescription)" }
    }
}

enum LibraryError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
