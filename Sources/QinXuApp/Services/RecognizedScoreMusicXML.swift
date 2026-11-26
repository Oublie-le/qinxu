import Foundation
import SheetMusicCore

/// A bounded bridge for the recognized score, not another recognition pass.
/// Upstream durations already include dots/tuplets. Staff order, not clef, assigns the hands.
/// The caller must still run QinXuCore.MusicXMLParser and present the recognition diagnostics.
enum RecognizedScoreMusicXML {
    struct ConversionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let epsilon = 0.000_001
    private static func refuse(_ message: String) -> ConversionError {
        ConversionError(message: "识谱结果暂不能用于判音：" + message)
    }

    static func encode(_ score: SheetMusicCore.Score, title: String) throws -> Data {
        guard score.parts.count == 1, let part = score.parts.first,
              (1...2).contains(part.staves.count) else {
            throw refuse("需要一个钢琴声部及一至两个谱表，请先核对谱表分组。")
        }
        guard !part.instrument.useDrumset, !part.instrument.isTransposing,
              part.instrument.stringData == nil else { throw refuse("不支持打击乐、移调或弦乐指法谱。") }
        guard score.preservedMarkup.isEmpty, part.preservedMarkup.isEmpty,
              part.instrument.preservedMarkup.isEmpty else { throw refuse("曲谱含尚未解释的内容。") }
        let staves = Array(part.staves)
        let count = staves[0].measures.count
        guard (1...1_000).contains(count), score.systemMeasures.count <= count else {
            throw refuse("小节数量为空、过多，或系统标记与小节不对齐。")
        }
        for staff in staves {
            guard staff.group == "pitched", staff.lineCount == 5,
                  staff.measures.count == count, staff.preservedMarkup.isEmpty,
                  staff.staffTypePreservedMarkup.isEmpty else {
                throw refuse("需要小节一一对应的普通五线谱，不能省略某个谱表。")
            }
        }
        var clefs = try staves.map { try clef($0.defaultClefType ?? "G") }
        var meter = (beats: 4, unit: 4)
        var keys = [Int](repeating: 0, count: staves.count)
        let tempo = try initialTempo(score)
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><score-partwise version=\"4.0\">"
        xml += "<work><work-title>\(escape(String(title.prefix(200))))</work-title></work>"
        xml += "<part-list><score-part id=\"P1\"><part-name>钢琴</part-name></score-part></part-list><part id=\"P1\">"
        var noteCount = 0
        var elementCount = 0
        var start = 0.0
        var ties: [String: (number: Int, end: Double)] = [:]
        for index in 0..<count {
            let measures = staves.map { $0.measures[index] }
            var declarations: [(Int, Int)] = []
            for (staffIndex, measure) in measures.enumerated() {
                guard !measure.startRepeat, measure.endRepeatCount == nil,
                      measure.measureRepeatCount == nil, measure.markers.isEmpty,
                      measure.jumps.isEmpty, measure.preservedMarkup.isEmpty else {
                    throw refuse("第 \(index + 1) 小节含反复、跳转或未解释的标记。")
                }
                guard measure.voices.count <= 16 else { throw refuse("第 \(index + 1) 小节声部过多。") }
                var declaredClef: String?
                var declaredKey: Int?
                for voice in measure.voices {
                    var advanced = false
                    for element in voice.elements {
                        elementCount += 1
                        guard elementCount <= 50_000 else { throw refuse("曲谱元素超过处理上限。") }
                        switch element {
                        case .chord: advanced = true
                        case let .locationShift(delta):
                            if delta.numerator != 0 { advanced = true }
                        case let .clef(value):
                            let sign = try clef(value.concertClefType)
                            guard !advanced, value.transposingClefType == nil || value.transposingClefType == value.concertClefType,
                                  declaredClef == nil || declaredClef == sign else {
                                throw refuse("第 \(index + 1) 小节含中途、冲突或移调谱号。")
                            }
                            declaredClef = sign
                        case let .timeSignature(value):
                            guard !advanced, (1...32).contains(value.numerator),
                                  [1, 2, 4, 8, 16, 32].contains(value.denominator) else {
                                throw refuse("第 \(index + 1) 小节拍号无效或在小节中途改变。")
                            }
                            declarations.append((value.numerator, value.denominator))
                        case let .keySignature(value):
                            guard !advanced, (-7...7).contains(value.concertKey),
                                  declaredKey == nil || declaredKey == value.concertKey else {
                                throw refuse("第 \(index + 1) 小节调号无效、冲突或在小节中途改变。")
                            }
                            declaredKey = value.concertKey
                        default: break // Every other case is checked by encodeVoice below.
                        }
                    }
                }
                if let declaredClef { clefs[staffIndex] = declaredClef }
                if let declaredKey { keys[staffIndex] = declaredKey }
            }
            if let first = declarations.first {
                guard declarations.allSatisfy({ $0 == first }), index == 0 || first == (meter.beats, meter.unit) else {
                    throw refuse("不支持声部拍号冲突或曲中变拍号。")
                }
                meter = (first.0, first.1)
            }
            let nominal = Double(meter.beats) * 4 / Double(meter.unit)
            let lengths = try measures.map { try $0.actualLength.map { try quarterBeats($0) } ?? nominal }
            let length = lengths[0]
            guard length > 0, length <= nominal + epsilon,
                  lengths.allSatisfy({ abs($0 - length) <= epsilon }) else {
                throw refuse("第 \(index + 1) 小节的左右谱表时长不一致或超过拍号。")
            }
            let implicit = length < nominal - epsilon ? " implicit=\"yes\"" : ""
            xml += "<measure number=\"\(index + 1)\"\(implicit)><attributes><divisions>1</divisions>"
            for staff in staves.indices { xml += "<key number=\"\(staff + 1)\"><fifths>\(keys[staff])</fifths></key>" }
            xml += "<time><beats>\(meter.beats)</beats><beat-type>\(meter.unit)</beat-type></time><staves>\(staves.count)</staves>"
            for staff in staves.indices {
                xml += "<clef number=\"\(staff + 1)\"><sign>\(clefs[staff])</sign><line>\(clefs[staff] == "G" ? 2 : 4)</line></clef>"
            }
            xml += "</attributes>"
            if index == 0, let tempo {
                xml += "<direction><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>\(tempo)</per-minute></metronome></direction-type><sound tempo=\"\(tempo)\"/></direction>"
            }
            var cursor = 0.0
            for (staffIndex, measure) in measures.enumerated() {
                for (voiceIndex, voice) in measure.voices.enumerated() {
                    if cursor > epsilon { xml += movement("backup", cursor); cursor = 0 }
                    xml += try encodeVoice(voice, staff: staffIndex + 1, voiceIndex: voiceIndex + 1,
                                           length: length, start: start, measure: index + 1,
                                           cursor: &cursor, noteCount: &noteCount, ties: &ties)
                }
            }
            // An explicit measure length includes trailing silence, even when its final voice is shorter.
            if cursor < length - epsilon { xml += movement("forward", length - cursor) }
            xml += "</measure>"
            start += length
            guard start <= 64_000, xml.utf8.count <= 5_000_000 else { throw refuse("曲谱超过时长或文件大小限制。") }
        }
        guard noteCount > 0, ties.isEmpty else { throw refuse("曲谱没有音符，或有未结束的延音线。") }
        xml += "</part></score-partwise>"
        return Data(xml.utf8)
    }

    private static func encodeVoice(_ voice: Voice, staff: Int, voiceIndex: Int, length: Double,
                                    start: Double, measure: Int, cursor: inout Double, noteCount: inout Int,
                                    ties: inout [String: (number: Int, end: Double)]) throws -> String {
        var xml = ""
        for element in voice.elements {
            switch element {
            case let .chord(chord):
                guard chord.arpeggio == nil, chord.tremolo == nil, chord.ornaments.isEmpty,
                      chord.graceNotesBefore.isEmpty, chord.graceNotesAfter.isEmpty,
                      chord.chordLines.isEmpty, chord.staffMove == 0, !chord.isWrittenDoubled,
                      chord.preservedMarkup.isEmpty else {
                    throw refuse("第 \(measure) 小节含倚音、装饰音、震音、琶音、跨谱表或未解释的音符。")
                }
                for spanner in chord.spanners { try checkSpanner(spanner) }
                let duration: Double
                if case .measure = chord.duration {
                    guard chord.notes.isEmpty else { throw refuse("有音高音符不能使用整小节休止时值。") }
                    duration = length
                } else { duration = try quarterBeats(chord.duration.asFraction) }
                guard duration > 0, cursor + duration <= length + epsilon else {
                    throw refuse("第 \(measure) 小节的音符或休止符超出小节；不会自动缩短时值。")
                }
                let articulation = try articulationXML(chord.articulations)
                if chord.notes.isEmpty {
                    guard articulation.isEmpty else { throw refuse("休止符含未支持的奏法指示。") }
                    xml += "<note><rest/><duration>\(decimal(duration))</duration><voice>\(voiceIndex)</voice><staff>\(staff)</staff></note>"
                } else {
                    for (index, note) in chord.notes.enumerated() {
                        noteCount += 1
                        guard noteCount <= 20_000 else { throw refuse("音符超过 20000 个。") }
                        let pitch = try pitchXML(note)
                        let key = "\(staff):\(voiceIndex):\(note.pitch)"
                        if let back = note.tieBack {
                            guard back > 0, let open = ties[key], open.number == back,
                                  abs(open.end - start - cursor) <= epsilon else {
                                throw refuse("第 \(measure) 小节延音线没有同声部的连续起点。")
                            }
                            ties.removeValue(forKey: key)
                        } else if ties[key] != nil { throw refuse("第 \(measure) 小节延音线中断。") }
                        if let forward = note.tieForward {
                            guard forward > 0 else { throw refuse("延音线编号无效。") }
                            ties[key] = (forward, start + cursor + duration)
                        }
                        xml += "<note>\(index > 0 ? "<chord/>" : "")\(pitch)<duration>\(decimal(duration))</duration>"
                        var notation = ""
                        if note.tieBack != nil {
                            xml += "<tie type=\"stop\"/>"
                            notation += "<tied type=\"stop\"/>"
                        }
                        if note.tieForward != nil {
                            xml += "<tie type=\"start\"/>"
                            notation += "<tied type=\"start\"/>"
                        }
                        xml += "<voice>\(voiceIndex)</voice><staff>\(staff)</staff>"
                        notation += articulation
                        if !notation.isEmpty { xml += "<notations>\(notation)</notations>" }
                        xml += "</note>"
                    }
                }
                cursor += duration
            case let .locationShift(delta):
                let shift = try quarterBeats(delta, allowNegative: true)
                guard cursor + shift >= -epsilon, cursor + shift <= length + epsilon else {
                    throw refuse("第 \(measure) 小节的声部时间移动越界。")
                }
                if abs(shift) > epsilon { xml += movement(shift < 0 ? "backup" : "forward", abs(shift)) }
                cursor = max(0, cursor + shift)
            case .keySignature, .timeSignature, .clef: break // Validated and emitted at measure start.
            case .dynamic: break // The practice renderer explicitly warns that dynamics are simplified.
            case let .barLine(bar):
                guard [nil, "normal", "single", "double", "end"].contains(bar.subtype) else {
                    throw refuse("第 \(measure) 小节含反复或特殊小节线。")
                }
            case let .spanner(spanner): try checkSpanner(spanner)
            default: throw refuse("第 \(measure) 小节含未支持的演奏或结构标记，请对照原谱校核。")
            }
        }
        return xml
    }

    private static func initialTempo(_ score: SheetMusicCore.Score) throws -> Double? {
        var value: Double?
        for (measure, system) in score.systemMeasures.enumerated() {
            for positioned in system.elements {
                switch positioned.element {
                case let .tempo(tempo):
                    let bpm = tempo.beatsPerSecond * 60
                    guard bpm.isFinite, (20...300).contains(bpm),
                          value != nil || (measure == 0 && positioned.position.offset.numerator == 0),
                          value == nil || abs(value! - bpm) <= 0.01 else {
                        throw refuse("仅支持曲首设置每分钟 20–300 个四分音符的固定速度。")
                    }
                    value = bpm
                case .rehearsalMark: break // Rehearsal labels do not alter the note timeline.
                default: throw refuse("包含摇摆节奏、乐器切换或未解释的系统演奏指示。")
                }
            }
        }
        return value
    }

    private static func checkSpanner(_ spanner: Spanner) throws {
        switch spanner.kind {
        case .slur, .hairpin: break // Known display/dynamic simplifications; never merge slurs as ties.
        default: throw refuse("包含反复房子、八度线、踏板或未支持的跨音符演奏线。")
        }
    }

    private static func articulationXML(_ articulations: [ChordArticulation]) throws -> String {
        guard !articulations.isEmpty else { return "" }
        let symbols = try articulations.map { articulation -> String in
            switch articulation.kind {
            case .staccato: return "<staccato/>"
            case .staccatissimo: return "<staccatissimo/>"
            case .tenuto: return "<tenuto/>"
            case .accent: return "<accent/>"
            case .marcato: return "<strong-accent/>"
            default: throw refuse("包含未支持的特殊奏法，不能作为普通音符评分。")
            }
        }
        return "<articulations>\(symbols.joined())</articulations>"
    }

    private static func pitchXML(_ note: Note) throws -> String {
        guard (0...127).contains(note.pitch), (-1...33).contains(note.tpc), note.play, !note.isSmall,
              note.glissando == nil, note.guitarBend == nil, !note.guitarBendBack, note.legacyBend == nil,
              note.fret == nil, note.string == nil, note.symbols.isEmpty, note.preservedMarkup.isEmpty else {
            throw refuse("音符音高无效，或含提示音、滑音、弯音及未支持的演奏信息。")
        }
        if let accidental = note.accidental {
            guard [.flat, .natural, .sharp, .doubleSharp, .doubleFlat, .naturalFlat, .naturalSharp, .sharpSharp].contains(accidental) else {
                throw refuse("不支持微分音或超过重升、重降的临时记号。")
            }
        }
        let letters = ["F", "C", "G", "D", "A", "E", "B"]
        let natural = [5, 0, 7, 2, 9, 4, 11]
        let position = ((note.tpc - 13) % 7 + 7) % 7
        let alter = (note.tpc - 13 - position) / 7
        let base = note.pitch - natural[position] - alter
        guard (-2...2).contains(alter), base % 12 == 0 else { throw refuse("音高与升降号拼写不一致。") }
        let octave = base / 12 - 1
        guard (-1...9).contains(octave) else { throw refuse("音符八度超出支持范围。") }
        return "<pitch><step>\(letters[position])</step><alter>\(alter)</alter><octave>\(octave)</octave></pitch>"
    }

    private static func clef(_ value: String) throws -> String {
        guard value == "G" || value == "F" else { throw refuse("仅支持普通高音、低音谱号，不能猜测八度移位。") }
        return value
    }

    private static func quarterBeats(_ fraction: Fraction, allowNegative: Bool = false) throws -> Double {
        guard fraction.denominator > 0, fraction.denominator <= 1_000_000,
              (-32_000_000...32_000_000).contains(fraction.numerator) else { throw refuse("时值超出范围。") }
        let value = Double(fraction.numerator) * 4 / Double(fraction.denominator)
        guard value.isFinite, abs(value) <= 128, allowNegative || value > 0 else { throw refuse("时值无效。") }
        return value
    }

    private static func movement(_ name: String, _ beats: Double) -> String {
        "<\(name)><duration>\(decimal(beats))</duration></\(name)>"
    }

    private static func decimal(_ value: Double) -> String {
        // MusicXML's decimal type doesn't permit scientific notation.
        String(format: "%.12f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func escape(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.filter {
            $0.value == 9 || $0.value == 10 || $0.value == 13 || $0.value >= 32
        }))
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
