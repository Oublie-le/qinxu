import SwiftUI

enum QinXuTheme {
    static let background = Color(red: 0.953, green: 0.960, blue: 0.978)
    static let paper = Color.white
    static let navy = Color(red: 0.10, green: 0.13, blue: 0.22)
    static let ink = Color(red: 0.09, green: 0.12, blue: 0.20)
    static let muted = Color(red: 0.34, green: 0.39, blue: 0.49)
    static let accent = Color(red: 0.212, green: 0.341, blue: 0.914)
    static let accentTint = Color(red: 0.923, green: 0.941, blue: 1)
    static let success = Color(red: 0.07, green: 0.45, blue: 0.34)
    static let line = Color(red: 0.875, green: 0.898, blue: 0.940)
    static let wrong = Color(red: 0.75, green: 0.18, blue: 0.28)
    static let amber = Color(red: 0.61, green: 0.38, blue: 0.06)
}

struct PracticeCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        content.padding(padding)
            .background(QinXuTheme.paper, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(QinXuTheme.line, lineWidth: 1).allowsHitTesting(false))
    }
}

struct QuietButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, prominent ? 15 : 10)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(prominent ? Color.white : QinXuTheme.ink)
            .background(prominent ? QinXuTheme.accent : QinXuTheme.background, in: RoundedRectangle(cornerRadius: 11))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
