import Foundation
import Testing
import ImageIO
import UniformTypeIdentifiers
import QinXuCore
@testable import QinXuApp

@Suite @MainActor struct ScorePresentationStoreTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("qinxu-presentation-\(UUID().uuidString)", isDirectory: true)
    }

    private func imageData(width: Int = 80, height: Int = 120, type: UTType = .png) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func assertThrows(_ operation: () throws -> Void) {
        do { try operation(); Issue.record("Expected operation to fail") }
        catch { }
    }

    private func model(in directory: URL) -> PracticeViewModel {
        PracticeViewModel(storage: LocalLibraryStore(url: directory.appendingPathComponent("library.json")),
                          automaticTimer: false, deviceAccessEnabled: false)
    }

    @Test func imageImportDownsamplesBeforePersistenceAndKeepsAspectRatio() throws {
        let normalized = try ScorePresentationStore.normalizedCover(data: imageData(width: 2048, height: 1024))
        let source = try #require(CGImageSourceCreateWithData(normalized as CFData, nil))
        #expect((CGImageSourceGetType(source) as String?) == UTType.jpeg.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 512 && image.height == 256)
        #expect(normalized.count < 512 * 1024)
    }

    @Test func malformedOversizedAndUnsupportedImagesAreRejected() throws {
        assertThrows { _ = try ScorePresentationStore.normalizedCover(data: Data("not an image".utf8)) }
        assertThrows { _ = try ScorePresentationStore.normalizedCover(data: Data(repeating: 0, count: ScorePresentationStore.maximumImportBytes + 1)) }
        let tiff = try imageData(type: .tiff)
        assertThrows { _ = try ScorePresentationStore.normalizedCover(data: tiff) }
    }

    @Test func sourceFileLimitAppliesBeforeReadAndTypeComesFromBytes() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let large = folder.appendingPathComponent("oversized.jpg")
        try Data(repeating: 0, count: ScorePresentationStore.maximumImportBytes + 1).write(to: large)
        assertThrows { _ = try ScorePresentationStore.normalizedCover(from: large) }
        let wrongType = folder.appendingPathComponent("looks-like-jpeg.jpg")
        try imageData(type: .tiff).write(to: wrongType)
        assertThrows { _ = try ScorePresentationStore.normalizedCover(from: wrongType) }
        let noExtension = folder.appendingPathComponent("cover")
        try imageData().write(to: noExtension)
        #expect(!(try ScorePresentationStore.normalizedCover(from: noExtension)).isEmpty)
    }

    @Test func storeRoundTripKeepsFavoritesCoversAndCoreLibrarySeparate() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let library = folder.appendingPathComponent("library.json")
        let originalCoreData = Data("core library belongs to QinXuCore".utf8)
        try originalCoreData.write(to: library)
        let store = ScorePresentationStore(libraryURL: library)
        let cover = try ScorePresentationStore.normalizedCover(data: imageData())
        let snapshot = ScorePresentationStore.Snapshot(favoriteScoreIDs: ["score-1", "score-2"], scoreCoverData: ["score-1": cover])
        try store.save(snapshot)
        let loaded = store.load()
        #expect(loaded.error == nil && loaded.snapshot == snapshot)
        #expect(try Data(contentsOf: library) == originalCoreData)
        #expect(store.url.deletingLastPathComponent() == folder)
        #expect(store.url.lastPathComponent == "library.presentation.json")
    }

    @Test(arguments: ["not valid JSON", #"{"version":42,"favoriteScoreIDs":["future-score"],"scoreCoverData":{}}"#])
    func unsupportedOrDamagedStoreIsPreservedBeforeReplacing(original: String) throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = ScorePresentationStore(libraryURL: folder.appendingPathComponent("library.json"))
        let originalData = Data(original.utf8)
        try originalData.write(to: store.url)
        #expect(store.load().error != nil)
        #expect(try Data(contentsOf: store.url) == originalData)
        try store.save(.init(favoriteScoreIDs: ["new-score"]))
        let recoveries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("presentation-recovery-") }
        #expect(recoveries.count == 1)
        #expect(try Data(contentsOf: #require(recoveries.first)) == originalData)
        #expect(store.load().snapshot.favoriteScoreIDs == ["new-score"])
        #expect(store.load().error == nil)
    }

    @Test func invalidReplacementCannotOverwriteValidStore() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScorePresentationStore(libraryURL: folder.appendingPathComponent("library.json"))
        try store.save(.init(favoriteScoreIDs: ["keep"]))
        let before = try Data(contentsOf: store.url)
        assertThrows { try store.save(.init(scoreCoverData: ["broken": Data("invalid image".utf8)])) }
        #expect(try Data(contentsOf: store.url) == before)
        #expect(store.load().snapshot.favoriteScoreIDs == ["keep"])
    }

    @Test func modelPersistsPresentationWithoutSelectingScoreOrStartingPlayback() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = model(in: folder)
        let selected = first.selectedScoreID
        first.toggleFavorite(selected)
        let image = folder.appendingPathComponent("cover.png")
        try imageData().write(to: image)
        first.importCover(from: image, for: selected)
        #expect(first.errorMessage == nil)
        #expect(first.favoriteScoreIDs == [selected])
        #expect(first.scoreCoverData[selected] != nil && !first.isPlaying)
        let restored = model(in: folder)
        #expect(restored.favoriteScoreIDs == first.favoriteScoreIDs)
        #expect(restored.scoreCoverData == first.scoreCoverData)
        #expect(restored.selectedScoreID == selected)
        restored.removeCover(for: selected)
        let afterRemoval = model(in: folder)
        #expect(afterRemoval.scoreCoverData.isEmpty)
        #expect(afterRemoval.favoriteScoreIDs == [selected])
        afterRemoval.toggleFavorite(selected)
        #expect(model(in: folder).favoriteScoreIDs.isEmpty)
    }

    @Test func rejectedCoverReplacementKeepsStoredAndPublishedCover() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let first = model(in: folder), image = folder.appendingPathComponent("cover.png")
        try imageData().write(to: image)
        first.importCover(from: image, for: first.selectedScoreID)
        let before = first.scoreCoverData
        try Data("damaged".utf8).write(to: image)
        first.importCover(from: image, for: first.selectedScoreID)
        #expect(first.errorMessage != nil)
        #expect(first.scoreCoverData == before)
        #expect(model(in: folder).scoreCoverData == before)
        first.toggleFavorite("unknown-score")
        first.removeCover(for: "unknown-score")
        #expect(first.favoriteScoreIDs.isEmpty && first.scoreCoverData == before)
    }

    @Test func writeFailureKeepsModelStateAndOriginalSidecar() throws {
        let folder = directory(), moved = directory()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: moved)
        }
        let first = model(in: folder), selected = first.selectedScoreID
        first.toggleFavorite(selected)
        let image = folder.appendingPathComponent("cover.png")
        try imageData().write(to: image)
        first.importCover(from: image, for: selected)
        let coverBefore = first.scoreCoverData
        let sidecar = ScorePresentationStore(libraryURL: folder.appendingPathComponent("library.json")).url
        let bytesBefore = try Data(contentsOf: sidecar)
        try FileManager.default.moveItem(at: folder, to: moved)
        // A file in the parent-directory location reliably blocks saving, even under root.
        try Data("keep this blocker".utf8).write(to: folder)
        first.toggleFavorite(selected)
        first.removeCover(for: selected)
        #expect(first.errorMessage?.contains("保存收藏与封面失败") == true)
        #expect(first.favoriteScoreIDs == [selected] && first.scoreCoverData == coverBefore)
        #expect(try Data(contentsOf: moved.appendingPathComponent(sidecar.lastPathComponent)) == bytesBefore)
        #expect(try String(contentsOf: folder, encoding: .utf8) == "keep this blocker")
    }
}
