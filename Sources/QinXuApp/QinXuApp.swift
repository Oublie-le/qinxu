import SwiftUI
import QinXuCore

@main
struct QinXuApp: App {
    @StateObject private var model: PracticeViewModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            // Tests never open a MIDI/audio device or touch the user's library.
            // A validated UUID can opt into the same isolated store across launches.
            let prefix = "--ui-test-store-id="
            let requestedID = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) })
                .flatMap { UUID(uuidString: String($0.dropFirst(prefix.count))) }
            let storeID = requestedID ?? UUID()
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("QinXu-UI-\(storeID.uuidString)", isDirectory: true)
                .appendingPathComponent("library.json")
            if ProcessInfo.processInfo.arguments.contains("--ui-test-reading-pdf"),
               let resource = BundledBook.beyer.resourceURL {
                let store = ImportedDocumentStore(libraryURL: file)
                if store.load().documents.isEmpty {
                    _ = try? store.importPDF(from: resource, title: "读谱练习测试谱")
                }
            }
            #if os(iOS)
            if ProcessInfo.processInfo.arguments.contains("--ui-test-reading-images") {
                let store = ImportedDocumentStore(libraryURL: file)
                if store.load().documents.isEmpty {
                    try? UITestImageScoreFixture.importPages(into: store)
                }
            }
            #endif
            _model = StateObject(wrappedValue: PracticeViewModel(
                storage: LocalLibraryStore(url: file), deviceAccessEnabled: false))
            return
        }
        #endif
        _model = StateObject(wrappedValue: PracticeViewModel())
    }

    var body: some Scene {
        WindowGroup {
            PracticeHomeView(model: model)
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                .preferredColorScheme(.light)
                #if os(macOS)
                .frame(minWidth: 920, minHeight: 700)
                #endif
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { model.suspendForBackground() }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 900)
        #endif
    }
}
