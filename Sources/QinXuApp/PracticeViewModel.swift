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
    @Published private(set) var tempo: Double
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
    @Published private(set) var metronomeSettings: GlobalMetronomeSettings
    @Published var showingMetronomeSettings = false
    @Published private(set) var metronomeRunning = false
    @Published private(set) var metronomeBeat: Int?
    @Published private(set) var metronomeSubdivision: Int?
    @Published private(set) var sustainGuidance: [SustainGuidance] = []
    @Published private(set) var latestReport: PracticeReport?
    @Published var showingReport = false
    @Published private(set) var checkpoints: [String: PracticeCheckpoint] = [:]
    @Published private(set) var practiceStartMeasure = 1
    @Published private(set) var isStartingInput = false
    @Published private(set) var sustainedPitches: Set<Int> = []
    @Published private(set) var auditionPhase: ScoreAuditionPhase = .idle
    @Published private(set) var auditionBeat = 0.0
    private(set) var auditionScoreID: String?
    private var auditionPlayer: ScoreAuditionPlayer?
    private var auditionPreparation: Task<Void, Never>?
    private var countdownEnd: TimeInterval?
    private var loopRestartAt: TimeInterval?
    private var sessionSaved = false
    private var metronomeAnchor: TimeInterval?
    private var metronomeFollowsPractice = true
    private var metronomeBelongsToPractice = false
    private var reportDueAt: TimeInterval?
    private var sessionHasStarted = false
    private var lastCheckpointKey: String?
    private var lastCheckpointAttempt: TimeInterval = -.infinity
    private var finishedCheckpointSaved = false
    private var engineIsResumed = false
    private var engineIsLoop = false
    private var engineRangeEnd = 1
    private var practiceBeatOrigin: Double = 0
    private var stoppingTransport = false
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private let metronome: Metronome
    private let clock: () -> TimeInterval
    private let storage: LocalLibraryStore
    private let presentationStore: ScorePresentationStore
    private let progressStore: PracticeProgressStore
    private let metronomeSettingsStore: MetronomeSettingsStore
    let catalog: LibraryCatalogController
    let documentLibrary: ImportedDocumentLibrary
    private var transitionID = 0

    init(storage: LocalLibraryStore = LocalLibraryStore(),
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         automaticTimer: Bool = true, deviceAccessEnabled: Bool = true) {
        self.storage = storage
        self.presentationStore = ScorePresentationStore(libraryURL: storage.url)
        self.progressStore = PracticeProgressStore(libraryURL: storage.url)
        self.metronomeSettingsStore = MetronomeSettingsStore(libraryURL: storage.url)
        self.catalog = LibraryCatalogController(libraryURL: storage.url)
        self.documentLibrary = ImportedDocumentLibrary(libraryURL: storage.url)
        self.clock = clock
        self.metronome = Metronome(deviceAccessEnabled: deviceAccessEnabled, clock: clock)
        let globalSettings = metronomeSettingsStore.load()
        metronomeSettings = globalSettings.settings
        let library = storage.load()
        let all = DemoScores.all + BundledCollections.scores + BundledPracticeLibrary.scores + library.scores
        scores = all
        let initial = all.first(where: { $0.id == library.lastScoreID }) ?? all[0]
        selectedScoreID = initial.id; tempo = globalSettings.settings.quarterBPM
        loopEnd = max(1, initial.measures.count)
        engine = PracticeEngine(score: initial, tempoBPM: globalSettings.settings.quarterBPM)
        engineRangeEnd = initial.measures.count
        history = library.history
        midi = MIDIService(deviceAccessEnabled: deviceAccessEnabled)
        microphone = MicrophoneService(deviceAccessEnabled: deviceAccessEnabled)
        polyphonicMicrophone = PolyphonicMicrophoneService(deviceAccessEnabled: deviceAccessEnabled)
        if midi.connected { inputMode = .midi }
        let presentation = presentationStore.load()
        favoriteScoreIDs = presentation.snapshot.favoriteScoreIDs
        scoreCoverData = presentation.snapshot.scoreCoverData
        let progress = progressStore.load()
        checkpoints = progress.checkpoints
        let loadErrors = [library.error, presentation.error, progress.error, globalSettings.error,
                          BundledPracticeLibrary.beyer.error, catalog.errorMessage, documentLibrary.errorMessage].compactMap { $0 }
        if !loadErrors.isEmpty { errorMessage = loadErrors.joined(separator: "\n") }
        catalog.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        documentLibrary.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
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
            guard let self, !active, self.inputMode == .microphonePolyphonic,
                  !self.isStartingInput, self.isPlaying else { return }
            self.stopTransport()
        }.store(in: &cancellables)
        microphone.$isActive.dropFirst().sink { [weak self] active in
            guard let self, !active, self.inputMode == .microphone,
                  !self.isStartingInput, self.isPlaying else { return }
            self.stopTransport()
        }.store(in: &cancellables)
        midi.$connected.dropFirst().sink { [weak self] connected in
            guard let self, !connected, self.inputMode == .midi else { return }
            self.stopTransport()
        }.store(in: &cancellables)
        #if os(iOS)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.stopTransport(stopIndependentMetronome: true) }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] notification in
                guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                self?.stopTransport(stopIndependentMetronome: true)
            }.store(in: &cancellables)
        #endif
        do { try metronome.prepare(settings: metronomeSettings) }
        catch { errorMessage = "节拍器声音准备失败：\(error.localizedDescription)" }
        if automaticTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
    }

    deinit { timer?.invalidate() }

    var selectedScore: PianoScore { scores.first(where: { $0.id == selectedScoreID }) ?? scores[0] }
    var isPlaying: Bool { engine.isRunning || isStartingInput || countdownEnd != nil || loopRestartAt != nil || reportDueAt != nil }
    var metronomeSoundAvailable: Bool { !isStartingInput && !microphone.isActive && !polyphonicMicrophone.isActive }
    var metronomeEnabled: Bool {
        get { metronomeSettings.soundEnabled }
        set {
            var settings = metronomeSettings
            settings.soundEnabled = newValue
            _ = updateMetronomeSettings(settings)
        }
    }
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
        stopTransport()
        selectedScoreID = id; tempo = metronomeSettings.quarterBPM
        practiceStartMeasure = 1; loopEnabled = false
        loopStart = 1; loopEnd = max(1, selectedScore.measures.count)
        if hand == .left && !selectedScore.notes.contains(where: { $0.staff == 2 }) { hand = .both }
        reconfigure()
        if persist { saveLibrary() }
    }

    func reconfigure() {
        stopTransport()
        tempo = metronomeSettings.quarterBPM
        let total = max(1, selectedScore.measures.count)
        loopStart = min(total, max(1, loopStart)); loopEnd = min(total, max(loopStart, loopEnd))
        practiceStartMeasure = PracticeTiming.safeStartMeasure(score: selectedScore, hand: hand,
            requestedMeasure: min(total, max(1, practiceStartMeasure))) ?? 1
        if inputMode.isMicrophone { mode = .wait }
        engine = PracticeEngine(score: selectedScore, mode: mode, hand: hand, tempoBPM: tempo,
                                measureRange: loopEnabled ? loopStart...loopEnd : practiceStartMeasure...total,
                                inputLagTolerance: inputMode == .microphonePolyphonic ? 3 : 0.25,
                                evaluatesNoteDuration: !inputMode.isMicrophone)
        engineIsResumed = !loopEnabled && practiceStartMeasure > 1
        engineIsLoop = loopEnabled
        engineRangeEnd = loopEnabled ? loopEnd : total
        practiceBeatOrigin = engine.currentBeat
        sustainedPitches = []; sustainGuidance = []
        sessionSaved = false; sessionHasStarted = false
        latestReport = nil; showingReport = false; lastCheckpointKey = nil
        finishedCheckpointSaved = false; lastCheckpointAttempt = -.infinity
    }

    func togglePlayback() {
        if isPlaying { stopTransport(); return }
        stopAudition()
        if loopEnabled, let issue = PracticeTiming.loopStartIssue(score: selectedScore, hand: hand, startMeasure: loopStart) {
            errorMessage = issue; return
        }
        if engine.isFinished {
            if !loopEnabled { practiceStartMeasure = 1 }
            reconfigure()
        }
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
            // Release a standalone playback session before opening recording.
            metronome.stop()
            Task { [weak self] in
                guard let self, self.transitionID == token,
                      self.isStartingInput, self.inputMode == startingMode else { return }
                if startingMode == .microphonePolyphonic { await self.polyphonicMicrophone.start() }
                else { await self.microphone.start() }
                guard self.transitionID == token else { return }
                self.isStartingInput = false
                guard self.inputMode == startingMode else { return }
                guard startingMode == .microphonePolyphonic ? self.polyphonicMicrophone.isActive : self.microphone.isActive else {
                    self.syncMetronomeAudio()
                    return
                }
                let now = self.clock()
                self.engine.start(at: now); self.sessionHasStarted = true
                self.startPracticeMetronome(at: now)
                self.saveCheckpoint()
            }
        } else if mode == .rhythm {
            let pulses = metronomeSettings.beatsPerMeasure
            countdownEnd = clock() + metronomeSettings.measureSeconds
            countdown = pulses
            startPracticeMetronome(at: clock())
        } else {
            engine.start(at: clock())
            sessionHasStarted = true
            startPracticeMetronome(at: clock())
            saveCheckpoint()
        }
    }

    func restart() {
        stopTransport()
        practiceStartMeasure = 1
        reconfigure()
    }
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
        stopTransport(stopIndependentMetronome: true)
        inputMode = newMode
        if newMode.isMicrophone { mode = .wait }
        reconfigure()
    }

    func importScore(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try StructuredScoreImport.xmlData(from: url)
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

    func pausePractice() { stopTransport() }
    func suspendForBackground() { stopTransport(stopIndependentMetronome: true) }

    func toggleAudition(score: PianoScore) {
        if auditionScoreID == score.id {
            switch auditionPhase {
            case .playing:
                guard let auditionPlayer else { stopAudition(); return }
                auditionBeat = min(auditionPlayer.currentBeat, auditionPlayer.plan.durationBeats)
                auditionPlayer.stop()
                auditionPhase = .paused
                return
            case .paused:
                guard let auditionPlayer else { stopAudition(); return }
                do {
                    try auditionPlayer.play(from: auditionBeat)
                    auditionPhase = .playing
                } catch { reportAuditionFailure(error) }
                return
            case .preparing:
                return
            case .idle:
                break
            }
        }
        stopTransport(stopIndependentMetronome: true)
        auditionScoreID = score.id
        auditionPhase = .preparing
        auditionPreparation = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            defer { self.auditionPreparation = nil }
            do {
                let plan = try ScorePlaybackPlan(score: score)
                guard let bank = ScoreAuditionPlayer.soundBankURL else {
                    throw LibraryError.message("钢琴音色资源缺失，请重新安装琴序。")
                }
                let player = try ScoreAuditionPlayer(plan: plan, bankURL: bank)
                try player.play(from: 0)
                self.auditionPlayer = player
                self.auditionPhase = .playing
            } catch { self.reportAuditionFailure(error) }
        }
    }

    func stopAudition() {
        guard auditionPhase != .idle else { return }
        auditionPreparation?.cancel()
        auditionPreparation = nil
        auditionPlayer?.stop()
        auditionPlayer = nil
        auditionScoreID = nil
        auditionBeat = 0
        auditionPhase = .idle
    }

    private func reportAuditionFailure(_ error: Error) {
        stopAudition()
        errorMessage = "无法试听曲谱。\(error.localizedDescription)"
    }

    private func stopTransport(stopIndependentMetronome: Bool = false) {
        guard !stoppingTransport else { return }
        stoppingTransport = true
        defer { stoppingTransport = false }
        stopAudition()
        transitionID += 1
        countdownEnd = nil; countdown = nil; loopRestartAt = nil; isStartingInput = false; reportDueAt = nil
        let now = clock()
        engine.pause(at: now)
        engine.receive(.allNotesOff, at: now)
        sustainedPitches = []; sustainGuidance = []
        // Pausing on the final beat may complete the engine. Save it, but never auto-restart.
        finishIfNeeded(at: now, allowLoopRestart: false)
        saveCheckpoint()
        microphone.stop()
        polyphonicMicrophone.stop()
        if stopIndependentMetronome || metronomeBelongsToPractice { stopMetronome() }
    }

    private func receive(_ event: NoteInput, at time: TimeInterval) {
        guard countdownEnd == nil, auditionPhase == .idle else { return }
        if loopRestartAt != nil, case .on(let pitch, let velocity) = event {
            // Loop rests reject fresh attacks, but a velocity-zero release still
            // needs to clear the physical/acoustic state shown by the keyboard.
            if velocity <= 0 { engine.receive(.off(pitch: pitch), at: time) }
            return
        }
        engine.receive(event, at: time)
        if engine.isRunning || engine.correctCount + engine.wrongCount + engine.missedCount > 0 { sessionHasStarted = true }
        updateSustainGuidance(at: clock())
        finishIfNeeded(at: clock())
        saveCheckpoint()
    }

    func tick() {
        let now = clock()
        if auditionPhase == .playing, let auditionPlayer {
            if !auditionPlayer.isOutputRunning || auditionPlayer.reachedEnd { stopAudition() }
            else { auditionBeat = min(auditionPlayer.currentBeat, auditionPlayer.plan.durationBeats) }
        }
        updateSustainGuidance(at: now)
        if let end = countdownEnd {
            if now >= end {
                countdownEnd = nil; countdown = nil
                engine.start(at: end)
                sessionHasStarted = true
                // A resumed rhythm can start between beats. Keep clicks aligned
                // to its frozen musical position instead of inventing a downbeat.
                if metronomeRunning {
                    startMetronome(at: end - (engine.currentBeat - practiceBeatOrigin) * 60 / tempo,
                                   belongsToPractice: true)
                }
                saveCheckpoint()
            } else {
                let secondsPerPulse = metronomeSettings.beatSeconds
                let count = max(1, Int(ceil((end - now) / secondsPerPulse)))
                if countdown != count { countdown = count }
                updateMetronome(at: now)
                return
            }
        }
        if let restartTime = loopRestartAt {
            guard now >= restartTime else { updateMetronome(at: now); return }
            loopRestartAt = nil
            engine.reset(); sessionSaved = false
            finishedCheckpointSaved = false
            engine.start(at: now)
            if metronomeRunning { startMetronome(at: now, belongsToPractice: true) }
            updateSustainGuidance(at: now)
        }
        if engine.isRunning {
            engine.tick(at: now)
        }
        updateMetronome(at: now)
        finishIfNeeded(at: now)
        saveCheckpoint()
        if let due = reportDueAt, now >= due {
            reportDueAt = nil
            if metronomeBelongsToPractice { stopMetronome() }
            microphone.stop(); polyphonicMicrophone.stop()
            latestReport = engine.report(inputSource: inputMode.title, isPartial: isResumedSession)
            showingReport = true
        }
    }

    private func updateSustainGuidance(at time: TimeInterval) {
        let next = engine.sustainedPitches(at: time)
        if sustainedPitches != next { sustainedPitches = next }
        let guidance = engine.sustainGuidance(at: time)
        if sustainGuidance != guidance { sustainGuidance = guidance }
    }

    private func finishIfNeeded(at now: TimeInterval, allowLoopRestart: Bool = true) {
        guard engine.isFinished, !sessionSaved, engine.correctCount + engine.wrongCount + engine.missedCount > 0 else { return }
        sessionSaved = true
        latestReport = engine.report(inputSource: inputMode.title, isPartial: isResumedSession)
        history.insert(engine.summary(inputSource: inputMode.title, isPartial: isResumedSession), at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
        saveLibrary()
        if loopEnabled && allowLoopRestart {
            loopRestartAt = max(now + 1, engine.sustainGuidanceEndTime ?? now)
        }
        else if allowLoopRestart {
            // The final attack is accepted before its written hold has elapsed.
            // Keep its countdown visible instead of covering it with the report.
            reportDueAt = max(now, engine.sustainGuidanceEndTime ?? now)
        }
    }

    private var isResumedSession: Bool { engineIsResumed }

    func showCurrentReport() {
        stopTransport()
        latestReport = engine.report(inputSource: inputMode.title, isPartial: isResumedSession)
        showingReport = true
    }

    func practiceMeasure(_ measure: Int) {
        guard let safe = PracticeTiming.safeStartMeasure(score: selectedScore, hand: hand, requestedMeasure: measure) else { return }
        stopTransport()
        practiceStartMeasure = 1
        loopEnabled = true; loopStart = safe; loopEnd = max(safe, min(selectedScore.measures.count, measure))
        reconfigure()
    }

    func progress(for scoreID: String) -> PracticeCheckpoint? {
        guard let checkpoint = checkpoints[scoreID], let score = scores.first(where: { $0.id == scoreID }),
              checkpoint.matches(score) else { return nil }
        return checkpoint
    }

    func resume(scoreID: String) {
        guard let checkpoint = progress(for: scoreID), let score = scores.first(where: { $0.id == scoreID }),
              let measure = checkpoint.resumeMeasure(in: score) else { return }
        stopTransport()
        selectedScoreID = scoreID; practiceStartMeasure = measure
        hand = checkpoint.hand; mode = inputMode.isMicrophone ? .wait : checkpoint.mode
        // Resume restores location/hand/mode; the global speed stays authoritative.
        tempo = metronomeSettings.quarterBPM; loopEnabled = false
        loopStart = 1; loopEnd = score.measures.count
        reconfigure(); saveLibrary()
    }

    private func saveCheckpoint() {
        guard sessionHasStarted, !(engine.isFinished && finishedCheckpointSaved) else { return }
        // Use the old engine's configuration while selection controls are changing.
        let score = engine.score
        let measure = engine.mode == .wait ? engine.expectedNotes.first?.measure ?? engineRangeEnd
            : score.measures.last(where: { $0.startBeat <= engine.currentBeat + 0.000001 })?.number ?? 1
        let reachedEnd = engine.isFinished && !engineIsLoop && engineRangeEnd == score.measures.count
        let key = "\(score.id)|\(measure)|\(reachedEnd)|\(engine.hand.rawValue)|\(engine.mode.rawValue)|\(engine.tempoBPM)"
        guard key != lastCheckpointKey, clock() - lastCheckpointAttempt >= 1 || stoppingTransport,
              let checkpoint = PracticeCheckpoint.make(score: score, measure: measure, hand: engine.hand,
                  mode: engine.mode, tempoBPM: engine.tempoBPM, isCompleted: reachedEnd) else { return }
        var next = checkpoints; next[score.id] = checkpoint
        do {
            try progressStore.save(next)
            checkpoints = next; lastCheckpointKey = key
            finishedCheckpointSaved = engine.isFinished
        } catch {
            lastCheckpointAttempt = clock()
            errorMessage = "保存练习位置失败：\(error.localizedDescription)"
        }
    }

    func toggleMetronome() {
        stopAudition()
        if metronomeRunning {
            metronomeFollowsPractice = false; stopMetronome()
        } else {
            metronomeFollowsPractice = true
            let now = clock()
            if let end = countdownEnd {
                // Re-enabling clicks during preparation must retain the count-in phase.
                startMetronome(at: end - metronomeSettings.measureSeconds, belongsToPractice: true)
            } else if engine.isRunning && mode == .rhythm {
                startMetronome(at: now - (engine.currentBeat - practiceBeatOrigin) * 60 / tempo, belongsToPractice: true)
            } else { startMetronome(at: now, belongsToPractice: isPlaying) }
        }
    }

    private func startPracticeMetronome(at now: TimeInterval) {
        guard metronomeFollowsPractice else { return }
        startMetronome(at: now, belongsToPractice: true)
    }

    private func startMetronome(at anchor: TimeInterval, belongsToPractice: Bool) {
        metronomeRunning = true; metronomeAnchor = anchor
        metronomeBelongsToPractice = belongsToPractice
        syncMetronomeAudio()
        updateMetronome(at: clock())
    }

    private func stopMetronome() {
        metronome.stop(); metronomeRunning = false; metronomeBeat = nil
        metronomeSubdivision = nil; metronomeAnchor = nil; metronomeBelongsToPractice = false
    }

    private func updateMetronome(at now: TimeInterval) {
        guard metronomeRunning, let anchor = metronomeAnchor,
              let position = metronomeSettings.position(atElapsedSeconds: now - anchor) else { return }
        if metronomeBeat != position.beat { metronomeBeat = position.beat }
        if metronomeSubdivision != position.subdivision { metronomeSubdivision = position.subdivision }
    }

    private func syncMetronomeAudio() {
        guard metronomeRunning, metronomeEnabled, metronomeSoundAvailable, let anchor = metronomeAnchor else {
            metronome.stop(); return
        }
        do { try metronome.start(settings: metronomeSettings, anchor: anchor) }
        catch { errorMessage = "节拍器声音不可用：\(error.localizedDescription)" }
    }

    func openMetronomeSettings() {
        pausePractice()
        showingMetronomeSettings = true
    }

    @discardableResult
    func updateMetronomeSettings(_ settings: GlobalMetronomeSettings) -> Bool {
        if let issue = settings.validationMessage { errorMessage = issue; return false }
        var withoutSoundChange = settings
        withoutSoundChange.soundEnabled = metronomeSettings.soundEnabled
        let timingChanged = withoutSoundChange != metronomeSettings
        do {
            try metronomeSettingsStore.save(settings)
        } catch {
            errorMessage = "保存全局节拍器失败：\(error.localizedDescription)"; return false
        }
        if timingChanged {
            let wasStandalone = metronomeRunning && !metronomeBelongsToPractice
            stopTransport()
            metronomeSettings = settings
            reconfigure()
            do { try metronome.prepare(settings: settings) }
            catch { errorMessage = "节拍器声音准备失败：\(error.localizedDescription)" }
            if wasStandalone { startMetronome(at: clock(), belongsToPractice: false) }
        } else {
            metronomeSettings = settings
            syncMetronomeAudio()
        }
        return true
    }

    private func validatePolyphonicRange() -> Bool {
        let notes = engine.score.notes.filter { engine.verdicts[$0.id] != nil }
        guard notes.allSatisfy({ (21...108).contains($0.midi) }) else {
            errorMessage = "双手识音模型覆盖钢琴 A0–C8，请选择此音域内的曲谱。"; return false
        }
        return true
    }

    private func validateMicrophoneSubset() -> Bool {
        let notes = engine.score.notes.filter { engine.verdicts[$0.id] != nil }.sorted { $0.startBeat < $1.startBeat }
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
