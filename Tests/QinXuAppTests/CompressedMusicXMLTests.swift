import Foundation
import Testing
import zlib
import QinXuCore
@testable import QinXuApp

@Suite struct CompressedMusicXMLTests {
    private let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="4.0"><work><work-title>压缩曲谱</work-title></work>
    <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
    <part id="P1"><measure number="1"><attributes><divisions>1</divisions>
    <time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef>
    </attributes><note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration><type>whole</type></note>
    </measure></part></score-partwise>
    """

    private func manifest(_ path: String = "scores/piano.musicxml") -> String {
        "<container><rootfiles><rootfile full-path=\"\(path)\" media-type=\"application/vnd.recordare.musicxml+xml\"/></rootfiles></container>"
    }
    private func entries() -> [ZIPFixture.Entry] {
        [.init("META-INF/container.xml", Data(manifest().utf8)), .init("scores/piano.musicxml", Data(xml.utf8))]
    }
    private func rejected(_ action: () throws -> Void) {
        do { try action(); Issue.record("Expected import rejection") } catch { }
    }

    @Test(arguments: [false, true]) func storedAndDeflatedMXLKeepScoreSemantics(deflated: Bool) throws {
        var files = entries()
        if deflated { files = files.map { var entry = $0; entry.deflated = true; return entry } }
        let extracted = try CompressedMusicXML.scoreData(from: ZIPFixture.archive(files))
        #expect(extracted == Data(xml.utf8))
        let score = try MusicXMLParser().parse(data: extracted)
        #expect(score.title == "压缩曲谱")
        #expect(score.notes.count == 1)
        #expect(score.notes[0].midi == 60 && score.notes[0].durationBeats == 4)
    }

    @Test func firstDeclaredRootWinsAndOldContainerWithoutMimetypeWorks() throws {
        let manifest = "<container xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"scores/piano.musicxml\"/><rootfile full-path=\"other.xml\"/></rootfiles></container>"
        var files = entries(); files[0].data = Data(manifest.utf8)
        files.append(.init("other.xml", Data("wrong root".utf8)))
        #expect(try CompressedMusicXML.scoreData(from: ZIPFixture.archive(files)) == Data(xml.utf8))
        files.insert(.init("mimetype", Data("application/vnd.recordare.musicxml".utf8)), at: 0)
        #expect(try CompressedMusicXML.scoreData(from: ZIPFixture.archive(files)) == Data(xml.utf8))
        files[0].data = Data("application/zip".utf8)
        rejected { _ = try CompressedMusicXML.scoreData(from: ZIPFixture.archive(files)) }
    }

    @Test(arguments: ["../outside.xml", "/absolute.xml", "C:/score.xml", "scores\\file.xml", "scores//file.xml", "scores/./file.xml"])
    func unsafeArchivePathsAreRejected(path: String) throws {
        var files = entries(); files.append(.init(path, Data()))
        rejected { _ = try CompressedMusicXML.scoreData(from: ZIPFixture.archive(files)) }
    }

    @Test func duplicateEncryptedAndSymlinkEntriesAreRejected() throws {
        var files = entries(); files.append(files[1])
        rejected { _ = try CompressedMusicXML.scoreData(from: ZIPFixture.archive(files)) }
        files = entries(); files[1].flags = 1
        rejected { _ = try CompressedMusicXML.scoreData(from: ZIPFixture.archive(files)) }
        files = entries(); files[1].externalAttributes = 0xa000 << 16
        rejected { _ = try CompressedMusicXML.scoreData(from: ZIPFixture.archive(files)) }
    }

    @Test func checksumTruncationAndLocalHeaderMismatchAreRejected() throws {
        var files = entries(); files[1].crcOverride = 0
        rejected { _ = try CompressedMusicXML.scoreData(from: ZIPFixture.archive(files)) }
        let archive = try ZIPFixture.archive(entries())
        for length in [0, 4, 21, archive.count / 2, archive.count - 1] {
            rejected { _ = try CompressedMusicXML.scoreData(from: Data(archive.prefix(length))) }
        }
        var badLocal = archive
        badLocal[8] = 8 // Directory says stored; first local header now says DEFLATE.
        rejected { _ = try CompressedMusicXML.scoreData(from: badLocal) }
        var badDirectory = archive
        badDirectory.replaceSubrange((archive.count - 6)..<(archive.count - 2), with: [255, 255, 255, 255])
        rejected { _ = try CompressedMusicXML.scoreData(from: badDirectory) }
    }

    @Test func expandedSizeLimitsAndUndeclaredDeflateOutputAreRejected() throws {
        var files = entries(); files[1].expandedOverride = UInt32(CompressedMusicXML.maximumXMLBytes + 1)
        rejected { _ = try CompressedMusicXML.scoreData(from: ZIPFixture.archive(files)) }
        files = entries(); files[1].deflated = true; files[1].expandedOverride = 10
        rejected { _ = try CompressedMusicXML.scoreData(from: ZIPFixture.archive(files)) }
        files = entries(); files[0].expandedOverride = 65_537
        rejected { _ = try CompressedMusicXML.scoreData(from: ZIPFixture.archive(files)) }
    }

    @Test func containerEntitiesMissingRootAndWrongMediaTypeAreRejected() throws {
        for manifest in ["<!DOCTYPE container [<!ENTITY x SYSTEM 'file:///etc/passwd'>]>" + self.manifest(),
                         "<container><rootfiles/></container>",
                         self.manifest("missing.xml"),
                         self.manifest().replacingOccurrences(of: "application/vnd.recordare.musicxml+xml", with: "application/pdf")] {
            var files = entries(); files[0].data = Data(manifest.utf8)
            rejected { _ = try CompressedMusicXML.scoreData(from: ZIPFixture.archive(files)) }
        }
    }

    @Test @MainActor func modelImportsMXLAndRejectsUnsupportedMusicalContentWithoutReplacingLibrary() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("练习.MXL"), library = folder.appendingPathComponent("library.json")
        try ZIPFixture.archive(entries()).write(to: source)
        let model = PracticeViewModel(storage: LocalLibraryStore(url: library), automaticTimer: false, deviceAccessEnabled: false)
        model.importScore(from: source)
        #expect(model.errorMessage == nil)
        #expect(model.selectedScore.title == "压缩曲谱")
        let before = try Data(contentsOf: library), selected = model.selectedScoreID, count = model.scores.count
        var files = entries()
        files[1].data = Data(xml.replacingOccurrences(of: "<duration>4</duration>", with: "<duration>4</duration><grace/>").utf8)
        try ZIPFixture.archive(files).write(to: source)
        model.importScore(from: source)
        #expect(model.errorMessage != nil)
        #expect(model.selectedScoreID == selected && model.scores.count == count)
        #expect(try Data(contentsOf: library) == before)
    }
}

/// Small ZIP producer kept in tests: real raw DEFLATE, CRC32 and central headers.
/// Malformed fixtures intentionally vary metadata without invoking the reader.
private enum ZIPFixture {
    struct Entry {
        var path: String
        var data: Data
        var deflated = false
        var flags: UInt16 = 0
        var externalAttributes: UInt32 = 0
        var expandedOverride: UInt32?
        var crcOverride: UInt32?
        init(_ path: String, _ data: Data) { self.path = path; self.data = data }
    }
    static func archive(_ entries: [Entry]) throws -> Data {
        var local = Data(), central = Data()
        for entry in entries {
            let name = Data(entry.path.utf8), payload = entry.deflated ? try deflate(entry.data) : entry.data
            let crc = entry.crcOverride ?? entry.data.withUnsafeBytes { UInt32(truncatingIfNeeded: crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt($0.count))) }
            let expanded = entry.expandedOverride ?? UInt32(entry.data.count), offset = UInt32(local.count)
            local.u32(0x04034b50); local.u16(20); local.u16(entry.flags); local.u16(entry.deflated ? 8 : 0)
            local.u16(0); local.u16(0); local.u32(crc); local.u32(UInt32(payload.count)); local.u32(expanded)
            local.u16(UInt16(name.count)); local.u16(0); local.append(name); local.append(payload)
            central.u32(0x02014b50); central.u16(0x0314); central.u16(20); central.u16(entry.flags); central.u16(entry.deflated ? 8 : 0)
            central.u16(0); central.u16(0); central.u32(crc); central.u32(UInt32(payload.count)); central.u32(expanded)
            central.u16(UInt16(name.count)); central.u16(0); central.u16(0); central.u16(0); central.u16(0)
            central.u32(entry.externalAttributes); central.u32(offset); central.append(name)
        }
        let centralOffset = UInt32(local.count)
        local.append(central); local.u32(0x06054b50); local.u16(0); local.u16(0)
        local.u16(UInt16(entries.count)); local.u16(UInt16(entries.count)); local.u32(UInt32(central.count)); local.u32(centralOffset); local.u16(0)
        return local
    }
    private static func deflate(_ data: Data) throws -> Data {
        var stream = z_stream()
        #expect(deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY,
                            ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK)
        defer { deflateEnd(&stream) }
        var output = [UInt8](repeating: 0, count: Int(compressBound(uLong(data.count))) + 16)
        let result = data.withUnsafeBytes { input in output.withUnsafeMutableBufferPointer { buffer in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(input.count); stream.next_out = buffer.baseAddress; stream.avail_out = uInt(buffer.count)
            return zlib.deflate(&stream, Z_FINISH)
        } }
        try #require(result == Z_STREAM_END)
        return Data(output.prefix(Int(stream.total_out)))
    }
}

private extension Data {
    mutating func u16(_ value: UInt16) { append(contentsOf: [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]) }
    mutating func u32(_ value: UInt32) { u16(UInt16(truncatingIfNeeded: value)); u16(UInt16(truncatingIfNeeded: value >> 16)) }
}
