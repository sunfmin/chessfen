import ChessfenKit

/// The engine, as the screens ask for it.
///
/// There is still exactly one engine in the app and it is still `EngineService` (docs/adr/0009);
/// this changes nothing about that. It exists so a screen can be *put* into a state instead of
/// having to be played into one: a screenshot test hands the screens an engine that reports a
/// fixed Analysis, and everything above the seam — `retune`, `record`, the Score written against
/// a ply, every view — is the real one. The alternative is to photograph a screen by loading
/// 112 MiB of weights and waiting on a search whose numbers are different every run, which is
/// not a picture anyone can compare against last week's.
///
/// The whole of what the app asks of an engine, and no more: analysis for the game screen,
/// evaluate/review/clear for the Review, and the pause gate for the app leaving the front.
protocol Engine: AnyObject, Sendable {
    var isPaused: Bool { get }
    func analyse(_ game: Game, budget: EngineService.Budget) -> AsyncStream<Analysis>
    func stop()
    func pause()
    func resume()
    func clear() async
    func evaluate(_ game: Game, budget: EngineService.Budget) async -> Score?
    func review(
        _ game: Game, depth: Int, onPly: (@Sendable (Int, Score?) -> Void)?
    ) async -> [Score?]
}

extension EngineService: Engine {}
