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
                .onChange(of: scenePhase) { _, phase in
                    // An unbounded Analysis left running while the app is not on screen is
                    // a phone getting warm in a pocket over a position nobody is looking
                    // at. Whatever screen owns the search restarts it on the way back.
                    if phase != .active { engine.suspend() }
                }
        }
    }
}
