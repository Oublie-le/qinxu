import Foundation
import Testing
import QinXuCore
@testable import QinXuApp

@Suite @MainActor struct BundledPracticeLibraryTests {
    @Test func bundledLessonsParseAndUseChineseTitles() throws {
        let catalogue = BundledPracticeLibrary.beyer
        #expect(catalogue.error == nil)
        #expect(!catalogue.scores.isEmpty)
        #expect(catalogue.scores.count == catalogue.lessons.count)
        #expect(Set(catalogue.scores.map(\.id)).count == catalogue.scores.count)
        for score in catalogue.scores {
            #expect(score.title.hasPrefix("拜厄 · "))
            #expect(score.composer == "费迪南德·拜厄")
            #expect(!score.notes.isEmpty && !score.measures.isEmpty)
            #expect(score.notes.allSatisfy { $0.staff == 1 || $0.staff == 2 })
            #expect(score.notes.allSatisfy { $0.startBeat >= 0 && $0.durationBeats > 0 })
        }
    }

    @Test func textbookSelectionRestoresWithoutDuplicatingBundledScoresInUserStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = LocalLibraryStore(url: directory.appendingPathComponent("library.json"))
        let model = PracticeViewModel(storage: storage, automaticTimer: false, deviceAccessEnabled: false)
        let score = try #require(BundledPracticeLibrary.scores.first)
        model.selectScore(score.id)
        model.toggleFavorite(score.id)
        let saved = storage.load()
        #expect(saved.lastScoreID == score.id)
        #expect(saved.scores.isEmpty)
        let restored = PracticeViewModel(storage: storage, automaticTimer: false, deviceAccessEnabled: false)
        #expect(restored.selectedScoreID == score.id)
        #expect(restored.favoriteScoreIDs.contains(score.id))
        #expect(restored.scores.filter { $0.id == score.id }.count == 1)
        restored.togglePlayback()
        let expected = try #require(restored.engine.expectedNotes.first)
        #expect(restored.engine.isRunning)
        #expect(restored.engine.expectedNotes.contains(where: { $0.midi == expected.midi }))
    }

    @Test func everyBundledLessonCanCompleteThroughTheRealPracticeEngine() {
        for score in BundledPracticeLibrary.scores {
            var events: [(Double, Bool, Int)] = []
            for note in score.notes {
                events.append((note.startBeat, true, note.midi))
                events.append((note.startBeat + note.durationBeats, false, note.midi))
            }
            events.sort { $0.0 == $1.0 ? (!$0.1 && $1.1) : $0.0 < $1.0 }
            var engine = PracticeEngine(score: score, tempoBPM: 60)
            engine.start(at: 10)
            for (beat, on, pitch) in events {
                engine.receive(on ? .on(pitch: pitch, velocity: 80) : .off(pitch: pitch), at: 10 + beat)
            }
            #expect(engine.isFinished, "未完成：\(score.title)")
            #expect(engine.correctCount == score.notes.count, "判音数不符：\(score.title)")
            #expect(engine.wrongCount == 0 && engine.missedCount == 0, "出现错漏：\(score.title)")
        }
    }
}
