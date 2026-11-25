import Foundation
import SwiftUI
import Testing
import ImageIO
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif
import QinXuCore
@testable import QinXuApp

#if os(macOS)
/// In-memory SwiftUI rendering; this does not capture the user's desktop or test iOS interaction.
@Suite @MainActor struct PracticeRenderingTests {
    @Test(arguments: [393, 834, 1194])
    func homeRendersAtPhoneAndTabletSizes(width: Int) throws {
        let height = width == 393 ? 852 : width == 834 ? 1194 : 834
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = PracticeViewModel(storage: LocalLibraryStore(url: directory.appendingPathComponent("library.json")),
                                      automaticTimer: false, deviceAccessEnabled: false)
        let view = PracticeHomeView(model: model)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .frame(width: CGFloat(width), height: CGFloat(height))
        try render(view, name: "home-\(width)", width: width, height: height)
    }

    @Test(arguments: [393, 834, 1194])
    func scoreRendersAtPhoneAndTabletWidths(width: Int) throws {
        let score = DemoScores.all[1]
        let view = PracticeScoreView(score: score, hand: .both, currentBeat: 0,
                                    expectedNotes: Array(score.notes.prefix(3)), verdicts: [:], active: true)
            .frame(width: CGFloat(width), height: 340)
            .background(QinXuTheme.paper)
        try render(view, name: "score-\(width)", width: width, height: 340)
    }

    @Test(arguments: [393, 834, 1194])
    func keyboardRendersExpectedAndHeldNotes(width: Int) throws {
        let view = PianoKeyboardView(expectedPitches: [60, 64, 67], heldPitches: [64],
                                     hand: .both, interactive: true, press: { _ in }, release: { _ in })
            .frame(width: CGFloat(width), height: 124)
            .background(QinXuTheme.paper)
        try render(view, name: "keyboard-\(width)", width: width, height: 124)
    }

    private func render<V: View>(_ view: V, name: String, width: Int, height: Int) throws {
        // ImageRenderer excludes native ScrollView content. Render our own in-memory view instead.
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = try #require(bitmap.cgImage)
        #expect(image.width >= width)
        #expect(image.width % width == 0)
        #expect(image.height * width == image.width * height)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: width, height: height,
                                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var darkPixels = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let darkRGB = pixels[index] < UInt8(160) && pixels[index + 1] < UInt8(180) && pixels[index + 2] < UInt8(180)
            if darkRGB && pixels[index + 3] > UInt8(200) { darkPixels += 1 }
        }
        // Catches views that render a blank frame because scroll/Canvas layout collapsed.
        #expect(darkPixels > 100)

        if let output = ProcessInfo.processInfo.environment["QINXU_PREVIEW_DIR"] {
            let folder = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name + ".png")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
        }
    }
}

#endif
