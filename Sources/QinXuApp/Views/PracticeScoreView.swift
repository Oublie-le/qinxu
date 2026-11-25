import SwiftUI
import QinXuCore

struct PracticeScoreView: View {
    let score: PianoScore
    let hand: PracticeHand
    let currentBeat: Double
    let expectedNotes: [ScoreNote]
    let verdicts: [String: NoteVerdict]
    let active: Bool
    var compact: Bool = false
    private let staffSpace: CGFloat = 10
    private var leadingWidth: CGFloat { compact ? 88 : 104 }
    private var currentMeasure: Int { expectedNotes.first?.measure ?? score.measures.last(where: { $0.startBeat <= currentBeat })?.number ?? 1 }
    private var trebleBottom: CGFloat {
        max(compact ? 66 : 115, (compact ? 34 : 58) + CGFloat((score.notes.filter { $0.staff != 2 }.map(diatonic).max() ?? 38) - 30) * 5)
    }
    private var bassBottom: CGFloat {
        let trebleLow = score.notes.filter { $0.staff != 2 }.map(diatonic).min() ?? 30
        let bassHigh = score.notes.filter { $0.staff == 2 }.map(diatonic).max() ?? (compact ? 22 : 26)
        return max(trebleBottom + (compact ? 66 : 120), trebleBottom + CGFloat(30 - trebleLow) * 5 + (compact ? 32 : 65) + CGFloat(bassHigh - 18) * 5)
    }
    var preferredHeight: CGFloat {
        bassBottom + max(0, CGFloat(18 - (score.notes.filter { $0.staff == 2 }.map(diatonic).min() ?? 18)) * 5) + (compact ? 32 : 55)
    }
    private var height: CGFloat { preferredHeight }

    var body: some View {
        if NotationFont.isAvailable {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        Canvas { context, _ in drawClefs(context) }
                            .frame(width: leadingWidth, height: height).id("score-start")
                        ForEach(score.measures) { measure in
                            let spacing = spacing(for: measure)
                            Canvas { context, size in drawMeasure(context, measure: measure, spacing: spacing, size: size) }
                                .frame(width: spacing.width, height: height).id(measure.number)
                                .accessibilityLabel("第\(measure.number)小节")
                        }
                    }
                }
                .frame(height: height)
                .onChange(of: currentMeasure) { _, value in
                    if active {
                        withAnimation(.easeInOut(duration: 0.25)) { revealMeasure(value, using: proxy) }
                    } else { revealMeasure(value, using: proxy) }
                }
                .onChange(of: hand) { _, _ in revealMeasure(currentMeasure, using: proxy) }
                .onAppear { revealMeasure(currentMeasure, using: proxy) }
                .onChange(of: score.id) { _, _ in proxy.scrollTo("score-start", anchor: .leading) }
            }
        } else {
            Label("乐谱字体未就绪，请重新安装完整版本", systemImage: "music.note")
                .font(.system(size: 13)).foregroundStyle(QinXuTheme.muted)
                .frame(maxWidth: .infinity).frame(height: height)
        }
    }

    private func revealMeasure(_ number: Int, using proxy: ScrollViewProxy) {
        if number == score.measures.first?.number { proxy.scrollTo("score-start", anchor: .leading) }
        else { proxy.scrollTo(number, anchor: .center) }
    }

    private func drawClefs(_ context: GraphicsContext) {
        drawLines(context, width: leadingWidth, from: 19)
        let top = trebleBottom - 40
        var connector = Path()
        connector.move(to: CGPoint(x: 19, y: top)); connector.addLine(to: CGPoint(x: 19, y: bassBottom))
        context.stroke(connector, with: .color(QinXuTheme.ink.opacity(0.55)), lineWidth: 0.9)
        if let brace = NotationFont.path(.brace) {
            let bounds = brace.boundingBoxOfPath
            var transform = CGAffineTransform(a: 9 / bounds.width, b: 0, c: 0,
                                             d: -(bassBottom - top) / bounds.height, tx: 5, ty: bassBottom)
            if let path = brace.copy(using: &transform) { context.fill(Path(path), with: .color(QinXuTheme.ink)) }
        }
        NotationFont.draw(.trebleClef, in: context, at: CGPoint(x: 26, y: trebleBottom - 10), color: QinXuTheme.ink)
        NotationFont.draw(.bassClef, in: context, at: CGPoint(x: 26, y: bassBottom - 30), color: QinXuTheme.ink)
        for bottom in [trebleBottom, bassBottom] {
            NotationFont.drawTimeNumber(score.beatsPerMeasure, in: context, centeredAt: CGPoint(x: leadingWidth - 18, y: bottom - 30), color: QinXuTheme.ink)
            NotationFont.drawTimeNumber(score.beatUnit, in: context, centeredAt: CGPoint(x: leadingWidth - 18, y: bottom - 10), color: QinXuTheme.ink)
        }
    }

    private func drawLines(_ context: GraphicsContext, width: CGFloat, from start: CGFloat = 0) {
        for bottom in [trebleBottom, bassBottom] {
            for line in 0..<5 {
                var path = Path(); let y = bottom - CGFloat(line) * staffSpace
                path.move(to: CGPoint(x: start, y: y)); path.addLine(to: CGPoint(x: width, y: y))
                context.stroke(path, with: .color(QinXuTheme.ink.opacity(0.36)), lineWidth: 0.75)
            }
        }
    }

    private func drawMeasure(_ context: GraphicsContext, measure: ScoreMeasure, spacing: MeasureSpacing, size: CGSize) {
        if measure.number == currentMeasure {
            context.fill(Path(roundedRect: CGRect(x: 1, y: 12, width: size.width - 2, height: height - 35), cornerRadius: 9), with: .color(QinXuTheme.accent.opacity(0.045)))
        }
        drawLines(context, width: size.width)
        context.draw(Text(String(measure.number)).font(.system(size: 10, design: .serif)).foregroundStyle(QinXuTheme.muted), at: CGPoint(x: 13, y: 17))
        let finalBar = measure.number == score.measures.last?.number
        let barX = size.width - (finalBar ? 6 : 1)
        var bar = Path(); bar.move(to: CGPoint(x: barX, y: trebleBottom - 40)); bar.addLine(to: CGPoint(x: barX, y: bassBottom))
        context.stroke(bar, with: .color(QinXuTheme.ink.opacity(0.4)), lineWidth: 0.9)
        if finalBar {
            var end = Path(); end.move(to: CGPoint(x: size.width - 1, y: trebleBottom - 40)); end.addLine(to: CGPoint(x: size.width - 1, y: bassBottom))
            context.stroke(end, with: .color(QinXuTheme.ink.opacity(0.7)), lineWidth: 2.5)
        }
        for beat in 0..<max(1, Int(ceil(measure.durationBeats))) {
            context.draw(Text("\(beat + 1)").font(.system(size: 8, design: .monospaced)).foregroundStyle(QinXuTheme.muted.opacity(0.65)), at: CGPoint(x: spacing.x(at: measure.startBeat + Double(beat)), y: height - 16))
        }
        if currentBeat >= measure.startBeat && currentBeat < measure.startBeat + measure.durationBeats {
            let x = spacing.x(at: currentBeat)
            var cursor = Path(); cursor.move(to: CGPoint(x: x, y: 31)); cursor.addLine(to: CGPoint(x: x, y: height - 27))
            context.stroke(cursor, with: .color(QinXuTheme.teal.opacity(active ? 0.22 : 0.10)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
        let notes = score.notes.filter { $0.measure == measure.number }
        let accidentals = requiredAccidentals(notes)
        for (start, simultaneous) in Dictionary(grouping: notes, by: \.startBeat).sorted(by: { $0.key < $1.key }) {
            for staffNotes in Dictionary(grouping: simultaneous, by: \.staff).values {
                // The model has no voice/stem/beam information. Share a stem only when
                // the staff, onset and exact duration agree; never merge unequal values.
                let durationGroups = Dictionary(grouping: staffNotes, by: \.durationBeats).values.sorted {
                    ($0.map(diatonic).max() ?? 0) > ($1.map(diatonic).max() ?? 0)
                }
                for (index, chord) in durationGroups.enumerated() {
                    drawChord(context, notes: chord, x: spacing.x(at: start) + CGFloat(index) * 7,
                              accidentals: accidentals, forcedDown: durationGroups.count > 1 ? index > 0 : nil)
                }
            }
        }
        // Tuplets and merged ties lack their original notation in PianoScore. Keep
        // the exact numeric duration visible instead of silently rounding the rhythm.
        let special = notes.filter { !DurationNotation(beats: $0.durationBeats).isExact }
        for (start, group) in Dictionary(grouping: special, by: \.startBeat) {
            let labels = Set(group.map { String(format: "%.3g拍", $0.durationBeats) }).sorted().joined(separator: "/")
            context.draw(Text(labels).font(.system(size: 8, design: .monospaced)).foregroundStyle(QinXuTheme.muted), at: CGPoint(x: spacing.x(at: start), y: height - 31))
        }
    }

    private struct Head {
        let note: ScoreNote
        let origin: CGPoint
        let width: CGFloat
        let color: Color
    }

    private func drawChord(_ context: GraphicsContext, notes: [ScoreNote], x: CGFloat,
                           accidentals: [String: Int], forcedDown: Bool?) {
        guard let first = notes.first else { return }
        let bottom = first.staff == 2 ? bassBottom : trebleBottom
        let middle = first.staff == 2 ? 22 : 34
        let sorted = notes.sorted { diatonic($0) < diatonic($1) }
        let down = forcedDown ?? ((diatonic(sorted.first!) + diatonic(sorted.last!)) >= middle * 2)
        let notation = DurationNotation(beats: first.durationBeats)
        let width = NotationFont.bounds(notation.head).width
        let ordered = down ? Array(sorted.reversed()) : sorted
        var heads: [Head] = []
        var lastPitch: Int?, displaced = false
        for note in ordered {
            let pitch = diatonic(note)
            displaced = lastPitch.map { abs(pitch - $0) <= 1 && !displaced } ?? false
            let shift: CGFloat = displaced ? (width - 1.2) * (down ? -1 : 1) : 0
            let y = bottom - CGFloat(pitch - (note.staff == 2 ? 18 : 30)) * 5
            heads.append(Head(note: note, origin: CGPoint(x: x - width / 2 + shift, y: y), width: width, color: noteColor(note)))
            lastPitch = pitch
        }
        for head in heads {
            if hand.includes(staff: head.note.staff), expectedNotes.contains(where: { $0.id == head.note.id }) {
                context.fill(Path(ellipseIn: CGRect(x: head.origin.x - 6, y: head.origin.y - 11, width: head.width + 12, height: 22)), with: .color(QinXuTheme.accent.opacity(0.10)))
            }
            var ledgers: [CGFloat] = []
            if head.origin.y >= bottom + 10 { ledgers = Array(stride(from: bottom + 10, through: head.origin.y + 0.1, by: 10)) }
            if head.origin.y <= bottom - 50 { ledgers = Array(stride(from: bottom - 50, through: head.origin.y - 0.1, by: -10)) }
            for y in ledgers {
                var line = Path(); line.move(to: CGPoint(x: head.origin.x - 4, y: y)); line.addLine(to: CGPoint(x: head.origin.x + head.width + 4, y: y))
                context.stroke(line, with: .color(head.color.opacity(0.7)), lineWidth: 1.1)
            }
        }
        if notation.hasStem, let top = heads.map(\.origin.y).min(), let low = heads.map(\.origin.y).max() {
            let stemX = x + (down ? -width / 2 + 0.6 : width / 2 - 0.6)
            let stemEnd = down ? max(low + 35, bottom - 20) : min(top - 35, bottom - 20)
            let stemStart = down ? top + 1.68 : low - 1.68
            let color = heads.first(where: { expectedNotes.contains($0.note) })?.color ?? noteColor(first)
            var stem = Path(); stem.move(to: CGPoint(x: stemX, y: stemStart)); stem.addLine(to: CGPoint(x: stemX, y: stemEnd))
            context.stroke(stem, with: .color(color), lineWidth: 1.2)
            if let flag = notation.flag(down: down) {
                NotationFont.draw(flag, in: context, at: CGPoint(x: stemX - 0.6, y: stemEnd), color: color)
            }
        }
        let left = heads.map(\.origin.x).min() ?? x - width / 2
        var accidentalColumns: [[ClosedRange<CGFloat>]] = []
        var dotRows: [CGFloat] = []
        for head in heads.sorted(by: { $0.origin.y < $1.origin.y }) {
            if let alter = accidentals[head.note.id] {
                let glyph: NotationFont.Glyph = alter == -2 ? .doubleFlat : alter == -1 ? .flat : alter == 1 ? .sharp : alter == 2 ? .doubleSharp : .natural
                let bounds = NotationFont.bounds(glyph)
                let interval = (head.origin.y - bounds.maxY - 2)...(head.origin.y - bounds.minY + 2)
                let column = accidentalColumns.firstIndex(where: { !$0.contains(where: { $0.overlaps(interval) }) }) ?? accidentalColumns.count
                if column == accidentalColumns.count { accidentalColumns.append([]) }
                accidentalColumns[column].append(interval)
                NotationFont.draw(glyph, in: context, at: CGPoint(x: left - 6 - bounds.width - CGFloat(column) * 13, y: head.origin.y), color: head.color)
            }
            NotationFont.draw(notation.head, in: context, at: head.origin, color: head.color)
            if notation.dotted {
                let onLine = abs((bottom - head.origin.y).truncatingRemainder(dividingBy: 10)) < 0.1
                let dotX = (heads.map { $0.origin.x + $0.width }.max() ?? x) + 5
                var dotY = head.origin.y - (onLine ? 5 : 0)
                while dotRows.contains(where: { abs($0 - dotY) < 2 }) { dotY += 10 }
                dotRows.append(dotY)
                NotationFont.draw(.dot, in: context, at: CGPoint(x: dotX, y: dotY), color: head.color)
            }
        }
    }

    private func noteColor(_ note: ScoreNote) -> Color {
        guard hand.includes(staff: note.staff) else { return QinXuTheme.ink.opacity(0.20) }
        switch verdicts[note.id] ?? .pending {
        case .correct: return QinXuTheme.teal
        case .wrong, .missed: return QinXuTheme.wrong
        case .early, .late: return QinXuTheme.amber
        case .pending: return expectedNotes.contains(where: { $0.id == note.id }) ? QinXuTheme.accent : QinXuTheme.ink
        }
    }

    private func requiredAccidentals(_ notes: [ScoreNote]) -> [String: Int] {
        var state: [String: Int] = [:], result: [String: Int] = [:]
        for group in Dictionary(grouping: notes, by: \.startBeat).sorted(by: { $0.key < $1.key }).map(\.value) {
            for matchingPitch in Dictionary(grouping: group, by: { "\($0.staff):\(diatonic($0))" }).values {
                let key = "\(matchingPitch[0].staff):\(diatonic(matchingPitch[0]))"
                let alterations = Set(matchingPitch.map(notatedAlter))
                for note in matchingPitch {
                    let alter = notatedAlter(note)
                    if alter != (state[key] ?? 0) || alterations.count > 1 { result[note.id] = alter }
                }
                state[key] = alterations.count > 1 ? Int.max : alterations.first
            }
        }
        return result
    }

    private func notatedAlter(_ note: ScoreNote) -> Int {
        if ["C", "D", "E", "F", "G", "A", "B"].contains(note.step.uppercased()) { return note.alter }
        return [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0][((note.midi % 12) + 12) % 12]
    }
    private func diatonic(_ note: ScoreNote) -> Int {
        if let offset = ["C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6][note.step.uppercased()] { return note.octave * 7 + offset }
        return (note.midi / 12 - 1) * 7 + [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6][((note.midi % 12) + 12) % 12]
    }

    private struct DurationNotation {
        let base: Double
        let dotted: Bool
        let isExact: Bool
        init(beats: Double) {
            let values = [4.0, 2, 1, 0.5, 0.25, 0.125]
            if let exact = values.first(where: { abs(beats - $0) < 0.000001 }) {
                base = exact; dotted = false; isExact = true
            } else if let dot = values.first(where: { abs(beats - $0 * 1.5) < 0.000001 }) {
                base = dot; dotted = true; isExact = true
            } else {
                // Deliberately approximate only the silhouette; a numeric beat label
                // is mandatory for this case, including tuplets and long merged ties.
                base = values.min(by: { abs($0 - beats) < abs($1 - beats) }) ?? 1
                dotted = false; isExact = false
            }
        }
        var head: NotationFont.Glyph { base >= 4 ? .wholeHead : base >= 2 ? .halfHead : .blackHead }
        var hasStem: Bool { base < 4 }
        func flag(down: Bool) -> NotationFont.Glyph? {
            if base <= 0.125 { return down ? .thirtySecondDown : .thirtySecondUp }
            if base <= 0.25 { return down ? .sixteenthDown : dotted ? .sixteenthUpShort : .sixteenthUp }
            if base <= 0.5 { return down ? .eighthDown : dotted ? .eighthUpShort : .eighthUp }
            return nil
        }
    }

    private struct MeasureSpacing {
        let beats: [Double]
        let positions: [CGFloat]
        let width: CGFloat
        func x(at beat: Double) -> CGFloat {
            guard let first = beats.first, let start = positions.first else { return 42 }
            if beat <= first { return start }
            for index in 1..<beats.count where beat <= beats[index] {
                let fraction = (beat - beats[index - 1]) / max(0.000001, beats[index] - beats[index - 1])
                return positions[index - 1] + CGFloat(fraction) * (positions[index] - positions[index - 1])
            }
            return positions.last ?? start
        }
    }
    private func spacing(for measure: ScoreMeasure) -> MeasureSpacing {
        let notes = score.notes.filter { $0.measure == measure.number }
        let beats = Set(notes.map(\.startBeat) + [measure.startBeat, measure.startBeat + measure.durationBeats]).sorted()
        let naturalWidth: CGFloat = compact ? 230 : 285
        let minimumSpacing: CGFloat = notes.contains { !DurationNotation(beats: $0.durationBeats).isExact } ? 44 : 30
        var positions: [CGFloat] = [42]
        for index in 1..<beats.count {
            let fraction = (beats[index] - beats[index - 1]) / max(0.01, measure.durationBeats)
            positions.append(positions.last! + max(minimumSpacing, CGFloat(fraction) * (naturalWidth - 64)))
        }
        return MeasureSpacing(beats: beats, positions: positions, width: (positions.last ?? 42) + 22)
    }
}
