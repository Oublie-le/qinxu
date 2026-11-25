import SwiftUI
import QinXuCore

@main
struct QinXuApp: App {
    @StateObject private var model: PracticeViewModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            // Each test launch has a new local store and never opens a MIDI/audio device.
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("QinXu-UI-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("library.json")
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
