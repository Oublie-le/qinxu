import QinXuCore

/// Compact, playable piano arrangements. Every bar describes both hands independently.
enum BundledCollections {
    private typealias Event = (pitch: Int, beats: Double)
    private typealias Bar = (melody: [Event], bass: [[Int]])

    private struct Piece {
        let score: PianoScore
        let difficulty: CatalogDifficulty
        let genre: String
    }

    static let scores = (pop + familiar).map(\.score)
    static let metadata = Dictionary(uniqueKeysWithValues: (pop + familiar).map {
        ($0.score.id, ScoreCatalogMetadata(difficulty: $0.difficulty, genre: $0.genre))
    })
    static let collections: [LibraryCollection] = [
        LibraryCollection(id: "bundled-pop-piano", title: "流行钢琴",
                          subtitle: "原创短曲 · 抒情、轻快与切分", entries: pop.map { .score($0.score.id) }),
        LibraryCollection(id: "bundled-familiar-melodies", title: "熟悉的旋律",
                          subtitle: "经典主题 · 简易钢琴改编", entries: familiar.map { .score($0.score.id) })
    ]

    private static let pop: [Piece] = [
        original("pop-window-rain", "窗边的雨", 68, .beginner, [
            ([(64, 2), (67, 1), (69, 1)], [[48]]),
            ([(67, 1), (64, 1), (62, 2)], [[43]]),
            ([(60, 1), (64, 1), (69, 2)], [[45]]),
            ([(67, 2), (65, 1), (64, 1)], [[41]]),
            ([(62, 1), (65, 1), (69, 1), (67, 1)], [[50]]),
            ([(64, 2), (62, 1), (60, 1)], [[48]]),
            ([(62, 1), (64, 1), (67, 2)], [[43]]),
            ([(60, 4)], [[48]])
        ]),
        original("pop-neon", "街角霓虹", 102, .intermediate, [
            ([(0, 0.5), (67, 0.5), (69, 1), (72, 0.5), (69, 0.5), (67, 1)], [[45], [52], [48], [52]]),
            ([(65, 1.5), (67, 0.5), (69, 1), (64, 1)], [[41], [48], [45], [48]]),
            ([(0, 0.5), (64, 0.5), (67, 1), (71, 0.5), (72, 0.5), (67, 1)], [[48], [55], [52], [55]]),
            ([(69, 1), (67, 0.5), (65, 0.5), (62, 2)], [[43], [50], [47], [50]]),
            ([(72, 1), (76, 1), (74, 0.5), (72, 0.5), (69, 1)], [[45], [52], [48], [52]]),
            ([(69, 0.5), (67, 0.5), (65, 1), (64, 1), (65, 1)], [[41], [48], [45], [48]]),
            ([(67, 1.5), (69, 0.5), (71, 1), (74, 1)], [[43], [50], [47], [50]]),
            ([(72, 3), (0, 1)], [[48, 55]])
        ]),
        original("pop-small-trip", "午后散步", 94, .easy, [
            ([(60, 0.5), (62, 0.5), (64, 1), (67, 2)], [[48], [55]]),
            ([(69, 1), (67, 0.5), (65, 0.5), (64, 2)], [[41], [48]]),
            ([(67, 1), (71, 1), (72, 0.5), (71, 0.5), (67, 1)], [[43], [50]]),
            ([(64, 1), (62, 1), (60, 2)], [[48], [55]]),
            ([(64, 0.5), (67, 0.5), (69, 1), (72, 2)], [[45], [52]]),
            ([(74, 1), (72, 0.5), (69, 0.5), (65, 2)], [[41], [48]]),
            ([(67, 1), (65, 0.5), (64, 0.5), (62, 1), (67, 1)], [[43], [50]]),
            ([(60, 4)], [[48, 55]])
        ]),
        original("pop-paper-plane", "纸飞机", 88, .easy, [
            ([(67, 1), (69, 0.5), (72, 0.5), (76, 2)], [[48], [55]]),
            ([(74, 0.5), (72, 0.5), (71, 1), (67, 2)], [[47], [55]]),
            ([(69, 1), (72, 1), (76, 1.5), (74, 0.5)], [[45], [52]]),
            ([(72, 2), (69, 1), (65, 1)], [[41], [48]]),
            ([(65, 0.5), (67, 0.5), (69, 1), (74, 2)], [[50], [57]]),
            ([(71, 1), (67, 1), (74, 1), (72, 1)], [[43], [50]]),
            ([(69, 1.5), (67, 0.5), (65, 1), (62, 1)], [[43], [47]]),
            ([(64, 1), (60, 3)], [[48, 55]])
        ]),
        original("pop-last-train", "末班车", 76, .intermediate, [
            ([(69, 1.5), (72, 0.5), (71, 1), (64, 1)], [[45], [52], [48], [52]]),
            ([(67, 1), (69, 1), (72, 1), (67, 1)], [[41], [48], [45], [48]]),
            ([(67, 1.5), (64, 0.5), (62, 1), (64, 1)], [[48], [55], [52], [55]]),
            ([(71, 2), (67, 1), (62, 1)], [[43], [50], [47], [50]]),
            ([(65, 0.5), (69, 0.5), (72, 1), (74, 1), (72, 1)], [[50], [57], [53], [57]]),
            ([(76, 2), (72, 1.5), (69, 0.5)], [[45], [52], [48], [52]]),
            ([(67, 1), (69, 1), (71, 0.5), (67, 0.5), (64, 1)], [[43], [50], [47], [50]]),
            ([(69, 4)], [[45, 52]])
        ])
    ]

    private static let familiar: [Piece] = [
        simpleTheme("classic-twinkle", "小星星", "法国传统旋律", 76,
            "传统旋律亦见莫扎特 K.265 的主题。本谱采用简易左手伴奏。",
            [[60, 60, 67, 67], [69, 69, 67], [65, 65, 64, 64], [62, 62, 60],
             [67, 67, 65, 65], [64, 64, 62], [67, 67, 65, 65], [64, 64, 62],
             [60, 60, 67, 67], [69, 69, 67], [65, 65, 64, 64], [62, 62, 60]],
            bass: [48, 41, 41, 43, 48, 43, 48, 43, 48, 41, 41, 43],
            endings: [3: 48, 11: 48]),
        simpleTheme("classic-joy", "欢乐颂 · 主题", "路德维希·范·贝多芬", 84,
            "选自第九交响曲终乐章的主题，移至 C 大调并简化节奏及左手伴奏。",
            [[64, 64, 65, 67], [67, 65, 64, 62], [60, 60, 62, 64], [64, 62, 62],
             [64, 64, 65, 67], [67, 65, 64, 62], [60, 60, 62, 64], [62, 60, 60]],
            bass: [48, 43, 48, 43, 48, 43, 48, 43],
            endings: [7: 48]),
        make("classic-auld-lang-syne", "友谊地久天长 · 主题", "苏格兰传统旋律", 74, .easy, "传统旋律",
            "公版旋律的前段，略去原曲弱起并配以简易伴奏。", [
                ([(60, 2), (60, 1), (64, 1)], [[48]]),
                ([(62, 2), (60, 1), (62, 1)], [[43]]),
                ([(64, 1), (60, 1), (60, 1), (67, 1)], [[48]]),
                ([(69, 3), (69, 1)], [[41]]),
                ([(67, 2), (64, 1), (64, 1)], [[48]]),
                ([(60, 2), (62, 1), (60, 1)], [[48]]),
                ([(62, 1), (64, 1), (62, 1), (60, 1)], [[43]]),
                ([(60, 4)], [[48, 55]])
            ])
    ]

    private static func original(_ id: String, _ title: String, _ tempo: Double,
                                 _ level: CatalogDifficulty, _ bars: [Bar]) -> Piece {
        make(id, title, "琴序原创", tempo, level, "流行风格", "原创流行风格钢琴短曲。", bars)
    }

    private static func simpleTheme(_ id: String, _ title: String, _ author: String,
                                    _ tempo: Double, _ source: String, _ melody: [[Int]],
                                    bass: [Int], endings: [Int: Int]) -> Piece {
        let bars: [Bar] = melody.enumerated().map { bar, pitches in
            let right = pitches.enumerated().map { index, pitch in
                (pitch, index == pitches.count - 1 ? Double(5 - pitches.count) : 1)
            }
            let left = endings[bar].map { [[bass[bar]], [$0]] } ?? [[bass[bar]]]
            return (right, left)
        }
        return make(id, title, author, tempo, .beginner, "经典主题", source, bars)
    }

    private static func make(_ id: String, _ title: String, _ author: String,
                             _ tempo: Double, _ level: CatalogDifficulty, _ genre: String,
                             _ source: String, _ bars: [Bar]) -> Piece {
        let spellings = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
        var notes: [ScoreNote] = []
        var measures: [ScoreMeasure] = []
        func add(_ pitch: Int, at beat: Double, duration: Double, staff: Int, measure: Int) {
            guard pitch > 0 else { return }
            let pitchClass = pitch % 12
            notes.append(ScoreNote(id: "\(id)-\(notes.count + 1)", midi: pitch, startBeat: beat,
                durationBeats: duration, staff: staff, measure: measure, step: spellings[pitchClass],
                alter: [1, 3, 6, 8, 10].contains(pitchClass) ? 1 : 0, octave: pitch / 12 - 1))
        }
        for (index, bar) in bars.enumerated() {
            let start = Double(index * 4)
            let measure = index + 1
            measures.append(ScoreMeasure(number: measure, startBeat: start, durationBeats: 4))
            var beat = start
            for event in bar.melody {
                add(event.pitch, at: beat, duration: event.beats, staff: 1, measure: measure)
                beat += event.beats
            }
            let pulse = 4 / Double(bar.bass.count)
            for (index, chord) in bar.bass.enumerated() {
                for pitch in chord {
                    add(pitch, at: start + Double(index) * pulse, duration: pulse, staff: 2, measure: measure)
                }
            }
        }
        notes.sort {
            if $0.startBeat != $1.startBeat { return $0.startBeat < $1.startBeat }
            if $0.staff != $1.staff { return $0.staff < $1.staff }
            return $0.midi < $1.midi
        }
        let score = PianoScore(id: id, title: title, composer: author, tempoBPM: tempo,
                               notes: notes, measures: measures, warnings: [source])
        return Piece(score: score, difficulty: level, genre: genre)
    }
}
