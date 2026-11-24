import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Deliberately bounded MusicXML score-partwise importer for piano practice.
/// Durations are quarter-note beats. Pitch always comes from pitch/alter, never the key signature.
public struct MusicXMLParser {
    public init() {}

    public func parse(data: Data) throws -> PianoScore {
        guard !data.isEmpty, data.count <= 5 * 1_024 * 1_024 else {
            throw MusicXMLImportError("曲谱为空或超过 5 MB 限制。")
        }
        if data.starts(with: [0x50, 0x4B]) {
            throw MusicXMLImportError("暂不支持压缩的 .mxl 文件，请先导出为 .musicxml 或 .xml。")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw MusicXMLImportError("请使用 UTF-8 编码的 MusicXML 文件。")
        }
        let safeText = try withoutExternalDeclaration(text)
        let reader = XMLTreeReader()
        let parser = XMLParser(data: Data(safeText.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), let root = reader.root else {
            throw reader.failure ?? MusicXMLImportError("MusicXML 格式无效，无法读取曲谱。")
        }
        return try ScoreBuilder(root: root, identifier: stableIdentifier(data)).build()
    }

    /// Strip the conventional public declaration before parsing; no DTD is ever loaded.
    private func withoutExternalDeclaration(_ text: String) throws -> String {
        let unsafe = MusicXMLImportError("不支持含内部 DTD、实体声明或非官方 DTD 的曲谱；请使用标准 MusicXML 导出。")
        let upper = text.uppercased()
        guard !upper.contains("<!ENTITY") else { throw unsafe }
        guard upper.contains("<!DOCTYPE") else { return text }
        let pattern = #"<!DOCTYPE\s+score-partwise\s+PUBLIC\s+(['"])-//Recordare//DTD MusicXML (?:1\.0|1\.1|2\.0|3\.0|3\.1|4\.0) Partwise//EN\1\s+(['"])https?://www\.musicxml\.org/dtds/partwise\.dtd\2\s*>"#
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = expression.matches(in: text, range: range)
        guard matches.count == 1, let match = matches.first,
              let declarationRange = Range(match.range, in: text),
              let rootStart = text.range(of: "<score-partwise"),
              declarationRange.upperBound <= rootStart.lowerBound else { throw unsafe }
        var clean = text
        clean.removeSubrange(declarationRange)
        guard !clean.uppercased().contains("<!DOCTYPE") else { throw unsafe }
        return clean
    }

    private func stableIdentifier(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return "import-" + String(hash, radix: 16)
    }
}

public struct MusicXMLImportError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

private final class XMLNode {
    let name: String
    let attributes: [String: String]
    var children: [XMLNode] = []
    var content = ""
    init(name: String, attributes: [String: String]) { self.name = name; self.attributes = attributes }
    var text: String { content.trimmingCharacters(in: .whitespacesAndNewlines) }
    func child(_ name: String) -> XMLNode? { children.first { $0.name == name } }
    func all(_ name: String) -> [XMLNode] { children.filter { $0.name == name } }
    func value(_ name: String) -> String? { child(name)?.text }
}

private final class XMLTreeReader: NSObject, XMLParserDelegate {
    var root: XMLNode?
    var failure: MusicXMLImportError?
    private var stack: [XMLNode] = []
    private var nodes = 0
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        nodes += 1
        guard stack.count < 64, nodes <= 150_000, !name.contains(":") else {
            failure = MusicXMLImportError("曲谱结构过深、过大，或使用了暂不支持的命名空间前缀。")
            parser.abortParsing(); return
        }
        let node = XMLNode(name: name, attributes: attributes)
        if let parent = stack.last { parent.children.append(node) }
        else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.content += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) { stack.last?.content += text }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        failure = MusicXMLImportError("不允许读取曲谱中的外部实体。")
        parser.abortParsing(); return nil
    }
}

private final class ScoreBuilder {
    let root: XMLNode
    let identifier: String
    var divisions: Double?
    var numerator = 4
    var denominator = 4
    var hasTime = false
    var staffCount = 1
    var tempo: Double?
    var notes: [ScoreNote] = []
    var measures: [ScoreMeasure] = []
    var openTies: [TieKey: Int] = [:]
    var warnings: [String] = ["练习谱面简化了排版、调号、连线、力度及文字指示；实际音高及节拍以曲谱数据为准。"]
    let epsilon = 0.000_001
    var nominalDuration: Double { Double(numerator) * 4 / Double(denominator) }

    struct TieKey: Hashable { let midi: Int; let staff: Int; let voice: String }
    struct ChordAnchor { let beat: Double; let duration: Double; let voice: String; let staff: Int }

    init(root: XMLNode, identifier: String) { self.root = root; self.identifier = identifier }
    func error(_ message: String) -> MusicXMLImportError { MusicXMLImportError(message) }

    func build() throws -> PianoScore {
        guard root.name == "score-partwise" else { throw error("仅支持 score-partwise 格式的 MusicXML 钢琴谱。") }
        try rejectUnsupported(root)
        let parts = root.all("part")
        let descriptions = root.child("part-list")?.all("score-part") ?? []
        guard parts.count == 1, descriptions.count == 1 else {
            throw error("第一版仅支持一个钢琴声部（可含左右手两个谱表），暂不支持多乐器总谱。")
        }
        guard let partID = descriptions[0].attributes["id"], !partID.isEmpty,
              parts[0].attributes["id"] == partID else { throw error("曲谱声部编号缺失或不一致。") }
        guard descriptions[0].all("score-instrument").count <= 1,
              descriptions[0].all("midi-instrument").count <= 1 else { throw error("暂不支持在同一声部中切换多种乐器。") }
        let sourceMeasures = parts[0].all("measure")
        guard !sourceMeasures.isEmpty, sourceMeasures.count <= 1_000 else { throw error("曲谱必须包含 1 至 1000 个小节。") }
        var start = 0.0
        for (index, measure) in sourceMeasures.enumerated() {
            let length = try readMeasure(measure, number: index + 1, start: start, isFirst: index == 0, isLast: index == sourceMeasures.count - 1)
            measures.append(ScoreMeasure(number: index + 1, startBeat: start, durationBeats: length))
            start += length
            guard start <= 64_000 else { throw error("曲谱总时长超过当前版本限制。") }
        }
        guard !notes.isEmpty else { throw error("曲谱没有可练习的有音高音符。") }
        guard openTies.isEmpty else { throw error("曲谱有未结束的延音线，请检查 tie 标记。") }
        if !hasTime { warnings.append("曲谱没有提供拍号，暂按 4/4 拍读取。") }
        notes.sort {
            if abs($0.startBeat - $1.startBeat) > epsilon { return $0.startBeat < $1.startBeat }
            if $0.staff != $1.staff { return $0.staff < $1.staff }
            return $0.midi < $1.midi
        }
        // The physical keyboard cannot separately identify simultaneous unisons from different voices.
        for index in notes.indices where index > 0 {
            let note = notes[index]
            for earlier in notes[..<index].reversed() {
                if note.startBeat - earlier.startBeat > epsilon { break }
                if note.midi == earlier.midi {
                    throw error("暂不支持同一时刻跨声部或谱表重叠的同音，请先简化曲谱。")
                }
            }
        }
        let title = root.value("movement-title") ?? root.child("work")?.value("work-title") ?? "未命名练习"
        let composers = root.child("identification")?.all("creator").filter { $0.attributes["type"] == "composer" }.map(\.text).filter { !$0.isEmpty } ?? []
        return PianoScore(id: identifier, title: title.isEmpty ? "未命名练习" : String(title.prefix(200)), composer: String(composers.joined(separator: "、").prefix(200)), tempoBPM: tempo ?? 80, beatsPerMeasure: numerator, beatUnit: denominator, notes: notes, measures: measures, warnings: warnings)
    }

    func rejectUnsupported(_ node: XMLNode) throws {
        let unsupported: [String: String] = [
            "repeat": "反复记号", "ending": "反复房子", "transpose": "移调乐器", "grace": "倚音",
            "unpitched": "无固定音高音符", "cue": "提示音符", "octave-shift": "八度移位线",
            "measure-repeat": "小节重复记号", "beat-repeat": "节拍重复记号", "multiple-rest": "多小节休止合并",
            "senza-misura": "自由拍号", "interchangeable": "交替拍号",
            "ornaments": "装饰音或震音", "arpeggiate": "琶音记号", "fermata": "自由延长记号",
            "swing": "摇摆节奏", "scordatura": "特殊定弦", "listen": "特殊演奏指示"
        ]
        if let label = unsupported[node.name] { throw error("暂不支持\(label)，请先将其展开为明确的普通音符和节拍。") }
        if ["articulations", "pedal"].contains(node.name) {
            let warning = "奏法与踏板指示暂不参与时值评分。"
            if !warnings.contains(warning) { warnings.append(warning) }
        }
        if node.name == "sound" {
            let navigation = ["dacapo", "dalsegno", "tocoda", "fine", "segno", "coda", "forward-repeat"]
            if navigation.contains(where: { node.attributes[$0] != nil }) { throw error("暂不支持 D.C.、D.S. 或 Coda 等跳转，请先展开曲谱。") }
        }
        if node.name == "note", let attack = node.attributes["attack"], Double(attack) != 0 { throw error("暂不支持带额外起音偏移的音符。") }
        if node.name == "note", let release = node.attributes["release"], Double(release) != 0 { throw error("暂不支持带额外松键偏移的音符。") }
        for child in node.children { try rejectUnsupported(child) }
    }

    func readMeasure(_ measure: XMLNode, number: Int, start: Double, isFirst: Bool, isLast: Bool) throws -> Double {
        guard measure.attributes["non-controlling"] != "yes" else { throw error("暂不支持各声部小节不对齐的曲谱。") }
        var cursor = 0.0
        var extent = 0.0
        var anchor: ChordAnchor?
        var contentSeen = false
        for node in measure.children {
            switch node.name {
            case "attributes":
                try readAttributes(node, atStart: start == 0 && !contentSeen, beforeContent: !contentSeen)
                anchor = nil
            case "direction":
                try readDirection(node, beat: start + cursor)
            case "sound":
                if let value = node.attributes["tempo"] { try setTempo(value, at: start + cursor) }
            case "backup", "forward":
                let duration = try durationInBeats(node)
                cursor += node.name == "backup" ? -duration : duration
                guard cursor >= -epsilon, cursor <= nominalDuration + epsilon else { throw error("第 \(number) 小节的声部时间移动超出了小节范围。") }
                cursor = max(0, cursor)
                if node.name == "forward" { extent = max(extent, cursor) }
                anchor = nil
                contentSeen = true
            case "note":
                try requireSingletons(node, names: ["chord", "rest", "pitch", "voice", "staff", "time-modification"])
                contentSeen = true
                guard notes.count < 20_000 else { throw error("曲谱音符超过 20000 个限制。") }
                let duration = try durationInBeats(node)
                let staff = try integer(node.value("staff") ?? "1", label: "谱表编号", range: 1...staffCount)
                let voice = node.value("voice") ?? "1"
                guard !voice.isEmpty, voice.count <= 64 else { throw error("声部编号为空或过长。") }
                let isChord = node.child("chord") != nil
                let isRest = node.child("rest") != nil
                let onset: Double
                if isChord {
                    guard !isRest, let previous = anchor, previous.voice == voice, previous.staff == staff,
                          duration <= previous.duration + epsilon else { throw error("第 \(number) 小节的和弦缺少主音、跨越声部/谱表，或时值长于主音。") }
                    onset = previous.beat
                } else {
                    onset = cursor
                    cursor += duration
                    anchor = isRest ? nil : ChordAnchor(beat: onset, duration: duration, voice: voice, staff: staff)
                }
                extent = max(extent, onset + duration)
                guard extent <= nominalDuration + epsilon else { throw error("第 \(number) 小节的时值超过拍号，请检查 divisions、backup 和音符时值。") }
                if let modification = node.child("time-modification") {
                    _ = try integer(modification.value("actual-notes"), label: "连音实际音符数", range: 1...64)
                    _ = try integer(modification.value("normal-notes"), label: "连音标准音符数", range: 1...64)
                }
                if isRest {
                    guard node.child("pitch") == nil, node.all("tie").isEmpty else { throw error("休止符不能同时包含音高或延音线。") }
                    continue
                }
                try readNote(node, start: start + onset, duration: duration, staff: staff, voice: voice, measure: number)
            default: break
            }
        }
        guard extent > epsilon else { throw error("第 \(number) 小节没有有效音符或休止符。") }
        if extent < nominalDuration - epsilon {
            guard isFirst || isLast || measure.attributes["implicit"] == "yes" else {
                throw error("第 \(number) 小节时值不足；弱起或不完整小节需使用 implicit=\"yes\"。")
            }
            return extent
        }
        return nominalDuration
    }

    func readAttributes(_ node: XMLNode, atStart: Bool, beforeContent: Bool) throws {
        try requireSingletons(node, names: ["divisions", "time", "staves"])
        if let raw = node.value("divisions") {
            guard beforeContent else { throw error("暂不支持在小节中途改变 divisions。") }
            divisions = try positiveNumber(raw, label: "divisions", maximum: 1_000_000)
        }
        if let raw = node.value("staves") {
            let count = try integer(raw, label: "谱表数量", range: 1...2)
            guard atStart || count == staffCount else { throw error("暂不支持曲中改变谱表数量。") }
            staffCount = count
        }
        if let time = node.child("time") {
            guard time.all("beats").count == 1, time.all("beat-type").count == 1 else { throw error("暂不支持复合或交替拍号。") }
            let beats = try integer(time.value("beats"), label: "拍号分子", range: 1...32)
            let unit = try integer(time.value("beat-type"), label: "拍号分母", range: 1...32)
            guard [1, 2, 4, 8, 16, 32].contains(unit) else { throw error("拍号分母必须是 1、2、4、8、16 或 32。") }
            guard beforeContent, atStart || (hasTime && beats == numerator && unit == denominator) else { throw error("暂不支持曲中变拍号。") }
            numerator = beats; denominator = unit; hasTime = true
        }
        for clef in node.all("clef") {
            let staff = try integer(clef.attributes["number"] ?? "1", label: "谱号编号", range: 1...staffCount)
            let expectedSign = staff == 1 ? "G" : "F"
            let expectedLine = staff == 1 ? "2" : "4"
            guard clef.value("sign") == expectedSign, clef.value("line") == expectedLine,
                  (clef.value("clef-octave-change") ?? "0") == "0" else {
                throw error("当前谱面仅支持第一谱表高音谱号、第二谱表低音谱号，且不带八度移位。")
            }
        }
    }

    func durationInBeats(_ node: XMLNode) throws -> Double {
        guard node.all("duration").count == 1 else { throw error("每个音符或声部移动必须有且仅有一个 duration 时值。") }
        guard let divisions else { throw error("曲谱缺少 divisions，无法确定音符时值。") }
        let value = try positiveNumber(node.value("duration"), label: "音符/声部移动时值", maximum: 64_000_000)
        let beats = value / divisions
        guard beats.isFinite, beats > 0, beats <= 128 else { throw error("音符时值超出支持范围。") }
        return beats
    }

    func readNote(_ node: XMLNode, start: Double, duration: Double, staff: Int, voice: String, measure: Int) throws {
        guard let pitch = node.child("pitch"), node.all("pitch").count == 1,
              let step = pitch.value("step"), let semitone = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11][step] else { throw error("音符缺少有效的 C–B 音名。") }
        try requireSingletons(pitch, names: ["step", "alter", "octave"])
        let octave = try integer(pitch.value("octave"), label: "八度", range: -1...9)
        let rawAlter = pitch.value("alter") ?? "0"
        guard let alteration = Double(rawAlter), alteration.isFinite,
              alteration.rounded() == alteration, (-2...2).contains(alteration) else {
            throw error("暂不支持微分音或超过重升/重降的音高。")
        }
        let alter = Int(alteration)
        let midi = (octave + 1) * 12 + semitone + alter
        guard (0...127).contains(midi) else { throw error("音高超出了 MIDI 0–127 范围。") }
        let key = TieKey(midi: midi, staff: staff, voice: voice)
        let tieElements = node.all("tie")
        guard tieElements.allSatisfy({ ["start", "stop"].contains($0.attributes["type"] ?? "") }) else { throw error("延音线 tie 类型必须是 start 或 stop。") }
        let ties = Set(tieElements.compactMap { $0.attributes["type"] })
        guard ties.count == tieElements.count else { throw error("音符包含重复的延音线标记。") }
        let visualTies = node.child("notations")?.all("tied") ?? []
        if tieElements.isEmpty && visualTies.contains(where: { ["start", "stop", "continue"].contains($0.attributes["type"] ?? "") }) {
            throw error("延音线只有视觉 tied 标记，缺少用于演奏的 tie 标记，请重新导出曲谱。")
        }
        if ties.contains("stop") {
            guard let index = openTies[key], abs(notes[index].startBeat + notes[index].durationBeats - start) <= epsilon else {
                throw error("第 \(measure) 小节的延音线没有同音、同谱表、同声部且连续的起点。")
            }
            notes[index].durationBeats += duration
            if !ties.contains("start") { openTies.removeValue(forKey: key) }
        } else {
            guard openTies[key] == nil else { throw error("第 \(measure) 小节的延音线中断或缺少 stop 标记。") }
            let index = notes.count
            notes.append(ScoreNote(id: "\(identifier)-n\(index + 1)", midi: midi, startBeat: start, durationBeats: duration, staff: staff, measure: measure, step: step, alter: alter, octave: octave))
            if ties.contains("start") { openTies[key] = index }
        }
    }

    func readDirection(_ node: XMLNode, beat: Double) throws {
        let offset: Double
        if let raw = node.value("offset") {
            guard let value = Double(raw), value.isFinite, let divisions else { throw error("速度指示的 offset 无效。") }
            offset = value / divisions
        } else { offset = 0 }
        var normalized: Double?
        for directionType in node.all("direction-type") {
            for metronome in directionType.all("metronome") {
                guard metronome.child("metronome-note") == nil, metronome.all("beat-unit").count == 1,
                      let unit = metronome.value("beat-unit"),
                      let factor = ["whole": 4.0, "half": 2, "quarter": 1, "eighth": 0.5, "16th": 0.25, "32nd": 0.125][unit],
                      let raw = metronome.value("per-minute"), let count = Double(raw), count.isFinite, count > 0 else { throw error("暂不支持该节拍器标记，请使用明确的音符单位和数字速度。") }
                let dots = metronome.all("beat-unit-dot").count
                guard dots <= 3 else { throw error("节拍器音符的附点数量过多。") }
                let dotFactor = 2 - pow(0.5, Double(dots))
                let value = factor * dotFactor * count
                if let prior = normalized, abs(prior - value) > epsilon { throw error("同一位置存在互相冲突的速度标记。") }
                normalized = value
            }
        }
        let soundTempos = node.all("sound").compactMap { $0.attributes["tempo"] }
        for raw in soundTempos {
            guard let value = Double(raw), value.isFinite else { throw error("速度不是有效数字。") }
            if let normalized, abs(value - normalized) > 0.01 { throw error("节拍器标记与 MIDI 播放速度不一致，请修正曲谱。") }
            try setTempo(raw, at: beat + offset)
        }
        if soundTempos.isEmpty, let normalized { try setTempo(String(normalized), at: beat + offset) }
    }

    func setTempo(_ raw: String, at beat: Double) throws {
        guard let value = Double(raw), value.isFinite, (20...300).contains(value) else { throw error("速度必须为每分钟 20–300 个四分音符。") }
        if let tempo {
            guard abs(value - tempo) <= 0.01 else { throw error("暂不支持曲中变速，请先使用固定速度曲谱。") }
        } else {
            guard abs(beat) <= epsilon else { throw error("暂不支持在曲中首次设置速度，请把速度标记放在曲首。") }
            tempo = value
        }
    }

    func requireSingletons(_ node: XMLNode, names: [String]) throws {
        for name in names where node.all(name).count > 1 {
            throw error("曲谱包含重复的 \(name) 标记，无法可靠读取。")
        }
    }

    func positiveNumber(_ value: String?, label: String, maximum: Double) throws -> Double {
        guard let value, let number = Double(value), number.isFinite, number > 0, number <= maximum else {
            throw error("\(label)缺失或不是支持范围内的正数。")
        }
        return number
    }

    func integer(_ value: String?, label: String, range: ClosedRange<Int>) throws -> Int {
        guard let value, let number = Int(value), range.contains(number) else { throw error("\(label)缺失、不是整数或超出支持范围。") }
        return number
    }
}
