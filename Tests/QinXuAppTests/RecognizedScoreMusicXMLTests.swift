import Foundation
import Testing
import SheetMusicCore
import QinXuCore
@testable import QinXuApp

@Suite struct RecognizedScoreMusicXMLTests {
    private func note(_ pitch: Int, _ tpc: Int = 14, duration: NoteDuration = .quarter) -> VoiceElement {
        .chord(Chord(duration: duration, notes: [Note(pitch: pitch, tpc: tpc)]))
    }

    private func score(_ upper: [Measure], lower: [Measure]? = nil,
                       upperClef: String = "G", lowerClef: String = "F",
                       system: [SystemMeasure] = []) -> SheetMusicCore.Score {
        var staves = [Staff(defaultClefType: upperClef, measures: upper)]
        if let lower { staves.append(Staff(defaultClefType: lowerClef, measures: lower)) }
        return SheetMusicCore.Score(division: 480,
            parts: [Part(id: "piano", instrument: Instrument(id: "piano"), staves: IdentifiedArray(staves))],
            systemMeasures: IdentifiedArray(system))
    }

    private func parsed(_ input: SheetMusicCore.Score, title: String = "识谱测试") throws -> PianoScore {
        try QinXuCore.MusicXMLParser().parse(data: RecognizedScoreMusicXML.encode(input, title: title))
    }

    private func rejected(_ input: SheetMusicCore.Score) {
        do { _ = try parsed(input); Issue.record("Expected unsupported recognition to be rejected") }
        catch { }
    }

    @Test func bothTrebleAndAccidentalSpellingSurviveConversion() throws {
        let upper = Measure(voices: [Voice(elements: [note(72, duration: .whole)])])
        let lower = Measure(voices: [Voice(elements: [note(66, 20, duration: .whole)])])
        let result = try parsed(score([upper], lower: [lower], lowerClef: "G"), title: "A & B <练习>")
        #expect(result.title == "A & B <练习>")
        #expect(result.measures[0].upperClef == .treble && result.measures[0].lowerClef == .treble)
        let left = try #require(result.notes.first { $0.staff == 2 })
        #expect(left.midi == 66 && left.step == "F" && left.alter == 1 && left.octave == 4)
    }

    @Test func parallelVoicesAndRestTimeAreNotFlattened() throws {
        let first = Voice(elements: [.rest(duration: .half), note(76, 18, duration: .half)])
        let second = Voice(elements: [note(72, duration: .whole)])
        let lower = Measure(voices: [Voice(elements: [note(48, duration: .whole)])])
        let result = try parsed(score([Measure(voices: [first, second])], lower: [lower]))
        #expect(result.notes.count == 3)
        #expect(result.notes.first { $0.midi == 76 }?.startBeat == 2)
        #expect(result.notes.first { $0.midi == 72 }?.startBeat == 0)
        #expect(result.notes.first { $0.midi == 48 }?.startBeat == 0)
        #expect(result.durationBeats == 4)
    }

    @Test func dottedAndTupletDurationsAreNotScaledTwice() throws {
        let dotted = Measure(voices: [Voice(elements: [
            note(72, duration: .fraction(Fraction(numerator: 3, denominator: 8))),
            .rest(duration: .fraction(Fraction(numerator: 5, denominator: 8)))
        ])])
        let third = NoteDuration.fraction(Fraction(numerator: 1, denominator: 12))
        let triplets = Voice(elements: [note(72, duration: third), note(74, 16, duration: third),
            note(76, 18, duration: third), .rest(duration: .fraction(Fraction(numerator: 3, denominator: 4)))],
            tuplets: [Tuplet(normalNotes: 2, actualNotes: 3, startIndex: 0, endIndex: 2)])
        let result = try parsed(score([dotted, Measure(voices: [triplets])]))
        #expect(result.notes[0].durationBeats == 1.5)
        #expect(result.notes.count == 4)
        for (index, item) in result.notes.dropFirst().enumerated() {
            #expect(abs(item.durationBeats - 1.0 / 3) < 0.000_001)
            #expect(abs(item.startBeat - 4 - Double(index) / 3) < 0.000_001)
        }
        #expect(result.durationBeats == 8)
    }

    @Test func tiesStayOneAttackAndMismatchedTieIdentityIsRejected() throws {
        var beginning = Note(pitch: 72, tpc: 14); beginning.tieForward = 1
        var ending = Note(pitch: 72, tpc: 14); ending.tieBack = 1
        func measure(_ n: Note) -> Measure {
            Measure(voices: [Voice(elements: [.chord(Chord(duration: .whole, notes: [n]))])])
        }
        let result = try parsed(score([measure(beginning), measure(ending)]))
        #expect(result.notes.count == 1 && result.notes[0].durationBeats == 8)
        ending.tieBack = 2
        rejected(score([measure(beginning), measure(ending)]))
        rejected(score([measure(beginning)]))
    }

    @Test func pickupAndBoundaryClefChangePreserveMeasureTiming() throws {
        let pickup = Measure(voices: [Voice(elements: [
            .timeSignature(TimeSignature(numerator: 3, denominator: 4)), note(72)
        ])], actualLength: Fraction(numerator: 1, denominator: 4), irregular: true)
        let next = Measure(voices: [Voice(elements: [
            .clef(Clef(concertClefType: "F")), note(48, duration: .fraction(Fraction(numerator: 3, denominator: 4)))
        ])])
        let result = try parsed(score([pickup, next]))
        #expect(result.measures.map(\.durationBeats) == [1, 3])
        #expect(result.notes[1].startBeat == 1 && result.notes[1].midi == 48)
        #expect(result.measures[1].upperClef == .bass)
    }

    @Test func explicitCursorMovesAndTrailingSilenceKeepTheirPositions() throws {
        let measure = Measure(voices: [Voice(elements: [
            .locationShift(delta: Fraction(numerator: 1, denominator: 4)), note(72)
        ])])
        let result = try parsed(score([measure]))
        #expect(result.notes[0].startBeat == 1 && result.durationBeats == 4)
        rejected(score([Measure(voices: [Voice(elements: [
            .locationShift(delta: Fraction(numerator: -1, denominator: 4)), note(72)
        ])])]))
    }

    @Test func unsupportedStructuresAreRefusedInsteadOfDropped() throws {
        let plain = Measure(voices: [Voice(elements: [note(72, duration: .whole)])])
        var repeated = plain; repeated.endRepeatCount = 2
        rejected(score([repeated]))
        rejected(score([plain], lower: [plain, plain]))
        rejected(score([plain], upperClef: "G8vb"))
        var moved = Chord(duration: .whole, notes: [Note(pitch: 72, tpc: 14)]); moved.staffMove = 1
        rejected(score([Measure(voices: [Voice(elements: [.chord(moved)])])]))
        let twoParts = SheetMusicCore.Score(division: 480, parts: [
            Part(id: "first", instrument: Instrument(id: "piano"), staves: [Staff(measures: [plain])]),
            Part(id: "second", instrument: Instrument(id: "piano"), staves: [Staff(measures: [plain])])
        ])
        rejected(twoParts)
        // The MIDI pitch cannot be silently respelled when the recognized tonal pitch class contradicts it.
        rejected(score([Measure(voices: [Voice(elements: [note(61, 14, duration: .whole)])])]))
        rejected(score([Measure(voices: [Voice(elements: [note(72, duration: .fraction(Fraction(numerator: 5, denominator: 4)))])])]))
    }

    @Test func fixedTempoIsPreservedAndChangesAreRejected() throws {
        let measure = Measure(voices: [Voice(elements: [note(72, duration: .whole)])])
        let initial = SystemMeasure(elements: [.init(position: .start, element: .tempo(Tempo(beatsPerSecond: 1.5)))])
        let result = try parsed(score([measure], system: [initial]))
        #expect(result.tempoBPM == 90)
        let changed = SystemMeasure(elements: [.init(position: .start, element: .tempo(Tempo(beatsPerSecond: 2)))])
        rejected(score([measure, measure], system: [initial, changed]))
        let invalid = SystemMeasure(elements: [.init(position: .start, element: .tempo(Tempo(beatsPerSecond: .nan)))])
        rejected(score([measure], system: [invalid]))
    }
}
