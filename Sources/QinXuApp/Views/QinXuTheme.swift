import SwiftUI

enum QinXuTheme {
    static let background = Color(red: 0.973, green: 0.969, blue: 0.953)
    static let paper = Color(red: 1, green: 0.996, blue: 0.980)
    static let navy = Color(red: 0.14, green: 0.18, blue: 0.16)
    static let ink = Color(red: 0.14, green: 0.18, blue: 0.16)
    static let muted = Color(red: 0.43, green: 0.47, blue: 0.43)
    static let teal = Color(red: 0.21, green: 0.33, blue: 0.26)
    static let line = Color(red: 0.90, green: 0.91, blue: 0.87)
    static let wrong = Color(red: 0.75, green: 0.23, blue: 0.18)
    static let amber = Color(red: 0.62, green: 0.40, blue: 0.10)
    static let accent = Color(red: 0.85, green: 0.29, blue: 0.20)
    static let softAccent = Color(red: 0.98, green: 0.91, blue: 0.87)
    static let sage = Color(red: 0.90, green: 0.93, blue: 0.87)
}

struct PracticeCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding)
            .background(QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(QinXuTheme.line, lineWidth: 1))
    }
}

struct QuietButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 13).padding(.vertical, 10)
            .foregroundStyle(prominent ? .white : QinXuTheme.ink)
            .background(prominent ? QinXuTheme.accent : QinXuTheme.paper, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(prominent ? .clear : QinXuTheme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct SectionEyebrow: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium))
            .tracking(1).foregroundStyle(QinXuTheme.muted)
    }
}

struct KeyboardBrandMark: View {
    var size: CGFloat = 30
    var body: some View {
        Canvas { context, bounds in
            let scale = bounds.width / 30
            var frame = Path(roundedRect: CGRect(x: 0.9 * scale, y: 0.9 * scale,
                width: 28.2 * scale, height: 28.2 * scale), cornerRadius: 4 * scale)
            context.stroke(frame, with: .color(QinXuTheme.teal), lineWidth: 1.6 * scale)
            for x in [10.0, 20.0] {
                frame = Path()
                frame.move(to: CGPoint(x: x * scale, y: 1.5 * scale))
                frame.addLine(to: CGPoint(x: x * scale, y: 29 * scale))
                context.stroke(frame, with: .color(QinXuTheme.teal), lineWidth: 1.2 * scale)
                context.fill(Path(roundedRect: CGRect(x: (x - 2.4) * scale, y: 1.1 * scale,
                    width: 4.8 * scale, height: 14.5 * scale), cornerRadius: scale), with: .color(QinXuTheme.teal))
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct QinXuWordmark: View {
    var compact = false
    var body: some View {
        HStack(spacing: 10) {
            KeyboardBrandMark(size: compact ? 25 : 30)
            if !compact {
                VStack(alignment: .leading, spacing: 5) {
                    Text("琴序").font(.system(size: 22, weight: .semibold)).tracking(1)
                    Text("QINXU").font(.system(size: 8, weight: .medium)).tracking(2)
                        .foregroundStyle(QinXuTheme.muted)
                }
            }
        }.foregroundStyle(QinXuTheme.ink)
    }
}
