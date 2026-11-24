import SwiftUI
import QinXuCore

struct PracticeScoreView: View {
    let score: PianoScore
    let hand: PracticeHand
    let currentBeat: Double
    let expectedNotes: [ScoreNote]
    let verdicts: [String: NoteVerdict]
    let active: Bool
    private let measureWidth: CGFloat = 285
    private var currentMeasure: Int { expectedNotes.first?.measure ?? score.measures.last(where: { $0.startBeat <= currentBeat })?.number ?? 1 }
    private var trebleBottom: CGFloat {
        max(115, 58 + CGFloat((score.notes.filter { $0.staff != 2 }.map(diatonic).max() ?? 38) - 30) * 5)
    }
    private var bassBottom: CGFloat {
        let trebleLow = score.notes.filter { $0.staff != 2 }.map(diatonic).min() ?? 30
        let bassHigh = score.notes.filter { $0.staff == 2 }.map(diatonic).max() ?? 26
        return max(trebleBottom + 120, trebleBottom + CGFloat(30 - trebleLow) * 5 + 65 + CGFloat(bassHigh - 18) * 5)
    }
    private var height: CGFloat {
        bassBottom + max(0, CGFloat(18 - (score.notes.filter { $0.staff == 2 }.map(diatonic).min() ?? 18)) * 5) + 55
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    Canvas { context, _ in
                        drawLines(context, width: 75)
                        context.draw(Text("𝄞").font(.system(size: 51, design: .serif)).foregroundStyle(QinXuTheme.ink), at: CGPoint(x: 38, y: trebleBottom - 17))
                        context.draw(Text("𝄢").font(.system(size: 40, design: .serif)).foregroundStyle(QinXuTheme.ink), at: CGPoint(x: 38, y: bassBottom - 24))
                    }.frame(width: 75, height: height)
                    ForEach(score.measures) { measure in
                        Canvas { context, size in drawMeasure(context, measure: measure, size: size) }
                            .frame(width: measureWidth, height: height).id(measure.number)
                            .accessibilityLabel("第\(measure.number)小节")
                    }
                }
            }
            .onChange(of: currentMeasure) { _, value in
                if active { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(value, anchor: .center) } }
            }
            .onChange(of: score.id) { _, _ in proxy.scrollTo(score.measures.first?.number ?? 1, anchor: .leading) }
        }
    }
    private func drawLines(_ context: GraphicsContext, width: CGFloat) {
        for bottom in [trebleBottom, bassBottom] {
            for line in 0..<5 {
                var path = Path(); let y = bottom - CGFloat(line) * 10
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: width, y: y))
                context.stroke(path, with: .color(QinXuTheme.ink.opacity(0.28)), lineWidth: 0.7)
            }
        }
    }
    private func drawMeasure(_ context: GraphicsContext, measure: ScoreMeasure, size: CGSize) {
        if measure.number == currentMeasure {
            context.fill(Path(roundedRect: CGRect(x: 1, y: 12, width: size.width - 2, height: height - 35), cornerRadius: 9), with: .color(QinXuTheme.teal.opacity(0.045)))
        }
        drawLines(context, width: size.width)
        context.draw(Text(String(format: "%02d", measure.number)).font(.system(size: 10, design: .monospaced)).foregroundStyle(QinXuTheme.muted), at: CGPoint(x: 15, y: 26))
        var bar = Path(); bar.move(to: CGPoint(x: size.width - 1, y: trebleBottom - 40)); bar.addLine(to: CGPoint(x: size.width - 1, y: bassBottom))
        context.stroke(bar, with: .color(QinXuTheme.line), lineWidth: 1)
        for beat in 0..<max(1, Int(ceil(measure.durationBeats))) {
            let x = noteX(measure.startBeat + Double(beat), measure)
            context.draw(Text("\(beat + 1)").font(.system(size: 8, design: .monospaced)).foregroundStyle(QinXuTheme.muted.opacity(0.6)), at: CGPoint(x: x, y: height - 18))
        }
        if currentBeat >= measure.startBeat && currentBeat < measure.startBeat + measure.durationBeats {
            let x = noteX(currentBeat, measure)
            var cursor = Path(); cursor.move(to: CGPoint(x: x, y: 40)); cursor.addLine(to: CGPoint(x: x, y: height - 30))
            context.stroke(cursor, with: .color(QinXuTheme.teal.opacity(active ? 0.25 : 0.12)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
        // Exact beat labels prevent tuplets or merged ties looking like ordinary durations.
        let localNotes = score.notes.filter { $0.measure == measure.number }
        let standard = [0.125, 0.1875, 0.25, 0.375, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0]
        let special = localNotes.filter { note in !standard.contains { abs($0 - note.durationBeats) < 0.001 } }
        for (start, notes) in Dictionary(grouping: special, by: { $0.startBeat }) {
            let labels = Set(notes.map { String(format: "%.3g拍", $0.durationBeats) }).sorted().joined(separator: "/")
            context.draw(Text(labels).font(.system(size: 8, design: .monospaced)).foregroundStyle(QinXuTheme.muted), at: CGPoint(x: noteX(start, measure), y: height - 34))
        }
        for note in score.notes where note.measure == measure.number {
            let x = noteX(note.startBeat, measure), bottom = note.staff == 2 ? bassBottom : trebleBottom
            let y = bottom - CGFloat(diatonic(note) - (note.staff == 2 ? 18 : 30)) * 5
            let selected = hand.includes(staff: note.staff)
            let expected = selected && expectedNotes.contains(where: { $0.id == note.id })
            let color: Color
            if !selected { color = QinXuTheme.ink.opacity(0.18) }
            else {
                switch verdicts[note.id] ?? .pending {
                case .correct: color = QinXuTheme.teal
                case .wrong, .missed: color = QinXuTheme.wrong
                case .early, .late: color = QinXuTheme.amber
                case .pending: color = expected ? QinXuTheme.teal : QinXuTheme.ink
                }
            }
            if expected { context.fill(Path(ellipseIn: CGRect(x: x - 15, y: y - 14, width: 30, height: 28)), with: .color(QinXuTheme.teal.opacity(0.11))) }
            var ledgers: [CGFloat] = []
            if y >= bottom + 10 { ledgers = Array(stride(from: bottom + 10, through: y + 0.1, by: 10)) }
            if y <= bottom - 50 { ledgers = Array(stride(from: bottom - 50, through: y - 0.1, by: -10)) }
            for ly in ledgers {
                var line = Path(); line.move(to: CGPoint(x: x - 11, y: ly)); line.addLine(to: CGPoint(x: x + 11, y: ly))
                context.stroke(line, with: .color(color.opacity(0.6)), lineWidth: 0.8)
            }
            let dotted = [4.0, 2, 1, 0.5, 0.25, 0.125].first { abs(note.durationBeats - $0 * 1.5) < 0.001 }
            let duration = dotted ?? note.durationBeats
            var rotated = context; rotated.translateBy(x: x, y: y); rotated.rotate(by: .degrees(-18))
            let head = Path(ellipseIn: CGRect(x: -6, y: -4, width: 12, height: 8))
            rotated.fill(head, with: .color(duration >= 1.99 ? QinXuTheme.paper : color))
            if duration >= 1.99 { rotated.stroke(head, with: .color(color), lineWidth: 1.8) }
            let accidental = note.alter == -2 ? "𝄫" : note.alter == -1 ? "♭" : note.alter == 1 ? "♯" : note.alter == 2 ? "𝄪" : "♮"
            context.draw(Text(accidental).font(.system(size: 16, design: .serif)).foregroundStyle(color.opacity(0.8)), at: CGPoint(x: x - 16, y: y - 1))
            if duration < 3.99 {
                let down = y < bottom - 20
                let sx = x + (down ? -5.5 : 5.5), sy = y + (down ? 29.0 : -29.0)
                var stem = Path(); stem.move(to: CGPoint(x: sx, y: y)); stem.addLine(to: CGPoint(x: sx, y: sy))
                context.stroke(stem, with: .color(color), lineWidth: 1.2)
                let flags = duration < 0.99 ? min(3, max(1, Int((-log2(max(duration, 0.125))).rounded(.down)))) : 0
                for flagIndex in 0..<flags {
                    let fy = sy + CGFloat(flagIndex) * (down ? -5 : 5)
                    var flag = Path(); flag.move(to: CGPoint(x: sx, y: fy)); flag.addQuadCurve(to: CGPoint(x: sx + 8, y: fy + (down ? -13 : 13)), control: CGPoint(x: sx + 14, y: fy + (down ? -6 : 6)))
                    context.stroke(flag, with: .color(color), lineWidth: 1.7)
                }
            }
            if dotted != nil {
                let onLine = abs((bottom - y).truncatingRemainder(dividingBy: 10)) < 0.1
                context.fill(Path(ellipseIn: CGRect(x: x + 11, y: y - (onLine ? 6.5 : 1.5), width: 3, height: 3)), with: .color(color))
            }
        }
    }
    private func noteX(_ beat: Double, _ measure: ScoreMeasure) -> CGFloat {
        33 + CGFloat((beat - measure.startBeat) / max(0.01, measure.durationBeats)) * (measureWidth - 48)
    }
    private func diatonic(_ note: ScoreNote) -> Int {
        if let offset = ["C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6][note.step.uppercased()] { return note.octave * 7 + offset }
        return (note.midi / 12 - 1) * 7 + [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6][((note.midi % 12) + 12) % 12]
    }
}
