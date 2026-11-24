import SwiftUI

enum PracticeTheme {
    static let background = Color(red: 0.96, green: 0.95, blue: 0.92)
    static let paper = Color(red: 0.995, green: 0.99, blue: 0.97)
    static let navy = Color(red: 0.10, green: 0.17, blue: 0.20)
    static let ink = Color(red: 0.16, green: 0.23, blue: 0.25)
    static let muted = Color(red: 0.44, green: 0.48, blue: 0.47)
    static let teal = Color(red: 0.13, green: 0.44, blue: 0.40)
    static let line = Color(red: 0.86, green: 0.87, blue: 0.83)
    static let wrong = Color(red: 0.75, green: 0.30, blue: 0.24)
    static let amber = Color(red: 0.65, green: 0.45, blue: 0.15)
}

struct PracticeCard<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content.padding(padding)
            .background(PracticeTheme.paper, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(PracticeTheme.line.opacity(0.8), lineWidth: 1))
    }
}

struct QuietButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 15).padding(.vertical, 11)
            .foregroundStyle(prominent ? Color.white : PracticeTheme.ink)
            .background(prominent ? PracticeTheme.teal : Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(prominent ? Color.clear : PracticeTheme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct SectionEyebrow: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(2).foregroundStyle(PracticeTheme.muted)
    }
}
