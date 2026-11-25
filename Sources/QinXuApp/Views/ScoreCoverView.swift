import SwiftUI
import QinXuCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// A reusable cover surface. Its parent chooses the size; imported art is never cropped.
struct ScoreCoverView: View {
    let score: PianoScore
    let imageData: Data?

    private var palette: ScoreCoverPalette {
        let seed = score.id.unicodeScalars.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1.value) }
        return ScoreCoverPalette.all[Int(seed % UInt64(ScoreCoverPalette.all.count))]
    }

    private var artwork: Image? {
        guard let imageData else { return nil }
        #if os(iOS)
        guard let image = UIImage(data: imageData) else { return nil }
        return Image(uiImage: image)
        #elseif os(macOS)
        guard let image = NSImage(data: imageData) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                palette.paper
                if let artwork {
                    artwork.resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    fallback(size: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                Rectangle().fill(palette.ink.opacity(0.10)).frame(width: 1)
                    .padding(.leading, 4)
            }
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(QinXuTheme.ink.opacity(0.045), lineWidth: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.title + "封面")
    }

    private func fallback(size: CGSize) -> some View {
        let small = size.width < 100
        return ZStack(alignment: .topLeading) {
            // Draw the cropped ornament within the cover's bounds. An offset
            // Circle view enlarged the button's accessibility frame beyond its
            // visible cover, putting its activation point over quick practice.
            Canvas { context, _ in
                let circle = CGRect(x: size.width * 0.35, y: size.height * 0.59,
                                    width: size.width * 1.02, height: size.width * 1.02)
                context.fill(Path(ellipseIn: circle), with: .color(palette.ink.opacity(0.10)))
                context.stroke(Path(ellipseIn: circle.insetBy(dx: 14, dy: 14)),
                               with: .color(palette.ink.opacity(0.16)), lineWidth: 0.7)
            }.frame(width: size.width, height: size.height).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: small ? 5 : 8) {
                Text(score.title.components(separatedBy: " · ").first ?? score.title)
                    .font(.system(size: small ? 15 : 19, weight: .medium, design: .serif))
                    .lineLimit(3)
                if let subtitle = score.title.components(separatedBy: " · ").dropFirst().first {
                    Text(subtitle).font(.system(size: small ? 8 : 10)).lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "music.note").font(.system(size: small ? 11 : 15))
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, small ? 9 : 12)
            .padding(.vertical, small ? 11 : 15)
        }
    }
}

private struct ScoreCoverPalette {
    let paper: Color
    let ink: Color

    static let all: [ScoreCoverPalette] = [
        .init(paper: Color(red: 0.87, green: 0.90, blue: 0.87), ink: Color(red: 0.20, green: 0.30, blue: 0.27)),
        .init(paper: Color(red: 0.94, green: 0.89, blue: 0.84), ink: Color(red: 0.46, green: 0.33, blue: 0.27)),
        .init(paper: Color(red: 0.91, green: 0.86, blue: 0.66), ink: Color(red: 0.40, green: 0.36, blue: 0.15)),
        .init(paper: Color(red: 0.86, green: 0.90, blue: 0.92), ink: Color(red: 0.27, green: 0.35, blue: 0.42)),
        .init(paper: Color(red: 0.94, green: 0.81, blue: 0.75), ink: Color(red: 0.55, green: 0.31, blue: 0.23)),
        .init(paper: Color(red: 0.87, green: 0.87, blue: 0.82), ink: Color(red: 0.35, green: 0.38, blue: 0.31))
    ]
}
