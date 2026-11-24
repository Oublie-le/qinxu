import Foundation
import Testing
@testable import PianoCore

@Suite struct MusicXMLParserTests {
    private let parser = MusicXMLParser()
    private let attributes = "<attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves><clef number=\"1\"><sign>G</sign><line>2</line></clef><clef number=\"2\"><sign>F</sign><line>4</line></clef></attributes>"
    private func document(_ measures: String, title: String = "测试曲") -> String {
        "<score-partwise version=\"4.0\"><work><work-title>\(title)</work-title></work><identification><creator type=\"composer\">练习作者</creator></identification><part-list><score-part id=\"P1\"><part-name>Piano</part-name></score-part></part-list><part id=\"P1\">\(measures)</part></score-partwise>"
    }
    private func parse(_ text: String) throws -> PianoScore { try parser.parse(data: Data(text.utf8)) }
    private func note(_ step: String = "C", duration: String = "1", octave: Int = 4, alter: String? = nil, staff: Int = 1, voice: String = "1", extra: String = "", chord: Bool = false) -> String {
        "<note>\(chord ? "<chord/>" : "")<pitch><step>\(step)</step>\(alter.map { "<alter>\($0)</alter>" } ?? "")<octave>\(octave)</octave></pitch><duration>\(duration)</duration><voice>\(voice)</voice><staff>\(staff)</staff>\(extra)</note>"
    }
    private func rest(_ duration: String) -> String { "<note><rest/><duration>\(duration)</duration></note>" }
    private func rejects(_ xml: String, containing: String, file: StaticString = #filePath, line: UInt = #line) {
        expectThrows(try parse(xml), file: file, line: line) { error in
            expectTrue(error.localizedDescription.contains(containing), "Unexpected error: \(error)", file: file, line: line)
        }
    }

    @Test func testChordBackupAndGrandStaffUseSharedTimeline() throws {
        let xml = document("<measure number=\"1\">\(attributes)\(note())\(note("E", chord: true))\(note("D", duration: "2"))\(rest("1"))<backup><duration>4</duration></backup>\(note(duration: "4", octave: 3, staff: 2, voice: "2"))</measure>")
        let score = try parse(xml)
        expectEqual(score.title, "测试曲")
        expectEqual(score.composer, "练习作者")
        expectEqual(score.notes.map(\.midi), [60, 64, 48, 62])
        expectEqual(score.notes.map(\.startBeat), [0, 0, 0, 1])
        expectEqual(score.notes.map(\.durationBeats), [1, 1, 4, 2])
        expectEqual(score.notes.map(\.staff), [1, 1, 2, 1])
        expectEqual(score.durationBeats, 4)
    }

    @Test func testForwardCreatesGapInsteadOfFakeRestNote() throws {
        let xml = document("<measure number=\"1\">\(attributes)\(note())<forward><duration>1</duration></forward>\(note("D", duration: "2"))</measure>")
        let score = try parse(xml)
        expectEqual(score.notes.map(\.startBeat), [0, 2])
        expectEqual(score.notes.count, 2)
        expectEqual(score.measures[0].durationBeats, 4)
    }

    @Test func testPickupOffsetsFollowingMeasureAndNormalizesMeasureNumbers() throws {
        let xml = document("<measure number=\"0\" implicit=\"yes\">\(attributes)\(note("G"))</measure><measure number=\"1\">\(note(duration: "4"))</measure>")
        let score = try parse(xml)
        expectEqual(score.measures.map(\.number), [1, 2])
        expectEqual(score.measures.map(\.startBeat), [0, 1])
        expectEqual(score.measures.map(\.durationBeats), [1, 4])
        expectEqual(score.notes.map(\.measure), [1, 2])
        expectEqual(score.notes[1].startBeat, 1)
    }

    @Test func testTiesMergeAcrossMeasuresWithoutExtraAttack() throws {
        let xml = document("<measure number=\"1\">\(attributes)\(note(duration: "4", extra: "<tie type=\"start\"/>"))</measure><measure number=\"2\">\(note(extra: "<tie type=\"stop\"/><tie type=\"start\"/>"))\(note(duration: "3", extra: "<tie type=\"stop\"/>"))</measure>")
        let score = try parse(xml)
        expectEqual(score.notes.count, 1)
        expectEqual(score.notes[0].durationBeats, 8)
        expectEqual(score.notes[0].measure, 1)
        expectEqual(score.measures.count, 2)
    }

    @Test func testTieRequiresMatchingVoiceAndContiguousTime() {
        let start = "<measure number=\"1\">\(attributes)\(note(duration: "4", extra: "<tie type=\"start\"/>"))</measure>"
        rejects(document(start + "<measure number=\"2\">\(note(duration: "4", voice: "2", extra: "<tie type=\"stop\"/>"))</measure>"), containing: "同声部")
        rejects(document(start + "<measure number=\"2\">\(rest("1"))\(note(duration: "3", extra: "<tie type=\"stop\"/>"))</measure>"), containing: "连续")
        rejects(document(start), containing: "未结束")
    }

    @Test func testTieRequiresMatchingStaff() {
        let xml = document("<measure number=\"1\">\(attributes)\(note(duration: "4", extra: "<tie type=\"start\"/>"))</measure><measure number=\"2\">\(note(duration: "4", staff: 2, extra: "<tie type=\"stop\"/>"))</measure>")
        rejects(xml, containing: "同谱表")
    }

    @Test func testKeySignatureDoesNotSubstituteForExplicitPitchAlter() throws {
        let a = attributes.replacingOccurrences(of: "</attributes>", with: "<key><fifths>1</fifths></key></attributes>")
        let score = try parse(document("<measure number=\"1\">\(a)\(note("F"))\(note("F", alter: "1"))\(note("F", alter: "0"))\(rest("1"))</measure>"))
        expectEqual(score.notes.map(\.midi), [65, 66, 65])
        expectEqual(score.notes.map(\.alter), [0, 1, 0])
    }

    @Test func testTripletsAndFractionalDivisionsUseActualDurations() throws {
        let a = attributes.replacingOccurrences(of: "<divisions>1</divisions>", with: "<divisions>1.5</divisions>")
        let triplet = "<time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>"
        let xml = document("<measure number=\"1\">\(a)\(note(duration: "0.5", extra: triplet))\(note("D", duration: "0.5", extra: triplet))\(note("E", duration: "0.5", extra: triplet))\(rest("4.5"))</measure>")
        let score = try parse(xml)
        expectEqual(score.notes[0].durationBeats, 1.0 / 3, accuracy: 0.000_001)
        expectEqual(score.notes[2].startBeat, 2.0 / 3, accuracy: 0.000_001)
        expectEqual(score.durationBeats, 4, accuracy: 0.000_001)
    }

    @Test func testDottedMetronomeTempoNormalizesToQuarterNotes() throws {
        let a = attributes.replacingOccurrences(of: "<beats>4</beats><beat-type>4</beat-type>", with: "<beats>6</beats><beat-type>8</beat-type>")
        let direction = "<direction><direction-type><metronome><beat-unit>quarter</beat-unit><beat-unit-dot/><per-minute>100</per-minute></metronome></direction-type><sound tempo=\"150\"/></direction>"
        let score = try parse(document("<measure number=\"1\">\(a)\(direction)\(note(duration: "3"))</measure>"))
        expectEqual(score.tempoBPM, 150)
        expectEqual(score.beatsPerMeasure, 6)
        expectEqual(score.beatUnit, 8)
        expectEqual(score.durationBeats, 3)
    }

    @Test func testTempoMismatchAndLaterChangesAreRejected() {
        let direction = "<direction><direction-type><metronome><beat-unit>half</beat-unit><per-minute>60</per-minute></metronome></direction-type><sound tempo=\"60\"/></direction>"
        rejects(document("<measure number=\"1\">\(attributes)\(direction)\(note(duration: "4"))</measure>"), containing: "速度不一致")
        rejects(document("<measure number=\"1\">\(attributes)<sound tempo=\"80\"/>\(note(duration: "4"))</measure><measure number=\"2\"><sound tempo=\"90\"/>\(note(duration: "4"))</measure>"), containing: "曲中变速")
    }

    @Test func testInvalidTimelineIsRejected() {
        rejects(document("<measure number=\"1\">\(attributes)<backup><duration>1</duration></backup>\(note(duration: "4"))</measure>"), containing: "超出了小节范围")
        rejects(document("<measure number=\"1\">\(attributes)\(note(duration: "5"))</measure>"), containing: "时值超过拍号")
        rejects(document("<measure number=\"1\">\(attributes)\(note(chord: true))</measure>"), containing: "和弦缺少主音")
        rejects(document("<measure number=\"1\">\(attributes)\(note())</measure><measure number=\"2\">\(note())</measure><measure number=\"3\">\(note())</measure>"), containing: "时值不足")
    }

    @Test func testDuplicateSemanticFieldsAreRejected() {
        let duplicateDuration = note().replacingOccurrences(of: "</note>", with: "<duration>2</duration></note>")
        rejects(document("<measure number=\"1\">\(attributes)\(duplicateDuration)</measure>"), containing: "有且仅有一个")
        let duplicatePitch = note().replacingOccurrences(of: "</pitch>", with: "<step>D</step></pitch>")
        rejects(document("<measure number=\"1\">\(attributes)\(duplicatePitch)</measure>"), containing: "重复的 step")
    }

    @Test func testOfficialMusicXMLDeclarationIsSafelyStripped() throws {
        let declaration = "<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">"
        let body = document("<measure number=\"1\">\(attributes)\(note(duration: "4"))</measure>")
        let score = try parse("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + declaration + "\n" + body)
        expectEqual(score.notes.first?.midi, 60)
        expectEqual(score.durationBeats, 4)
    }

    @Test func testUnsafeAndUnknownDTDDeclarationsAreRejected() {
        let body = document("<measure number=\"1\">\(attributes)\(note(duration: "4"))</measure>")
        rejects("<!DOCTYPE score-partwise SYSTEM \"file:///etc/passwd\">" + body, containing: "DTD")
        rejects("<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"https://example.invalid/dtds/partwise.dtd\">" + body, containing: "非官方 DTD")
        rejects("<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\" [ <!ELEMENT score-partwise ANY> ]>" + body, containing: "内部 DTD")
    }

    @Test func testUnsafeXMLAndCompressedFilesAreRejected() {
        rejects("<!DOCTYPE score-partwise [<!ENTITY x SYSTEM 'file:///etc/passwd'>]>" + document(""), containing: "DTD")
        rejects("<score-partwise><part></score-partwise>", containing: "格式无效")
        expectThrows(try parser.parse(data: Data([0x50, 0x4B, 0x03, 0x04]))) { error in
            expectTrue(error.localizedDescription.contains(".mxl"))
        }
        expectThrows(try parser.parse(data: Data(repeating: 32, count: 5 * 1_024 * 1_024 + 1)))
    }

    @Test func testUnsupportedPlaybackSemanticsAreRejectedClearly() {
        for (construct, expected) in [
            ("<barline><repeat direction=\"backward\"/></barline>", "反复"),
            ("<attributes><transpose><chromatic>2</chromatic></transpose></attributes>", "移调"),
            ("<direction><direction-type><octave-shift type=\"up\"/></direction-type></direction>", "八度"),
            ("<direction><sound dacapo=\"yes\"/></direction>", "跳转")
        ] {
            rejects(document("<measure number=\"1\">\(attributes)\(construct)\(note(duration: "4"))</measure>"), containing: expected)
        }
        rejects(document("<measure number=\"1\">\(attributes)\(note(extra: "<grace/>"))</measure>"), containing: "倚音")
    }

    @Test func testTimeAndClefChangesCannotSilentlyChangeMeaning() {
        let xml = document("<measure number=\"1\">\(attributes)\(note(duration: "4"))</measure><measure number=\"2\"><attributes><time><beats>3</beats><beat-type>4</beat-type></time></attributes>\(note(duration: "3"))</measure>")
        rejects(xml, containing: "变拍号")
        let clef = attributes.replacingOccurrences(of: "<sign>G</sign><line>2</line>", with: "<sign>C</sign><line>3</line>")
        rejects(document("<measure number=\"1\">\(clef)\(note(duration: "4"))</measure>"), containing: "高音谱号")
    }

    @Test func testNonFiniteDurationsAndOutOfRangePitchAreRejected() {
        for invalid in ["0", "-1", "nan", "inf", "1e999"] {
            rejects(document("<measure number=\"1\">\(attributes)\(note(duration: invalid))</measure>"), containing: "时值")
        }
        rejects(document("<measure number=\"1\">\(attributes)\(note("G", duration: "4", octave: 9, alter: "1"))</measure>"), containing: "MIDI")
        rejects(document("<measure number=\"1\">\(attributes)\(note(alter: "0.5"))</measure>"), containing: "微分音")
    }

    @Test func testMultipleInstrumentsAndPartsAreRejected() {
        let first = document("<measure number=\"1\">\(attributes)\(note(duration: "4"))</measure>")
        let xml = first.replacingOccurrences(of: "</part-list>", with: "<score-part id=\"P2\"><part-name>Violin</part-name></score-part></part-list>")
            .replacingOccurrences(of: "</score-partwise>", with: "<part id=\"P2\"><measure number=\"1\"/></part></score-partwise>")
        rejects(xml, containing: "多乐器")
    }

    @Test func testStableImportedIdentifiersAndThreeOriginalFixturesRoundTrip() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Scores")
        expectEqual(DemoScores.all.map(\.id), ["demo-melody", "demo-chords", "demo-rhythm"])
        for demo in DemoScores.all {
            let data = try Data(contentsOf: directory.appendingPathComponent(demo.id + ".musicxml"))
            let imported = try parser.parse(data: data)
            expectEqual(imported.id, try parser.parse(data: data).id)
            expectEqual(imported.title, demo.title)
            expectEqual(imported.tempoBPM, demo.tempoBPM)
            expectEqual(imported.measures, demo.measures)
            expectEqual(imported.notes.count, demo.notes.count)
            for (lhs, rhs) in zip(imported.notes, demo.notes) {
                expectEqual(lhs.midi, rhs.midi)
                expectEqual(lhs.staff, rhs.staff)
                expectEqual(lhs.measure, rhs.measure)
                expectEqual(lhs.step, rhs.step)
                expectEqual(lhs.startBeat, rhs.startBeat, accuracy: 0.000_001)
                expectEqual(lhs.durationBeats, rhs.durationBeats, accuracy: 0.000_001)
            }
        }
    }
}
