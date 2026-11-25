import Foundation
import SwiftUI
import Testing
import QinXuCore
@testable import QinXuApp

#if os(macOS)
private final class SessionPreviewClock { var now: TimeInterval = 100 }

extension PracticeRenderingTests {
    @Test(arguments: [667, 1194])
    func globalMetronomeRendersFromLibraryAndPractice(width: Int) throws {
        let height = width == 667 ? 375 : 834
        let compact = width == 667
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = SessionPreviewClock()
        let model = PracticeViewModel(storage: LocalLibraryStore(url: directory.appendingPathComponent("library.json")),
                                      clock: { clock.now }, automaticTimer: false, deviceAccessEnabled: false)
        let settings = GlobalMetronomeSettings(beatsPerMeasure: 3, beatUnit: 4, tempoBPM: 90,
                                               tempoNote: .quarter, clickNote: .eighth)
        #expect(model.updateMetronomeSettings(settings))
        model.toggleMetronome()
        clock.now += settings.pulseSeconds + 0.01
        model.tick()
        #expect(model.metronomeSubdivision == 2)
        try render(GlobalMetronomeSettingsView(model: model)
            .frame(width: CGFloat(width), height: CGFloat(height)),
            name: "global-metronome-sheet-\(width)", width: width, height: height)
        try render(PracticeHomeView(model: model)
            .frame(width: CGFloat(width), height: CGFloat(height)),
            name: "global-metronome-home-\(width)", width: width, height: height)
        model.selectScore("demo-chords")
        #expect(model.metronomeRunning)
        let availableWidth = width - (compact ? 63 : 175)
        try render(PracticeSessionView(model: model, compact: compact, onExit: {}, onShowDevices: {})
            .frame(width: CGFloat(availableWidth), height: CGFloat(height)),
            name: "global-metronome-session-\(width)", width: availableWidth, height: height)
    }

    @Test(arguments: [667, 1194])
    func sustainImmersionAndReportRenderAtPhoneAndTabletSizes(width: Int) throws {
        let height = width == 667 ? 375 : 834
        let compact = width == 667
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = SessionPreviewClock()
        let model = PracticeViewModel(storage: LocalLibraryStore(url: directory.appendingPathComponent("library.json")),
                                      clock: { clock.now }, automaticTimer: false, deviceAccessEnabled: false)
        model.selectScore("demo-chords")
        model.togglePlayback()
        for pitch in [48, 52, 55, 60] { model.press(pitch) }
        clock.now += 0.6
        model.tick()
        #expect(model.sustainGuidance.count == 4)
        #expect(model.sustainGuidance.allSatisfy { $0.remainingFraction > 0 && $0.remainingFraction < 1 })
        for immersive in [false, true] {
            let availableWidth = immersive ? width : width - (compact ? 63 : 175)
            let session = PracticeSessionView(model: model, compact: compact, onExit: {}, onShowDevices: {},
                                              immersive: immersive, onToggleImmersion: {})
                .frame(width: CGFloat(availableWidth), height: CGFloat(height))
            try render(session, name: "practice-\(immersive ? "immersive" : "guidance")-\(width)",
                       width: availableWidth, height: height)
        }

        // Deliberately evaluated synthetic events produce real report fields;
        // this is a rendering fixture, not a recording or a hardware result.
        let piece = PianoScore(id: "report-render", title: "节奏练习 · 画面检查", tempoBPM: 60,
            beatsPerMeasure: 2, beatUnit: 4, notes: [
                .init(id: "c", midi: 60, startBeat: 0, durationBeats: 0.5, measure: 1),
                .init(id: "d", midi: 62, startBeat: 1, durationBeats: 0.5, measure: 1),
                .init(id: "e", midi: 64, startBeat: 2, durationBeats: 0.5, measure: 2),
                .init(id: "f", midi: 65, startBeat: 3, durationBeats: 0.5, measure: 2)
            ], measures: [.init(number: 1, startBeat: 0, durationBeats: 2),
                          .init(number: 2, startBeat: 2, durationBeats: 2)])
        var engine = PracticeEngine(score: piece, mode: .rhythm)
        engine.start(at: 10)
        engine.receive(.on(pitch: 60, velocity: 80), at: 10)
        engine.receive(.off(pitch: 60), at: 10.3)
        engine.receive(.on(pitch: 62, velocity: 80), at: 10.85)
        engine.receive(.off(pitch: 62), at: 11.1)
        engine.receive(.on(pitch: 67, velocity: 80), at: 11.5)
        engine.receive(.off(pitch: 67), at: 11.6)
        engine.receive(.on(pitch: 64, velocity: 80), at: 12.25)
        engine.receive(.off(pitch: 64), at: 12.5)
        engine.tick(at: 14)
        let report = engine.report(inputSource: "MIDI")
        #expect(report.isComplete && report.overallScore != nil)
        #expect(report.wrong == 1 && report.missed == 1)
        let view = PracticeReportView(report: report, scoreTitle: piece.title, compact: compact,
                                      onClose: {}, onRetry: {}, onMeasure: { _ in })
            .frame(width: CGFloat(width), height: CGFloat(height))
        try render(view, name: "practice-report-\(width)", width: width, height: height)
    }
}
#endif
