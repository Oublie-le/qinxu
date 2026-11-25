import SwiftUI
import QinXuCore

struct PianoKeyboardView: View {
    let expectedPitches: Set<Int>
    let heldPitches: Set<Int>
    let hand: PracticeHand
    let interactive: Bool
    let press: (Int) -> Void
    let release: (Int) -> Void
    private var whites: [Int] { (0...127).filter { !isBlack($0) && $0 >= lower && $0 <= upper } }
    private var lower: Int { max(0, min(hand == .left ? 36 : 48, expectedPitches.union(heldPitches).min() ?? 48) / 12 * 12) }
    private var upper: Int { min(127, max(84, (expectedPitches.union(heldPitches).max() ?? 84) / 12 * 12 + 12)) }
    private func isBlack(_ pitch: Int) -> Bool { [1, 3, 6, 8, 10].contains(pitch % 12) }
    var body: some View {
        GeometryReader { geometry in
            let width = max(25, geometry.size.width / CGFloat(max(1, whites.count)))
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(whites, id: \.self) { pitch in
                            key(pitch, black: false).frame(width: width, height: 122)
                        }
                    }
                    ForEach(Array(lower...upper).filter(isBlack), id: \.self) { pitch in
                        key(pitch, black: true).frame(width: width * 0.59, height: 76)
                            .offset(x: CGFloat(whites.filter { $0 < pitch }.count) * width - width * 0.295)
                    }
                }.frame(width: CGFloat(whites.count) * width, height: 124)
            }.scrollIndicators(.hidden)
        }.frame(height: 124)
    }
    private func key(_ pitch: Int, black: Bool) -> some View {
        PianoTouchKey(pitch: pitch, black: black, expected: expectedPitches.contains(pitch), held: heldPitches.contains(pitch), interactive: interactive, press: press, release: release)
    }
}

private struct PianoTouchKey: View {
    let pitch: Int
    let black: Bool
    let expected: Bool
    let held: Bool
    let interactive: Bool
    let press: (Int) -> Void
    let release: (Int) -> Void
    @State private var touching = false
    private var color: Color {
        if held || touching { return QinXuTheme.teal }
        if expected { return black ? QinXuTheme.teal.opacity(0.7) : Color(red: 0.77, green: 0.88, blue: 0.81) }
        return black ? QinXuTheme.navy : .white
    }
    private var keyShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: black ? 4 : 5)
    }
    private var borderColor: Color { black ? Color.black.opacity(0.25) : QinXuTheme.line }
    private var labelColor: Color { black || held || touching ? Color.white.opacity(0.9) : QinXuTheme.muted }
    private var accessibleName: String {
        NoteNames.name(pitch) + (expected ? "，待弹" : "") + (held ? "，按下" : "")
    }
    private var accessibleValue: String {
        held || touching ? "已按下" : (expected ? "待弹" : "未按下")
    }

    @ViewBuilder private var noteLabel: some View {
        if expected || held || pitch % 12 == 0 {
            Text(NoteNames.name(pitch))
                .font(.system(size: black ? 7 : 9, weight: .medium, design: .monospaced))
                .foregroundStyle(labelColor)
                .padding(.bottom, black ? 7 : 10)
        }
    }

    private var keySurface: some View {
        keyShape.fill(color)
            .overlay(keyShape.stroke(borderColor, lineWidth: 1))
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
        keySurface.gesture(inputGesture)
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
            .accessibilityHint(interactive ? "按住弹奏，松开释放" : "切换触屏模式后可弹奏")
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
