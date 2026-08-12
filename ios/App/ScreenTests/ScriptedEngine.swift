import ChessfenKit
import Synchronization

@testable import Chessfen

/// An engine that reports what it was told to report.
///
/// The seam is the search and nothing above it (see `Engine`): a screen driven by this one runs
/// the real `retune`, the real `record`, the real Score written against the real ply — what is
/// faked is only the one thing in the app that cannot be asked twice for the same answer.
final class ScriptedEngine: Engine {
    /// The snapshots every search reports, in order, deepest last — a real search deepens, and a
    /// screen that redraws on each snapshot should be made to do it.
    private let snapshots: [Analysis]
    /// Whether the search ever finishes. A search that ends is a search that has answered, which
    /// is what an engine holding a Controller does; leaving it open is what being thought *about*
    /// looks like.
    private let isEndless: Bool
    private let paused = Mutex(false)
    /// The searches still running, so that `stop` can wind them up the way the real engine does —
    /// which is what letting go of 让引擎走 does.
    private let running = Mutex<[AsyncStream<Analysis>.Continuation]>([])

    init(_ snapshots: [Analysis], isEndless: Bool = false) {
        self.snapshots = snapshots
        self.isEndless = isEndless
    }

    var isPaused: Bool { paused.withLock { $0 } }
    func pause() { paused.withLock { $0 = true } }
    func resume() { paused.withLock { $0 = false } }
    func clear() async {}

    /// Winds up whatever is running, which ends its stream — a stopped search has still reported
    /// everything it found, exactly as Stockfish does.
    func stop() {
        let winding = running.withLock { current -> [AsyncStream<Analysis>.Continuation] in
            let all = current
            current = []
            return all
        }
        for continuation in winding { continuation.finish() }
    }

    func analyse(_ game: Game, budget: EngineService.Budget) -> AsyncStream<Analysis> {
        AsyncStream { continuation in
            for snapshot in snapshots { continuation.yield(snapshot) }
            if isEndless {
                running.withLock { $0.append(continuation) }
            } else {
                continuation.finish()
            }
        }
    }

    func evaluate(_ game: Game, budget: EngineService.Budget) async -> Score? {
        snapshots.last?.best?.score
    }

    /// One Score per ply, walked down the script so a curve has something to be a curve about.
    func review(
        _ game: Game, depth: Int, onPly: (@Sendable (Int, Score?) -> Void)?
    ) async -> [Score?] {
        game.plies.indices.map { ply in
            let score = snapshots[min(ply, snapshots.count - 1)].best?.score
            onPly?(ply, score)
            return score
        }
    }
}
