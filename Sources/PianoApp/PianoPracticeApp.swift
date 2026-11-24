import SwiftUI

@main
struct PianoPracticeApp: App {
    @StateObject private var model = PracticeViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
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
