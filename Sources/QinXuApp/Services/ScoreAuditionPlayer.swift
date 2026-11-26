import AVFoundation
import AudioToolbox
import QinXuCore

enum ScoreAuditionPhase {
    case idle, preparing, playing, paused
}

@MainActor
final class ScoreAuditionPlayer {
    let plan: ScorePlaybackPlan
    private let engine = AVAudioEngine()
    private let upper = AVAudioUnitSampler()
    private let lower = AVAudioUnitSampler()
    private var sequencer: AVAudioSequencer?
    private var originBeat = 0.0
    #if os(iOS)
    private var ownsSession = false
    #endif

    static var soundBankURL: URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.main.resourceURL
            .flatMap { Bundle(url: $0.appendingPathComponent("QinXu_QinXuApp.bundle")) } ?? Bundle.module
        return bundle.url(forResource: "Piano", withExtension: "sf2", subdirectory: "Resources")
        #else
        return Bundle.main.url(forResource: "Piano", withExtension: "sf2")
        #endif
    }

    init(plan: ScorePlaybackPlan, bankURL: URL) throws {
        self.plan = plan
        for sampler in [upper, lower] {
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            try Self.loadPiano(sampler, from: bankURL)
        }
        // Allow headroom when both hands strike several notes at once.
        engine.mainMixerNode.outputVolume = 0.55
    }

    static func loadPiano(_ sampler: AVAudioUnitSampler, from url: URL) throws {
        try sampler.loadSoundBankInstrument(at: url, program: 0,
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
    }

    var isOutputRunning: Bool { engine.isRunning && sequencer?.isPlaying == true }
    var currentBeat: Double { originBeat + (sequencer?.currentPositionInBeats ?? 0) }
    var reachedEnd: Bool { currentBeat >= plan.durationBeats + 0.24 / plan.secondsPerBeat }

    func play(from beat: Double) throws {
        stop()
        originBeat = min(max(0, beat), plan.durationBeats)
        let next = AVAudioSequencer(audioEngine: engine)
        next.tempoTrack.addEvent(AVExtendedTempoEvent(tempo: plan.tempoBPM), at: 0)
        let upperTrack = next.createAndAppendTrack()
        let lowerTrack = next.createAndAppendTrack()
        upperTrack.destinationAudioUnit = upper
        lowerTrack.destinationAudioUnit = lower
        for note in plan.notes where note.endBeat > originBeat {
            // On resume, recreate a note that spans the pause point for its
            // remaining time. Sequencer seeking alone may skip its earlier onset.
            let start = max(note.startBeat, originBeat)
            let track = note.staff == 2 ? lowerTrack : upperTrack
            let event = AVMIDINoteEvent(channel: 0, key: UInt32(note.midi),
                velocity: note.staff == 2 ? 68 : 76, duration: note.endBeat - start)
            track.addEvent(event, at: start - originBeat)
        }
        let length = plan.durationBeats - originBeat + 0.24 / plan.secondsPerBeat
        upperTrack.lengthInBeats = length
        lowerTrack.lengthInBeats = length
        sequencer = next
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try session.setActive(true)
            ownsSession = true
            #endif
            try engine.start()
            next.prepareToPlay()
            try next.start()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        sequencer?.stop()
        sequencer = nil
        if engine.isRunning { engine.stop() }
        engine.reset()
        #if os(iOS)
        if ownsSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsSession = false
        }
        #endif
    }
}
