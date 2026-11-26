import Foundation
import Testing
import QinXuCore
@testable import QinXuApp

@Suite struct PDFScoreMXLArchiveTests {
    private let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="4.0"><work><work-title>识谱输出测试</work-title></work>
    <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
    <part id="P1"><measure number="1"><attributes><divisions>4</divisions>
    <time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves>
    <clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef>
    </attributes>
    <note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>6</duration><type>quarter</type><dot/><staff>1</staff></note>
    <note><rest/><duration>10</duration><staff>1</staff></note>
    <backup><duration>16</duration></backup>
    <note><pitch><step>C</step><octave>3</octave></pitch><duration>16</duration><type>whole</type><staff>2</staff></note>
    </measure></part></score-partwise>
    """

    @Test func roundTripKeepsExactXMLAndStrictlyParsedPitchTimeAndHands() throws {
        let original = Data(xml.utf8)
        let archive = try PDFScoreMXLArchive.make(musicXML: original)
        let extracted = try CompressedMusicXML.scoreData(from: archive)
        #expect(extracted == original)
        #expect(archive == (try PDFScoreMXLArchive.make(musicXML: original)))
        let score = try MusicXMLParser().parse(data: extracted)
        #expect(score.title == "识谱输出测试")
        #expect(score.notes.count == 2)
        let right = try #require(score.notes.first(where: { $0.staff == 1 }))
        let left = try #require(score.notes.first(where: { $0.staff == 2 }))
        #expect(right.midi == 66 && right.startBeat == 0 && right.durationBeats == 1.5)
        #expect(left.midi == 48 && left.startBeat == 0 && left.durationBeats == 4)
    }

    @Test func mimetypeIsFirstStoredEntryWithoutExtraFieldOrUserMetadata() throws {
        let bytes = [UInt8](try PDFScoreMXLArchive.make(musicXML: Data(xml.utf8)))
        func word(_ index: Int) -> UInt16 { UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8 }
        #expect(Array(bytes.prefix(4)) == [0x50, 0x4b, 0x03, 0x04])
        #expect(word(8) == 0 && word(28) == 0)
        #expect(word(10) == 0 && word(12) == 0x21)
        let nameLength = Int(word(26))
        #expect(String(bytes: bytes[30..<(30 + nameLength)], encoding: .utf8) == "mimetype")
        let mime = Data("application/vnd.recordare.musicxml".utf8)
        #expect(Data(bytes[(30 + nameLength)..<(30 + nameLength + mime.count)]) == mime)
    }

    @Test func emptyAndOversizedDocumentsAreRejected() {
        for bytes in [Data(), Data(repeating: 0, count: CompressedMusicXML.maximumXMLBytes + 1)] {
            do { _ = try PDFScoreMXLArchive.make(musicXML: bytes); Issue.record("Expected export size rejection") }
            catch { }
        }
    }

    @Test func packagingDoesNotSilentlyRemoveUnsupportedMusicalConstructs() throws {
        let unsupported = Data(xml.replacingOccurrences(of: "</measure>", with: "<barline><repeat direction=\"backward\"/></barline></measure>").utf8)
        let extracted = try CompressedMusicXML.scoreData(from: PDFScoreMXLArchive.make(musicXML: unsupported))
        #expect(extracted == unsupported)
        do { _ = try MusicXMLParser().parse(data: extracted); Issue.record("Strict import must still reject repeats") }
        catch { }
    }
}
