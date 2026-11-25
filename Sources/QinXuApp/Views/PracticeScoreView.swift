import SwiftUI
import QinXuCore

struct PracticeScoreView: View {
    let score: PianoScore
    let hand: PracticeHand
    let currentBeat: Double
    let expectedNotes: [ScoreNote]
    let verdicts: [String: NoteVerdict]
    let active: Bool
    @State private var cachedLayout: ScoreDrawingLayout? = nil

    private var currentMeasure: Int {
        expectedNotes.first?.measure ??
            score.measures.last(where: { $0.startBeat <= currentBeat })?.number ?? 1
    }

    var body: some View {
        let layout = cachedLayout.flatMap { $0.scoreID == score.id ? $0 : nil } ?? ScoreDrawingLayout(score)
        GeometryReader { geometry in
            let gutterWidth = min(68, geometry.size.width * 0.22)
            let available = max(1, geometry.size.width - gutterWidth)
            let visibleMeasures = max(1, min(3, score.measures.count, Int(available / 230)))
            let measureWidth = max(134, available / CGFloat(visibleMeasures))
            HStack(spacing: 0) {
                Canvas { context, size in
                    drawClefs(context, width: size.width, layout: layout)
                }
                .frame(width: gutterWidth)
                .accessibilityHidden(true)

                measureStrip(width: measureWidth, layout: layout)
            }
        }
        .frame(height: layout.height)
        .onChange(of: score.id, initial: true) { _, _ in cachedLayout = layout }
    }

    private func measureStrip(width: CGFloat, layout: ScoreDrawingLayout) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(score.measures) { measure in
                        Canvas { context, size in
                            drawMeasure(context, measure: measure, width: size.width, layout: layout)
                        }
                        .frame(width: width, height: layout.height)
                        .id(measure.number)
                        .accessibilityLabel("第\(measure.number)小节")
                    }
                }
            }
            .onChange(of: currentMeasure, initial: true) { previous, value in
                if active && previous != value {
                    withAnimation(.easeInOut(duration: 0.24)) { proxy.scrollTo(value, anchor: .leading) }
                } else {
                    proxy.scrollTo(value, anchor: .leading)
                }
            }
            .onChange(of: score.id) { _, _ in
                proxy.scrollTo(currentMeasure, anchor: .leading)
            }
        }
    }

    private func drawClefs(_ context: GraphicsContext, width: CGFloat, layout: ScoreDrawingLayout) {
        drawStaffLines(context, from: 5, to: width, layout: layout)

        let treble = Text("𝄞").font(.system(size: 43, design: .serif)).foregroundStyle(QinXuTheme.ink)
        let bass = Text("𝄢").font(.system(size: 36, design: .serif)).foregroundStyle(QinXuTheme.ink)
        context.draw(treble, at: CGPoint(x: width * 0.35, y: layout.trebleBottom - 17))
        context.draw(bass, at: CGPoint(x: width * 0.35, y: layout.bassBottom - 20))
        for bottom in [layout.trebleBottom, layout.bassBottom] {
            let x = width * 0.82
            let font = Font.system(size: 15, weight: .bold, design: .serif).monospacedDigit()
            let numerator = Text(String(score.beatsPerMeasure)).font(font).foregroundStyle(QinXuTheme.ink)
            let denominator = Text(String(score.beatUnit)).font(font).foregroundStyle(QinXuTheme.ink)
            context.draw(numerator, at: CGPoint(x: x, y: bottom - 27))
            context.draw(denominator, at: CGPoint(x: x, y: bottom - 9))
        }
        stroke(context, from: CGPoint(x: 5, y: layout.trebleBottom - 36),
               to: CGPoint(x: 5, y: layout.bassBottom), color: QinXuTheme.ink.opacity(0.6))
    }

    private func drawStaffLines(_ context: GraphicsContext, from left: CGFloat, to right: CGFloat,
                                layout: ScoreDrawingLayout) {
        for bottom in [layout.trebleBottom, layout.bassBottom] {
            for line in 0..<5 {
                let y = bottom - CGFloat(line) * 9
                stroke(context, from: CGPoint(x: left, y: y), to: CGPoint(x: right, y: y),
                       color: QinXuTheme.ink.opacity(0.30), lineWidth: 0.75)
            }
        }
    }

    private func drawMeasure(_ context: GraphicsContext, measure: ScoreMeasure, width: CGFloat,
                             layout: ScoreDrawingLayout) {
        let focused = measure.number == currentMeasure
        if focused {
            let selection = CGRect(x: 1, y: 5, width: width - 3, height: layout.height - 18)
            context.fill(Path(roundedRect: selection, cornerRadius: 10), with: .color(QinXuTheme.accentTint))
        }
        let labelColor = focused ? QinXuTheme.accent : QinXuTheme.muted
        context.draw(Text("\(measure.number)").font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(labelColor), at: CGPoint(x: 13, y: 19), anchor: .leading)

        drawStaffLines(context, from: 0, to: width, layout: layout)
        let barEnd = CGPoint(x: width - 1, y: layout.bassBottom)
        let barStart = CGPoint(x: barEnd.x, y: layout.trebleBottom - 36)
        stroke(context, from: barStart, to: barEnd, color: QinXuTheme.ink.opacity(0.36))
        if measure.number == score.measures.last?.number {
            stroke(context, from: CGPoint(x: barStart.x - 4, y: barStart.y),
                   to: CGPoint(x: barEnd.x - 4, y: barEnd.y), color: QinXuTheme.ink.opacity(0.6), lineWidth: 1.5)
        }

        drawBeatScale(context, measure: measure, width: width, y: layout.height - 22, color: labelColor)

        if currentBeat >= measure.startBeat && currentBeat < measure.startBeat + measure.durationBeats {
            let x = noteX(currentBeat, measure, width)
            stroke(context, from: CGPoint(x: x, y: layout.trebleBottom - 43),
                   to: CGPoint(x: x, y: layout.bassBottom + 13),
                   color: QinXuTheme.accent.opacity(active ? 0.53 : 0.20), lineWidth: active ? 1.5 : 1)
            if active {
                let cap = CGRect(x: x - 3.5, y: layout.trebleBottom - 46, width: 7, height: 7)
                context.fill(Path(ellipseIn: cap), with: .color(QinXuTheme.accent))
            }
        }

        let localNotes = layout.notesByMeasure[measure.number] ?? []
        let affectedPitches = Set(localNotes.filter { ScoreDrawingLayout.alteration(of: $0) != 0 }.map(WrittenPitch.init))
        for note in localNotes {
            drawNote(context, note: note, x: noteX(note.startBeat, measure, width), layout: layout,
                     focused: focused, resetAccidental: affectedPitches.contains(WrittenPitch(note)))
        }

        // Nonstandard durations and merged notes extending past the barline need an exact beat label.
        let standardDurations = [0.125, 0.1875, 0.25, 0.375, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0]
        let labels = localNotes.filter { note in
            note.startBeat + note.durationBeats > measure.startBeat + measure.durationBeats + 0.001 ||
                !standardDurations.contains { abs($0 - note.durationBeats) < 0.001 }
        }
        for (start, notes) in Dictionary(grouping: labels, by: \.startBeat) {
            let label = Set(notes.map { String(format: "%.3g拍", $0.durationBeats) }).sorted().joined(separator: "/")
            let text = Text(label).font(.system(size: 9).monospacedDigit()).foregroundStyle(QinXuTheme.muted)
            context.draw(text, at: CGPoint(x: noteX(start, measure, width), y: layout.height - 39))
        }
    }

    private func drawBeatScale(_ context: GraphicsContext, measure: ScoreMeasure, width: CGFloat,
                               y: CGFloat, color: Color) {
        let beatLength = 4.0 / Double(max(1, score.beatUnit))
        let count = max(1, min(score.beatsPerMeasure, Int(ceil(measure.durationBeats / beatLength - 0.000001))))
        let spacing = (width - 51) * CGFloat(beatLength / max(0.01, measure.durationBeats))
        let labelStride = max(1, Int(ceil(17 / max(1, spacing))))
        for beat in 0..<count {
            let x = noteX(measure.startBeat + Double(beat) * beatLength, measure, width)
            if beat % labelStride == 0 {
                let label = Text("\(beat + 1)").font(.system(size: 9).monospacedDigit()).foregroundStyle(color)
                context.draw(label, at: CGPoint(x: x, y: y))
            }
        }
    }

    private func drawNote(_ context: GraphicsContext, note: ScoreNote, x: CGFloat, layout: ScoreDrawingLayout,
                          focused: Bool, resetAccidental: Bool) {
        let bass = note.staff == 2
        let bottom = bass ? layout.bassBottom : layout.trebleBottom
        let pitch = ScoreDrawingLayout.diatonic(note)
        let y = bottom - CGFloat(pitch - (bass ? 18 : 30)) * 4.5
        let selected = hand.includes(staff: note.staff)
        let expected = selected && expectedNotes.contains(where: { $0.id == note.id })
        let color = selected ? noteColor(note.id, expected: expected) : QinXuTheme.ink.opacity(0.23)

        if expected {
            let halo = CGRect(x: x - 12, y: y - 11, width: 24, height: 22)
            context.fill(Path(ellipseIn: halo), with: .color(QinXuTheme.accent.opacity(0.15)))
        }
        drawLedgerLines(context, x: x, y: y, bottom: bottom, color: color)

        // The score intentionally omits the original key signature. Show altered notes
        // explicitly and restore naturals wherever an alteration in this bar can carry over.
        let alter = ScoreDrawingLayout.alteration(of: note)
        if alter != 0 || resetAccidental {
            let accidental = [-2: "𝄫", -1: "♭", 0: "♮", 1: "♯", 2: "𝄪"][alter] ?? ""
            let text = Text(accidental).font(.system(size: 15, design: .serif)).foregroundStyle(color)
            context.draw(text, at: CGPoint(x: x - 13, y: y))
        }

        let dotted = [4.0, 2, 1, 0.5, 0.25, 0.125].first { abs(note.durationBeats - $0 * 1.5) < 0.001 }
        let duration = dotted ?? note.durationBeats
        var rotated = context
        rotated.translateBy(x: x, y: y)
        rotated.rotate(by: .degrees(-18))
        let head = Path(ellipseIn: CGRect(x: -5.8, y: -3.8, width: 11.6, height: 7.6))
        let hollow = duration >= 1.99
        rotated.fill(head, with: .color(hollow ? (focused ? QinXuTheme.accentTint : QinXuTheme.paper) : color))
        if hollow { rotated.stroke(head, with: .color(color), lineWidth: 1.5) }

        if duration < 3.99 { drawStem(context, x: x, y: y, down: y < bottom - 18, duration: duration, color: color) }
        if dotted != nil {
            let onLine = abs((bottom - y).truncatingRemainder(dividingBy: 9)) < 0.1
            let dot = CGRect(x: x + 9, y: y - (onLine ? 5.7 : 1.5), width: 3, height: 3)
            context.fill(Path(ellipseIn: dot), with: .color(color))
        }
    }

    private func noteColor(_ id: String, expected: Bool) -> Color {
        switch verdicts[id] ?? .pending {
        case .correct: QinXuTheme.success
        case .wrong, .missed: QinXuTheme.wrong
        case .early, .late: QinXuTheme.amber
        case .pending: expected ? QinXuTheme.accent : QinXuTheme.ink
        }
    }

    private func drawLedgerLines(_ context: GraphicsContext, x: CGFloat, y: CGFloat, bottom: CGFloat, color: Color) {
        let lines: [CGFloat]
        if y >= bottom + 9 {
            lines = Array(stride(from: bottom + 9, through: y, by: 9))
        } else if y <= bottom - 45 {
            lines = Array(stride(from: bottom - 45, through: y, by: -9))
        } else {
            lines = []
        }
        for line in lines {
            stroke(context, from: CGPoint(x: x - 9, y: line), to: CGPoint(x: x + 9, y: line),
                   color: color.opacity(0.74), lineWidth: 0.9)
        }
    }

    private func drawStem(_ context: GraphicsContext, x: CGFloat, y: CGFloat, down: Bool, duration: Double, color: Color) {
        let stemX = x + (down ? -5.2 : 5.2)
        let stemY = y + (down ? 26.0 : -26.0)
        stroke(context, from: CGPoint(x: stemX, y: y), to: CGPoint(x: stemX, y: stemY),
               color: color, lineWidth: 1.15)
        if duration >= 0.99 { return }
        let flagCount = min(3, max(1, Int((-log2(max(duration, 0.125))).rounded(.down))))
        for index in 0..<flagCount {
            let flagY = stemY + CGFloat(index) * (down ? -5 : 5)
            var flag = Path()
            flag.move(to: CGPoint(x: stemX, y: flagY))
            flag.addQuadCurve(to: CGPoint(x: stemX + 7, y: flagY + (down ? -11 : 11)),
                              control: CGPoint(x: stemX + 12, y: flagY + (down ? -5 : 5)))
            context.stroke(flag, with: .color(color), lineWidth: 1.65)
        }
    }

    private func stroke(_ context: GraphicsContext, from start: CGPoint, to end: CGPoint,
                        color: Color, lineWidth: CGFloat = 1) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func noteX(_ beat: Double, _ measure: ScoreMeasure, _ width: CGFloat) -> CGFloat {
        29 + CGFloat((beat - measure.startBeat) / max(0.01, measure.durationBeats)) * (width - 51)
    }
}

private struct WrittenPitch: Hashable {
    let staff: Int
    let position: Int

    init(_ note: ScoreNote) {
        staff = note.staff
        position = ScoreDrawingLayout.diatonic(note)
    }
}

private struct ScoreDrawingLayout {
    let scoreID: String
    let notesByMeasure: [Int: [ScoreNote]]
    let trebleBottom: CGFloat
    let bassBottom: CGFloat
    let height: CGFloat

    init(_ score: PianoScore) {
        scoreID = score.id
        notesByMeasure = Dictionary(grouping: score.notes, by: \.measure)
        let treble = score.notes.lazy.filter { $0.staff != 2 }.map(Self.diatonic)
        let bass = score.notes.lazy.filter { $0.staff == 2 }.map(Self.diatonic)
        let trebleLedgerAbove = CGFloat(max(0, (treble.max() ?? 38) - 38)) * 4.5
        let trebleLedgerBelow = CGFloat(max(0, 30 - (treble.min() ?? 30))) * 4.5
        let bassLedgerAbove = CGFloat(max(0, (bass.max() ?? 26) - 26)) * 4.5
        let bassLedgerBelow = CGFloat(max(0, 18 - (bass.min() ?? 18))) * 4.5
        trebleBottom = 86 + trebleLedgerAbove
        bassBottom = trebleBottom + max(84, 59 + trebleLedgerBelow + bassLedgerAbove)
        height = max(221, bassBottom + bassLedgerBelow + 49)
    }

    static func diatonic(_ note: ScoreNote) -> Int {
        if let offset = pitchSteps[note.step.uppercased()] { return note.octave * 7 + offset }
        return (note.midi / 12 - 1) * 7 + [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6][note.midi % 12]
    }

    static func alteration(of note: ScoreNote) -> Int {
        if pitchSteps[note.step.uppercased()] != nil { return note.alter }
        return [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0][note.midi % 12]
    }

    private static let pitchSteps = ["C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6]
}
