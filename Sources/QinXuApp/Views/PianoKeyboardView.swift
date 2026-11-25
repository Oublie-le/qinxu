import SwiftUI
import QinXuCore

/// A piece keeps one keyboard layout. Live targets and detected notes only affect highlighting.
enum PianoKeyboardRange {
    static func forScore(_ score: PianoScore, hand: PracticeHand) -> ClosedRange<Int> {
        let pitches = score.notes.filter { hand.includes(staff: $0.staff) }
            .map(\.midi).filter { (0...127).contains($0) }
        guard let first = pitches.min(), let last = pitches.max() else { return 48...84 }
        // Leave at least three semitones around the piece, aligned to octave boundaries.
        var lower = max(0, (first - 3) / 12 * 12)
        var upper = min(127, (last + 3 + 11) / 12 * 12)
        // Short exercises still show at least three octaves instead of just a few keys.
        while upper - lower < 36 {
            if lower == 0 { upper = min(127, upper + 12) }
            else if upper == 127 { lower = max(0, lower - 12) }
            else if first + last >= lower + upper { upper = min(127, upper + 12) }
            else { lower = max(0, lower - 12) }
        }
        return lower...upper
    }
}

struct PianoKeyHighlight: Equatable {
    enum Fill: Equatable { case plain, expected, sustained, held }
    let fill: Fill
    let showsExpectedMarker: Bool

    init(expected: Bool, held: Bool, sustained: Bool) {
        fill = held ? .held : sustained ? .sustained : expected ? .expected : .plain
        showsExpectedMarker = expected
    }
}

struct PianoKeyboardView: View {
    let pitchRange: ClosedRange<Int>
    let expectedPitches: Set<Int>
    let heldPitches: Set<Int>
    var sustainedPitches: Set<Int> = []
    let interactive: Bool
    let press: (Int) -> Void
    let release: (Int) -> Void
    var representsSound = false
    var compact: Bool = false
    private var keyHeight: CGFloat { compact ? 58 : 122 }
    private var whites: [Int] { pitchRange.filter { !isBlack($0) } }
    private func isBlack(_ pitch: Int) -> Bool { [1, 3, 6, 8, 10].contains(pitch % 12) }
    var body: some View {
        GeometryReader { geometry in
            let width = max(25, geometry.size.width / CGFloat(max(1, whites.count)))
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(whites, id: \.self) { pitch in
                            key(pitch, black: false).frame(width: width, height: keyHeight)
                        }
                    }
                    ForEach(pitchRange.filter(isBlack), id: \.self) { pitch in
                        key(pitch, black: true).frame(width: width * 0.59, height: compact ? 36 : 76)
                            .offset(x: CGFloat(whites.filter { $0 < pitch }.count) * width - width * 0.295)
                    }
                }.frame(width: CGFloat(whites.count) * width, height: keyHeight + 2)
            }.scrollIndicators(.automatic)
        }.frame(height: keyHeight + 2)
    }
    private func key(_ pitch: Int, black: Bool) -> some View {
        PianoTouchKey(pitch: pitch, black: black, expected: expectedPitches.contains(pitch),
                      held: heldPitches.contains(pitch), sustained: sustainedPitches.contains(pitch),
                      interactive: interactive, representsSound: representsSound, press: press, release: release)
    }
}

private struct PianoTouchKey: View {
    let pitch: Int
    let black: Bool
    let expected: Bool
    let held: Bool
    let sustained: Bool
    let interactive: Bool
    let representsSound: Bool
    let press: (Int) -> Void
    let release: (Int) -> Void
    @State private var touching = false
    private var highlight: PianoKeyHighlight {
        PianoKeyHighlight(expected: expected, held: held || touching, sustained: sustained)
    }
    private var color: Color {
        switch highlight.fill {
        case .held: return QinXuTheme.accent
        case .sustained: return QinXuTheme.softAccent
        case .expected: return black ? QinXuTheme.teal.opacity(0.7) : Color(red: 0.77, green: 0.88, blue: 0.81)
        case .plain: return black ? QinXuTheme.navy : .white
        }
    }
    private var keyShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: black ? 4 : 5)
    }
    private var borderColor: Color { black ? Color.black.opacity(0.25) : QinXuTheme.line }
    private var labelColor: Color {
        if held || touching { return Color.white.opacity(0.9) }
        if sustained { return QinXuTheme.accent }
        return black ? Color.white.opacity(0.9) : QinXuTheme.muted
    }
    private var accessibleName: String {
        NoteNames.name(pitch)
    }
    private var accessibleValue: String {
        var states: [String] = []
        if expected { states.append("待弹") }
        if held || touching { states.append(representsSound ? "识别到声音" : "已按下") }
        if sustained { states.append("应保持") }
        return states.isEmpty ? (representsSound ? "未识别到声音" : "未按下") : states.joined(separator: "，")
    }

    @ViewBuilder private var noteLabel: some View {
        if expected || held || sustained || pitch % 12 == 0 {
            Text(NoteNames.name(pitch))
                .font(.system(size: black ? 7 : 9, weight: .medium, design: .monospaced))
                .foregroundStyle(labelColor)
                .padding(.bottom, black ? 7 : 10)
        }
    }

    private var keySurface: some View {
        keyShape.fill(color)
            .overlay(keyShape.stroke(highlight.showsExpectedMarker ? QinXuTheme.teal : borderColor,
                                     lineWidth: highlight.showsExpectedMarker ? 2 : 1))
            .overlay(alignment: .top) {
                if highlight.showsExpectedMarker {
                    Circle().fill(QinXuTheme.teal).frame(width: 5, height: 5).padding(.top, 5)
                }
            }
            .overlay(alignment: .bottom) { noteLabel }
            .padding(.horizontal, black ? 0 : 0.5)
            .contentShape(Rectangle())
    }

    private var inputGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if interactive && !touching { touching = true; press(pitch) }
            }
            .onEnded { _ in releaseTouch() }
    }

    private var interactiveSurface: some View {
        keySurface.gesture(inputGesture, including: interactive ? .all : .none)
            .onChange(of: interactive) { _, value in if !value { releaseTouch() } }
            .onDisappear { releaseTouch() }
    }

    var body: some View {
        interactiveSurface
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("keyboard.key.\(pitch)")
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(accessibleValue)
            .accessibilityLabel(accessibleName)
            .accessibilityHint(interactive ? "按住弹奏，松开释放" : representsSound ? "声音可能包含余音，不表示实际按键状态" : "切换触屏模式后可弹奏")
            .accessibilityAction { playAccessibleNote() }
    }

    private func releaseTouch() {
        if touching { touching = false; release(pitch) }
    }

    private func playAccessibleNote() {
        guard interactive else { return }
        press(pitch)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            release(pitch)
        }
    }
}
