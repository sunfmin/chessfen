import CStockfish
import Foundation
import Synchronization

/// The one Stockfish in the app, behind a serial queue.
///
/// Why one, and why a queue rather than an actor (docs/adr/0009): Stockfish keeps a
/// transposition table and a thread pool that are expensive to build and that a second
/// instance would compete with for cores. Its own threads do the searching, so the calls
/// here are either instant or *blocking* — `cf_engine_wait` waits for a search to wind up —
/// and blocking calls have no business on Swift's cooperative pool. A dedicated serial
/// queue gives both properties at once: one search at a time, and no thread starvation.
///
/// The C callbacks arrive on Stockfish's threads. They are handed straight to a mutex and
/// an `AsyncStream` continuation, both of which are safe to touch from anywhere, and they
/// never call back into the engine.
public final class EngineService: @unchecked Sendable {
    public struct Configuration: Sendable {
        /// Cores to search on. Two are left for the UI and the OS, because a phone that has
        /// stopped answering taps is not a better chess app.
        public var threads: Int
        public var hashMegabytes: Int
        /// How many Lines an Analysis reports.
        public var multiPV: Int

        public init(threads: Int? = nil, hashMegabytes: Int = 256, multiPV: Int = 3) {
            self.threads = threads ?? max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
            self.hashMegabytes = hashMegabytes
            self.multiPV = multiPV
        }
    }

    public enum StartupFailure: Error, Hashable, Sendable {
        /// A weights file was not where it was said to be.
        case networkMissing
        /// Present, but too small to be a net — a truncated download, most likely.
        case networkTooSmall
        case allocationFailed
        case unknown
    }

    /// How long the engine is allowed to think, and what ends the search.
    public enum Budget: Hashable, Sendable {
        /// Deepen until told to stop. What the Analysis screen uses.
        case untilStopped
        /// Mirrored Time: think for about as long as the player took.
        case time(Duration)
        case depth(Int)
        case nodes(UInt64)
    }

    private let handle: EngineHandle
    private let queue = DispatchQueue(label: "com.sunfmin.chessfen.engine")
    private let sink = Mutex(Sink())

    /// A `CfEngine *` that may cross a queue boundary. Unchecked rather than hopeful: the
    /// pointer is created once, freed once, and every call through it is made on the serial
    /// queue below — which is the invariant that earns the annotation.
    private struct EngineHandle: @unchecked Sendable {
        let pointer: OpaquePointer
    }

    /// What the running search reports to.
    ///
    /// `generation` is what makes superseding safe. A stream that has gone away asks the
    /// engine to stop, and it must not stop whatever search has started since — so it says
    /// which search it meant.
    private struct Sink {
        var generation: UInt64 = 0
        var onInfo: (@Sendable (CfSearchInfo) -> Void)?
        var onFinish: (@Sendable () -> Void)?
    }

    private let generations = Atomic<UInt64>(0)

    public init(
        bigNetURL: URL, smallNetURL: URL, configuration: Configuration = Configuration()
    ) throws {
        cf_global_init()
        var status = CF_ENGINE_OK
        let created = bigNetURL.withUnsafeFileSystemRepresentation { big in
            smallNetURL.withUnsafeFileSystemRepresentation { small in
                cf_engine_create(big, small, &status)
            }
        }
        guard let created else { throw StartupFailure(status) }
        handle = EngineHandle(pointer: created)
        apply(configuration)
    }

    deinit {
        cf_engine_destroy(handle.pointer)
    }

    /// Changing this takes effect on the next search; Stockfish rebuilds its thread pool
    /// and table as the options are set, so it is not something to do mid-game.
    public func apply(_ configuration: Configuration) {
        setOption("Threads", "\(max(1, configuration.threads))")
        setOption("Hash", "\(max(1, configuration.hashMegabytes))")
        setOption("MultiPV", "\(max(1, configuration.multiPV))")
    }

    @discardableResult
    public func setOption(_ name: String, _ value: String) -> Bool {
        cf_engine_set_option(handle.pointer, name, value)
    }

    // -------------------------------------------------------------- analysis

    /// Deepening Analysis of the Game's current Position, one snapshot per Depth.
    ///
    /// The stream ends when the search stops — because `stop()` was called, because the
    /// budget ran out, or because the consuming task went away. Ending the loop *is* the way
    /// to end an unbounded Analysis: the stream's termination handler stops the engine, so a
    /// screen that is dismissed takes its search with it.
    ///
    /// There is one engine, so there is one search. Asking for another supersedes the first:
    /// the running search is stopped, waited for, and its stream finished before this one
    /// installs itself, all in that order on the serial queue. Callers therefore cannot
    /// interleave two searches however hard they try, and no stream is ever left hanging.
    public func analyse(_ game: Game, budget: Budget = .untilStopped) -> AsyncStream<Analysis> {
        let startFEN = game.startFEN
        let moves = game.uciMoves
        let state = game.state
        let perspective = state.sideToMove
        let generation = generations.wrappingAdd(1, ordering: .relaxed).newValue

        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.stopSearch(generation)
            }

            queue.async { [self] in
                // Wind up whatever was running before touching the sink: `wait` is the
                // guarantee that no more of the old search's callbacks are in flight, so
                // the old and new streams cannot be crossed.
                cf_engine_stop(handle.pointer)
                cf_engine_wait(handle.pointer)

                // Accumulates the MultiPV lines of one Depth, then emits them together.
                let group = Mutex(DepthGroup())
                let emit: @Sendable () -> Void = {
                    let ready: Analysis? = group.withLock { $0.take() }
                    if let ready { continuation.yield(ready) }
                }

                let superseded = sink.withLock { current -> Sink in
                    let previous = current
                    current = Sink(
                        generation: generation,
                        onInfo: { info in
                            let line = Line(info, in: state, perspective: perspective)
                            let flush = group.withLock { $0.absorb(info, line: line) }
                            if flush { emit() }
                        },
                        onFinish: {
                            emit()
                            continuation.finish()
                        }
                    )
                    return previous
                }
                superseded.onFinish?()

                let started = withCStrings(moves) { pointers in
                    var limits = budget.cLimits
                    return cf_engine_go(
                        handle.pointer, startFEN, pointers,
                        Int32(moves.count), &limits,
                        Unmanaged.passUnretained(self).toOpaque(),
                        { context, info in
                            guard let context, let info else { return }
                            let service = Unmanaged<EngineService>
                                .fromOpaque(context).takeUnretainedValue()
                            service.sink.withLock { $0.onInfo }?(info.pointee)
                        },
                        { context, _, _ in
                            guard let context else { return }
                            let service = Unmanaged<EngineService>
                                .fromOpaque(context).takeUnretainedValue()
                            service.sink.withLock { $0.onFinish }?()
                        }
                    )
                }
                // An unusable position starts nothing, and says so by ending the stream
                // rather than leaving the caller waiting for a snapshot that never comes.
                if !started {
                    sink.withLock { current in
                        if current.generation == generation { current = Sink() }
                    }
                    continuation.finish()
                }
            }
        }
    }

    /// Stops the search this generation started, and only that one.
    private func stopSearch(_ generation: UInt64) {
        let isCurrent = sink.withLock { $0.generation == generation }
        guard isCurrent else { return }
        cf_engine_stop(handle.pointer)
    }

    /// The Best Move for the Game, thought about for as long as the budget allows.
    ///
    /// This is what the engine plays with when it holds a Controller. `budget` carries
    /// Mirrored Time; the engine is never handicapped, so how well it plays is entirely a
    /// question of how long it was given.
    public func bestMove(for game: Game, budget: Budget) async -> Move? {
        var last: Analysis?
        for await analysis in analyse(game, budget: budget) { last = analysis }
        guard let uci = last?.bestMove else { return nil }
        return game.state.move(matching: uci)
    }

    /// The Score of a Game's current Position at one Depth, and nothing else — the
    /// baseline a Review needs for its first move, which has no ply before it to compare
    /// against.
    public func evaluate(_ game: Game, budget: Budget) async -> Score? {
        var last: Analysis?
        for await analysis in analyse(game, budget: budget) { last = analysis }
        return last?.best?.score
    }

    /// Re-scores every Position of a finished Game at one uniform Depth.
    ///
    /// Uniform is the whole point (see Review in CONTEXT.md): the Scores an Analysis
    /// happened to reach depend on how long each position was looked at, so they cannot be
    /// compared with each other. These can. The returned array has one entry per ply,
    /// each being the Score *after* that ply.
    ///
    /// `onPly` reports each Score as it lands, because a Review of a long game is a wait
    /// worth showing progress through rather than a spinner. It is called from the engine's
    /// queue, so anything it touches must be ready for that.
    public func review(
        _ game: Game, depth: Int, onPly: (@Sendable (Int, Score?) -> Void)? = nil
    ) async -> [Score?] {
        guard !game.plies.isEmpty else { return [] }
        var scores: [Score?] = []
        for ply in 1...game.plies.count {
            guard let position = game.rewound(to: ply) else {
                scores.append(nil)
                onPly?(ply - 1, nil)
                continue
            }
            var best: Analysis?
            for await analysis in analyse(position, budget: .depth(depth)) { best = analysis }
            scores.append(best?.best?.score)
            onPly?(ply - 1, best?.best?.score)
            if Task.isCancelled { break }
        }
        return scores
    }

    /// Asks the running search to wind up. It still reports its best move, which is how an
    /// unbounded Analysis produces a final answer.
    public func stop() {
        cf_engine_stop(handle.pointer)
    }

    /// Waits for the running search to finish reporting. Blocking, so it goes on the queue.
    public func waitForSearchToFinish() async {
        await withCheckedContinuation { continuation in
            queue.async { [handle] in
                cf_engine_wait(handle.pointer)
                continuation.resume()
            }
        }
    }

    /// Forgets the transposition table and history. The honest thing to do before a Review,
    /// so an earlier Analysis of the same position cannot make one ply look deeper than the
    /// uniform Depth asked for.
    public func clear() async {
        await withCheckedContinuation { continuation in
            queue.async { [handle] in
                cf_engine_clear(handle.pointer)
                continuation.resume()
            }
        }
    }
}

// ------------------------------------------------------------------ plumbing

/// Collects the MultiPV lines belonging to one Depth.
private struct DepthGroup {
    private var depth = 0
    private var selectiveDepth = 0
    private var nodes: UInt64 = 0
    private var nodesPerSecond: UInt64 = 0
    private var timeMilliseconds: UInt64 = 0
    private var hashFull = 0
    private var isPartial = false
    private var lines: [Int: Line] = [:]

    /// Absorbs one info line; returns true when the *previous* Depth is complete and should
    /// be emitted before this one is filled in.
    mutating func absorb(_ info: CfSearchInfo, line: Line) -> Bool {
        // Stockfish walks multipv 1...N within a Depth, so index 1 opens a new group.
        let opensGroup = Int(info.multiPvIndex) <= 1 && !lines.isEmpty
        if opensGroup { pending = snapshot() }
        if opensGroup || Int(info.depth) != depth {
            if !opensGroup, !lines.isEmpty { pending = snapshot() }
            lines.removeAll()
            isPartial = false
        }
        depth = Int(info.depth)
        selectiveDepth = max(selectiveDepth, Int(info.selectiveDepth))
        nodes = info.nodes
        nodesPerSecond = info.nodesPerSecond
        timeMilliseconds = info.timeMs
        hashFull = Int(info.hashFull)
        if info.isBound { isPartial = true }
        lines[Int(info.multiPvIndex)] = line
        return pending != nil
    }

    private var pending: Analysis?

    /// The completed Depth, if one is waiting; otherwise whatever has been collected.
    mutating func take() -> Analysis? {
        if let ready = pending {
            pending = nil
            return ready
        }
        guard !lines.isEmpty else { return nil }
        return snapshot()
    }

    private func snapshot() -> Analysis {
        Analysis(
            depth: depth,
            selectiveDepth: selectiveDepth,
            lines: lines.sorted { $0.key < $1.key }.map(\.value),
            nodes: nodes,
            nodesPerSecond: nodesPerSecond,
            timeMilliseconds: timeMilliseconds,
            hashFull: hashFull,
            isPartial: isPartial
        )
    }
}

extension Line {
    /// One reported variation, turned into something a player can read.
    ///
    /// This is where the White-relative rule is enforced: Stockfish scores from the point of
    /// view of whoever is to move at the root, so a black-to-move position comes back with
    /// its sign inverted, and the flip happens here and nowhere else.
    init(_ info: CfSearchInfo, in state: GameState, perspective: PieceColour) {
        let sign = perspective == .white ? 1 : -1
        if info.isMate {
            // Stockfish counts plies, positive meaning the side to move delivers it.
            let plies = Int(info.matePlies)
            let moves = plies > 0 ? (plies + 1) / 2 : plies / 2
            score = .mate(in: sign * moves)
        } else {
            score = .centipawns(sign * Int(info.centipawns))
        }

        let text = withUnsafeBytes(of: info.pv) { bytes in
            String(decoding: Array(bytes.prefix { $0 != 0 }), as: UTF8.self)
        }
        uciMoves = text.split(separator: " ").map(String.init)

        // SAN needs the position each move is played from, so the line is replayed.
        var walked = Game(startFEN: state.fen)
        var written: [String] = []
        for move in uciMoves {
            guard var game = walked, game.apply(uci: move), let last = game.plies.last else {
                break
            }
            written.append(last.san)
            walked = game
        }
        san = written
    }
}

extension EngineService.Budget {
    var cLimits: CfSearchLimits {
        var limits = CfSearchLimits(movetimeMs: 0, depth: 0, nodes: 0)
        switch self {
        case .untilStopped:
            break
        case .time(let duration):
            let milliseconds =
                duration.components.seconds * 1000
                + duration.components.attoseconds / 1_000_000_000_000_000
            limits.movetimeMs = Int32(clamping: milliseconds)
        case .depth(let depth):
            limits.depth = Int32(clamping: depth)
        case .nodes(let nodes):
            limits.nodes = nodes
        }
        return limits
    }
}

extension EngineService.StartupFailure {
    init(_ status: CfEngineStatus) {
        switch status {
        case CF_ENGINE_NET_MISSING: self = .networkMissing
        case CF_ENGINE_NET_TOO_SMALL: self = .networkTooSmall
        case CF_ENGINE_ALLOC_FAILED: self = .allocationFailed
        default: self = .unknown
        }
    }
}
