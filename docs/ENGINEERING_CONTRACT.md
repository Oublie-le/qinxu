# Parallel implementation contract

Shared types live in Sources/PianoCore/Models.swift. Avoid editing that file without coordinating.

## Parser / fixtures
- `public struct MusicXMLParser { public init(); public func parse(data: Data) throws -> PianoScore }`.
- `public enum DemoScores { public static var all: [PianoScore] { get } }`.
- MusicXML support is a declared subset. Reject unsupported constructs which would change evaluated timing/pitch; expose honest warnings for visual-only simplification. No silent repeat/grace/transposition loss. MusicXML compressed zip is explicitly unsupported for now.

## Practice engine
`public struct PracticeEngine` exposes:
- `init(score: PianoScore, mode: PracticeMode = .wait, hand: PracticeHand = .both, tempoBPM: Double? = nil, measureRange: ClosedRange<Int>? = nil)`
- read-only `score`, `mode`, `hand`, `tempoBPM`, `currentBeat: Double`, `expectedNotes: [ScoreNote]`, `verdicts: [String: NoteVerdict]`, `heldPitches: Set<Int>`, `isFinished: Bool`, `isRunning: Bool`, `correctCount: Int`, `wrongCount: Int`, `missedCount: Int`, `feedback: String`, `durationFeedback: String?`
- `mutating func start(at time: TimeInterval)` starts/resumes with a monotonic timestamp (seconds).
- `mutating func pause(at time: TimeInterval)` / `mutating func tick(at time: TimeInterval)`.
- `mutating func receive(_ event: NoteInput, at time: TimeInterval)`.
- `mutating func reset()`.
- `func summary(at date: Date = Date()) -> PracticeSummary`.
- Mode `.wait` accepts matching chord notes within a reasonable held/onset window and advances only after the chord is complete. `.rhythm` uses an absolute local timeline and can recover after missed notes. Tempo is quarter notes per minute. Rests exist as gaps. Single wrong presses must never shift all subsequent notes. Repeated notes need new onsets. Expected notes use staff filtering. Pause must freeze playback. Selected measure range uses original score beats.

## App services / view model (root owns)
`@MainActor final class PracticeViewModel: ObservableObject` provides:
- `@Published scores: [PianoScore]`, `selectedScoreID: String`, `mode: PracticeMode`, `hand: PracticeHand`, `tempo: Double`, `loopEnabled: Bool`, `loopStart: Int`, `loopEnd: Int`, `history: [PracticeSummary]`, `engine: PracticeEngine`, `midi: MIDIService`, `errorMessage: String?`, `isImporting: Bool`, `inputMode: InputMode`, `microphone: MicrophoneService`.
- `var selectedScore: PianoScore`, `var isPlaying: Bool`, `var midiStatus: String`, `var inputStatus: String`.
- `selectScore(_ id: String)`, `reconfigure()`, `togglePlayback()`, `restart()`, `press(_ pitch: Int)`, `release(_ pitch: Int)`, `importScore(from url: URL)`, `refreshMIDI()`, `setInputMode(_ mode: InputMode)`.
- InputMode enum `.midi`, `.touch`, `.microphone` with `title`. Root may initially implement `.microphone` as experimental single-note only but never fake detection.
- `MIDIService` observable exposes `@Published sources: [MIDISource]`, `selectedSourceID: Int32?`, `status: String`, `connected: Bool`, `func selectSource(_ id: Int32?)`, `func refresh()`; MIDISource `id: Int32`, `name: String`.
- `MicrophoneService` observable exposes `@Published status: String`, `isActive: Bool`, `detectedPitch: Int?`, `level: Double`.
- Root app entry creates the model and displays `ContentView(model: model)`.

## UI (UI agent owns Views/ only)
Build reusable SwiftUI views compiling on iOS 17 and macOS 14. Chinese interface, iPad-first with narrow-width fallback. Elegant cream/navy/teal palette, proper grand staff for a declared simplified practice view, left/right keyboard choices, MusicXML import, session controls, clear connection status, visible error alerts, history sheet. All buttons connected to real model methods. Use no external fonts/assets/dependencies. Avoid fake charts, invented accuracy stats, or pretending microphone production readiness. Staff must render actual score notes at correct diatonic positions, selected/current verdict colors, ledger lines; explain display simplification. Use model fields above. Source views can use `#if canImport(PianoCore) import PianoCore #endif`. Never overwrite services or model.
