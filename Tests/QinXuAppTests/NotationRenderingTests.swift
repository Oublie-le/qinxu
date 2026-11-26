import Foundation
import SwiftUI
import Testing
import QinXuCore
@testable import QinXuApp

#if os(macOS)
extension PracticeRenderingTests {
    @Test(arguments: [667, 1194])
    func notationGlyphsAndRhythmsRenderAtPhoneAndTabletWidths(width: Int) throws {
        #expect(NotationFont.isAvailable)
        let beyer = try #require(BundledPracticeLibrary.scores.first(where: { $0.id == "beyer-op101-002-theme" }))
        for (name, score) in [("rhythm", DemoScores.all[2]), ("glyphs", notationFixture()),
                              ("beyer-double-treble", beyer), ("clef-change", clefChangeFixture())] {
            let scoreView = PracticeScoreView(score: score, hand: .both, currentBeat: 0,
                                              expectedNotes: Array(score.notes.filter { $0.startBeat == 0 }),
                                              verdicts: [:], active: true, compact: width == 667)
            let height = Int(ceil(scoreView.preferredHeight))
            let view = scoreView.frame(width: CGFloat(width), height: CGFloat(height))
                .background(QinXuTheme.paper)
            try render(view, name: "notation-\(name)-\(width)", width: width, height: height)
        }
    }

    private func clefChangeFixture() -> PianoScore {
        PianoScore(id: "clef-change-fixture", title: "双高音与小节换谱号", notes: [
            .init(id: "upper-1", midi: 72, startBeat: 0, durationBeats: 4, staff: 1, measure: 1, step: "C", octave: 5),
            .init(id: "lower-1", midi: 60, startBeat: 0, durationBeats: 4, staff: 2, measure: 1, step: "C", octave: 4),
            .init(id: "upper-2", midi: 74, startBeat: 4, durationBeats: 4, staff: 1, measure: 2, step: "D", octave: 5),
            .init(id: "lower-2", midi: 60, startBeat: 4, durationBeats: 4, staff: 2, measure: 2, step: "C", octave: 4)
        ], measures: [.init(number: 1, startBeat: 0, durationBeats: 4, lowerClef: .treble),
                      .init(number: 2, startBeat: 4, durationBeats: 4)])
    }

    private func notationFixture() -> PianoScore {
        func note(_ id: String, _ midi: Int, _ beat: Double, _ duration: Double,
                  _ staff: Int, _ step: String, _ alter: Int, _ octave: Int) -> ScoreNote {
            ScoreNote(id: id, midi: midi, startBeat: beat, durationBeats: duration,
                      staff: staff, measure: beat < 4 ? 1 : 2, step: step, alter: alter, octave: octave)
        }
        return PianoScore(id: "notation-glyph-fixture", title: "字形与排布检查", notes: [
            // Sharp followed by its cancellation; dotted up-flag; down 8th/16th flags.
            note("sharp", 61, 0, 0.5, 1, "C", 1, 4),
            note("natural", 60, 0.5, 0.75, 1, "C", 0, 4),
            note("flat", 75, 1.5, 0.5, 1, "E", -1, 5),
            note("flat-cancel", 76, 2.5, 0.375, 1, "E", 0, 5),
            note("double-sharp", 69, 3.5, 0.25, 1, "G", 2, 4),
            note("bass-half", 41, 0, 2, 2, "F", 0, 2),
            note("double-flat", 45, 2, 0.5, 2, "B", -2, 2),
            note("double-flat-cancel", 47, 3, 0.5, 2, "B", 0, 2),
            // Adjacent seconds must alternate head sides and retain separate dots.
            note("second-c", 60, 4, 0.75, 1, "C", 0, 4),
            note("second-d", 62, 4, 0.75, 1, "D", 0, 4),
            note("second-e", 64, 4, 0.75, 1, "E", 0, 4),
            note("high-f", 77, 6, 0.5, 1, "F", 0, 5),
            note("high-g", 79, 6, 0.5, 1, "G", 0, 5),
            note("high-a", 81, 6, 0.5, 1, "A", 0, 5),
            note("short-down", 76, 7, 0.25, 1, "E", 0, 5),
            note("bass-second-c", 48, 4, 2, 2, "C", 0, 3),
            note("bass-second-d", 50, 4, 2, 2, "D", 0, 3),
            note("bass-second-e", 52, 4, 2, 2, "E", 0, 3),
            note("bass-low", 43, 6, 2, 2, "G", 0, 2)
        ], measures: [.init(number: 1, startBeat: 0, durationBeats: 4),
                      .init(number: 2, startBeat: 4, durationBeats: 4)])
    }
}
#endif
