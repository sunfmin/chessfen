import ChessfenKit
import SwiftUI

/// One Review in progress: every ply re-scored at one uniform Depth.
///
/// A class rather than view state because the engine reports each ply from its own queue,
/// and something main-actor isolated has to be on the receiving end of that.
@Observable final class ReviewRun {
    private(set) var scores: [Score?] = []
    /// The Score of the starting position — what the first move is compared against.
    private(set) var baseline: Score?
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var isRunning = false

    func start(service: any Engine, game: Game, depth: Int) async {
        guard !isRunning else { return }
        isRunning = true
        total = game.plies.count
        completed = 0
        scores = Array(repeating: nil, count: total)

        // A Review's Scores are only comparable if nothing was learned at a greater Depth
        // first, and the game screen has been analysing the same positions unbounded.
        await service.clear()
        if let start = game.rewound(to: 0) {
            baseline = await service.evaluate(start, budget: .depth(depth))
        }
        let final = await service.review(game, depth: depth) { [weak self] index, score in
            Task { @MainActor in self?.record(index, score) }
        }
        scores = final
        completed = total
        isRunning = false
    }

    private func record(_ index: Int, _ score: Score?) {
        guard scores.indices.contains(index) else { return }
        scores[index] = score
        completed = max(completed, index + 1)
    }

    /// The Score after `ply` moves — index 0 being the position the game started from.
    func score(atPly ply: Int) -> Score? {
        ply == 0 ? baseline : scores.indices.contains(ply - 1) ? scores[ply - 1] : nil
    }
}

struct ReviewScreen: View {
    let session: GameSession

    @Environment(EngineHost.self) private var engine

    @State private var run = ReviewRun()
    @State private var ply = 0
    @State private var depth = 14
    @State private var task: Task<Void, Never>?

    private var game: Game { session.game }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                curve
                progressRow
                board
                plyDetail
                stepper
                depthPicker
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("复盘")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ply = game.plies.count
            begin()
        }
        .onDisappear {
            task?.cancel()
            engine.service?.stop()
        }
    }

    // ------------------------------------------------------------------ parts

    private var curve: some View {
        EvalCurve(
            plies: game.plies.count,
            score: { run.score(atPly: $0) },
            selected: $ply
        )
        .frame(height: 120)
    }

    @ViewBuilder private var progressRow: some View {
        if run.isRunning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在用深度 \(depth) 重算：\(run.completed)/\(max(run.total, 1))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if !engine.isReady {
            Text("引擎不可用，无法复盘。").font(.footnote).foregroundStyle(.orange)
        } else if run.total > 0 {
            Text("已按统一深度 \(depth) 重算完，曲线上的每一点都可以互相比较。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var board: some View {
        BoardView(
            pieces: BoardRenderer.placement(position.state.fen) ?? [:],
            orientation: session.orientation,
            lastMove: lastMove,
            checks: position.state.inCheck ? Set(position.state.checkers) : [],
            coordinates: true,
            isInteractive: false
        )
    }

    @ViewBuilder private var plyDetail: some View {
        let quality = qualityOfCurrentPly
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(plyTitle).font(.subheadline.weight(.medium))
            if let quality, quality != .fine {
                Text(quality.label)
                    .font(.footnote.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (quality == .blunder ? Color.red : Color.orange).opacity(0.2),
                        in: Capsule()
                    )
            }
            Spacer()
            ScoreCell(score: run.score(atPly: ply), prominent: true)
        }
    }

    private var stepper: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { Double(ply) },
                    set: { ply = Int($0.rounded()) }
                ),
                in: 0...Double(max(game.plies.count, 1)),
                step: 1
            )
            HStack {
                Button {
                    ply = max(0, ply - 1)
                } label: {
                    Label("上一手", systemImage: "chevron.left").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(ply == 0)

                Button {
                    ply = min(game.plies.count, ply + 1)
                } label: {
                    Label("下一手", systemImage: "chevron.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(ply >= game.plies.count)
            }
        }
    }

    private var depthPicker: some View {
        HStack {
            Text("深度").font(.subheadline)
            Picker("深度", selection: $depth) {
                ForEach([10, 14, 18, 22], id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.segmented)
            .disabled(run.isRunning)
            Button("重算") { begin() }
                .disabled(run.isRunning || !engine.isReady)
        }
    }

    // ------------------------------------------------------------------ doing

    private func begin() {
        guard let service = engine.service, !game.plies.isEmpty else { return }
        task?.cancel()
        let game = self.game
        let depth = self.depth
        task = Task {
            await run.start(service: service, game: game, depth: depth)
            guard !Task.isCancelled else { return }
            // A Review's Scores replace the real-time ones in the saved game, because they
            // are the comparable set (docs/adr/0009).
            session.applyReview(run.scores)
        }
    }

    private var position: Game {
        game.rewound(to: ply) ?? game
    }

    private var lastMove: MoveSquares? {
        guard ply > 0 else { return nil }
        return game.plies[safe: ply - 1].flatMap { MoveSquares(uci: $0.uci) }
    }

    private var plyTitle: String {
        guard ply > 0, let played = game.plies[safe: ply - 1] else { return "起始局面" }
        let number = (ply + 1) / 2
        return "第 \(number) 回合 \(moverOfPly(ply).chinese) \(played.san)"
    }

    private var qualityOfCurrentPly: MoveQuality? {
        guard ply > 0 else { return nil }
        return MoveQuality.of(
            move: moverOfPly(ply),
            before: run.score(atPly: ply - 1),
            after: run.score(atPly: ply)
        )
    }

    /// Who played the `ply`th move, counting from one. Not always White: a recognised
    /// position may well have started with Black to move.
    private func moverOfPly(_ ply: Int) -> PieceColour {
        let startedWith: PieceColour =
            game.startFEN.split(separator: " ").dropFirst().first == "b" ? .black : .white
        return ply.isMultiple(of: 2) ? startedWith.opposite : startedWith
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// The eval curve: one point per ply, White above the line and Black below it.
struct EvalCurve: View {
    let plies: Int
    let score: (Int) -> Score?
    @Binding var selected: Int

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in draw(into: &context, size: size) }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard plies > 0, proxy.size.width > 0 else { return }
                            let fraction = min(max(value.location.x / proxy.size.width, 0), 1)
                            selected = Int((fraction * Double(plies)).rounded())
                        }
                )
        }
    }

    private func draw(into context: inout GraphicsContext, size: CGSize) {
        guard plies > 0 else { return }
        let step = size.width / CGFloat(plies)
        func point(_ ply: Int) -> CGPoint {
            let fraction = advantageFraction(score(ply))
            return CGPoint(x: CGFloat(ply) * step, y: size.height * (1 - fraction))
        }

        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(.secondary.opacity(0.12))
        )
        var middle = Path()
        middle.move(to: CGPoint(x: 0, y: size.height / 2))
        middle.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        context.stroke(middle, with: .color(.secondary.opacity(0.5)), lineWidth: 1)

        // Only as far as the Review has actually got: a curve drawn through positions
        // nobody has scored yet would be a flat line pretending to be a finding.
        let known = (0...plies).filter { score($0) != nil }
        guard let first = known.first, known.count > 1 else { return }

        var line = Path()
        line.move(to: point(first))
        for ply in known.dropFirst() { line.addLine(to: point(ply)) }

        var area = line
        area.addLine(to: CGPoint(x: point(known.last!).x, y: size.height / 2))
        area.addLine(to: CGPoint(x: point(first).x, y: size.height / 2))
        area.closeSubpath()
        context.fill(area, with: .color(.accentColor.opacity(0.18)))
        context.stroke(
            line, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineJoin: .round)
        )

        var marker = Path()
        marker.move(to: CGPoint(x: CGFloat(selected) * step, y: 0))
        marker.addLine(to: CGPoint(x: CGFloat(selected) * step, y: size.height))
        context.stroke(marker, with: .color(.primary.opacity(0.6)), lineWidth: 1.5)
    }
}
