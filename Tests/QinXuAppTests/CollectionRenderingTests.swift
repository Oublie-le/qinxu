import Foundation
import SwiftUI
import Testing
import QinXuCore
@testable import QinXuApp

#if os(macOS)
extension PracticeRenderingTests {
    @Test(arguments: [667, 1194])
    func collectionsStayCollapsedAndPlayableAtPhoneAndTabletSizes(width: Int) throws {
        let height = width == 667 ? 375 : 834
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = PracticeViewModel(storage: LocalLibraryStore(url: directory.appendingPathComponent("library.json")),
                                      automaticTimer: false, deviceAccessEnabled: false)
        let collection = try #require(BundledCollections.collections.first)
        #expect(!collection.entries.isEmpty)
        #expect(collection.entries.allSatisfy { ref in model.scores.contains { $0.id == ref.sourceID } })
        try render(PracticeHomeView(model: model).frame(width: CGFloat(width), height: CGFloat(height)),
                   name: "catalog-home-\(width)", width: width, height: height)
        try render(LibraryCollectionView(model: model, collection: collection, compact: width == 667,
                                         onSelect: { _ in }, onPractice: { _ in })
            .frame(width: CGFloat(width), height: CGFloat(height)),
            name: "catalog-collection-\(width)", width: width, height: height)
    }
}
#endif
