import Foundation
import Testing
import QinXuCore
@testable import QinXuApp

@Suite @MainActor struct BundledCollectionsTests {
    @Test func allCollectionMembersHaveCreditsAndCompleteInPractice() {
        let pieces = BundledCollections.scores
        let ids = Set(pieces.map(\.id))
        let grouped = BundledCollections.collections.flatMap(\.entries)
        #expect(Set(grouped.map(\.sourceID)) == ids)
        #expect(grouped.count == ids.count)
        #expect(BundledCollections.metadata.keys.sorted() == ids.sorted())
        for score in pieces {
            #expect(!score.composer.isEmpty)
            #expect(BundledCollections.metadata[score.id]?.difficulty != .unspecified)
            let measures = Dictionary(uniqueKeysWithValues: score.measures.map { ($0.number, $0) })
            let events = score.notes.flatMap { note in
                [(note.startBeat, true, note.midi), (note.startBeat + note.durationBeats, false, note.midi)]
            }.sorted { $0.0 == $1.0 ? (!$0.1 && $1.1) : $0.0 < $1.0 }
            for note in score.notes {
                if let measure = measures[note.measure] {
                    #expect(note.startBeat >= measure.startBeat)
                    #expect(note.startBeat + note.durationBeats <= measure.startBeat + measure.durationBeats)
                } else {
                    Issue.record("缺少小节：\(score.title) 第 \(note.measure) 小节")
                }
            }
            var engine = PracticeEngine(score: score, tempoBPM: 60)
            engine.start(at: 10)
            for (beat, on, pitch) in events {
                engine.receive(on ? .on(pitch: pitch, velocity: 80) : .off(pitch: pitch), at: 10 + beat)
            }
            #expect(engine.isFinished && engine.correctCount == score.notes.count, "未完成：\(score.title)")
        }
    }

    @Test func selectingACollectionScoreRestoresItWithoutWritingABundledCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = LocalLibraryStore(url: directory.appendingPathComponent("library.json"))
        let score = try #require(BundledCollections.scores.first)
        let model = PracticeViewModel(storage: storage, automaticTimer: false, deviceAccessEnabled: false)
        model.selectScore(score.id)
        #expect(storage.load().scores.isEmpty)
        let reopened = PracticeViewModel(storage: storage, automaticTimer: false, deviceAccessEnabled: false)
        #expect(reopened.selectedScoreID == score.id)
    }
}
