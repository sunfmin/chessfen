import ChessfenKit
import SwiftUI

@main
struct ChessfenApp: App {
    @State private var engine = EngineHost()
    @State private var library = GameLibrary()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryScreen()
                .environment(engine)
                .environment(library)
                .task { await engine.start() }
                // The only reader of the scene phase in the app: it is turned into
                // `engine.isActive` here, and everything that cares watches that instead.
                // `initial` matters for a launch that never reaches `.active` — into the
                // background for a fetch, say — where there is no change to hear about.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    engine.setActive(phase == .active)
                }
        }
    }
}
