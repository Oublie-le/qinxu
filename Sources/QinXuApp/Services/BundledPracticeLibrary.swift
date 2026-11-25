import Foundation
import QinXuCore

/// Bundled lessons use the same parser and practice engine as imported scores.
/// They are immutable app resources, never copies written into the user's library.
enum BundledPracticeLibrary {
    struct Lesson: Decodable, Identifiable {
        let id: String
        let title: String
        let filename: String
        let sourcePage: Int
        let notes: [String]?
    }
    struct Manifest: Decodable {
        let version: Int
        let lessons: [Lesson]
    }
    struct Catalogue {
        var lessons: [Lesson] = []
        var scores: [PianoScore] = []
        var error: String?
    }

    static let beyer = loadBeyer()
    static var scores: [PianoScore] { beyer.scores }
    static var ids: Set<String> { Set(scores.map(\.id)) }
    static var allBundledIDs: Set<String> { ids.union(DemoScores.all.map(\.id)) }

    private static func loadBeyer() -> Catalogue {
        #if SWIFT_PACKAGE
        let bundle = Bundle.main.resourceURL
            .flatMap { Bundle(url: $0.appendingPathComponent("QinXu_QinXuApp.bundle")) } ?? Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        let url = ["Resources/Books/Beyer", "Books/Beyer"].compactMap {
            bundle.url(forResource: "manifest", withExtension: "json", subdirectory: $0)
        }.first
        guard let url else { return Catalogue(error: "拜厄练习谱资源缺失，请安装完整版本。") }
        do {
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
            guard manifest.version == 1, !manifest.lessons.isEmpty,
                  Set(manifest.lessons.map(\.id)).count == manifest.lessons.count else {
                throw CatalogueError.invalid
            }
            var scores: [PianoScore] = []
            for lesson in manifest.lessons {
                guard lesson.filename == URL(fileURLWithPath: lesson.filename).lastPathComponent,
                      lesson.filename.hasSuffix(".musicxml"), lesson.id.hasPrefix("beyer-op101-"),
                      lesson.sourcePage > 0 else { throw CatalogueError.invalid }
                let data = try Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(lesson.filename))
                var score = try MusicXMLParser().parse(data: data)
                score.id = lesson.id
                score.title = "拜厄 · " + lesson.title
                score.composer = "费迪南德·拜厄"
                score.warnings.append(contentsOf: lesson.notes ?? [])
                score.warnings.append("公版原作的中文练习谱，非出版社中文版；原谱第 \(lesson.sourcePage) 页。")
                scores.append(score)
            }
            return Catalogue(lessons: manifest.lessons, scores: scores)
        } catch {
            // Never silently present a partial book after a packaging/parser failure.
            return Catalogue(error: "拜厄练习谱读取失败：\(error.localizedDescription)")
        }
    }

    private enum CatalogueError: LocalizedError {
        case invalid
        var errorDescription: String? { "教材目录格式不受支持。" }
    }
}
