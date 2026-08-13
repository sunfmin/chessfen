import ChessfenKit
// For `onReceive` only: the sound setting travels through iCloud, and a notification is how a
// device hears that another one has changed it.
import Combine
import SwiftUI

/// The board, what the engine makes of it, and the few things you do to it.
///
/// No scrolling: the board is the hero and it has to sit still under a navigation bar, not slide
/// beneath it. Everything else is a strip of fixed height below it, and the board takes whatever
/// is left over — which on a small phone means a slightly smaller board rather than a screen
/// that has to be dragged.
struct GameScreen: View {
    let session: GameSession
    @Binding var path: [Step]

    @Environment(EngineHost.self) private var engine
    @Environment(GameLibrary.self) private var library

    @State private var selected: Square?
    @State private var promotion: PromotionRequest?
    @State private var isSoundOn = Sounds.current.isSoundOn
    /// Nil until somebody opens or closes the setup chips themselves, and then it is their answer
    /// that stands for as long as the screen does. Until then the game decides: see `setup`.
    @State private var isSetupOpenByHand: Bool?
    /// Whether a thumb is on 让引擎走 right now. The engine is thinking for exactly as long as it is.
    @State private var isAsking = false
    /// How tall the window under the board is, and how tall the page in it turned out to be — the
    /// record fills the first, and the difference is what says whether anything is out of sight
    /// (see `body`).
    @State private var readHeight: CGFloat = 0
    @State private var pageHeight: CGFloat = 0

    private var isSetupOpen: Bool { isSetupOpenByHand ?? session.game.plies.isEmpty }

    struct PromotionRequest: Identifiable {
        let id = UUID()
        let moves: [Move]
    }

    var body: some View {
        GeometryReader { proxy in
            let side = Self.boardSide(in: proxy.size)
            VStack(spacing: 0) {
                header
                board.frame(width: side, height: side)
                // No bar while practising. Empty, it sits exactly half white and reads as a
                // considered 0.00 — the most misleading thing this screen could show someone who
                // has asked not to be told.
                if !session.isPractising {
                    EvalBar(
                        score: session.analysis?.best?.score,
                        orientation: session.orientation,
                        finish: finish
                    )
                    .frame(width: side)
                    .padding(.top, 7)
                }
                // What there is to read: what the engine makes of the position, and what has been
                // played. The board is outside it, which is what keeps it from sliding under the
                // navigation bar or changing size when a third line appears.
                //
                // A page at least as tall as its window, so the record inside it can take the slack
                // a big phone has left over rather than leaving a hole above the controls — and
                // taller than the window when there is more to say than fits, which is when it
                // becomes a scroll again.
                ScrollView {
                    VStack(spacing: 0) {
                        series
                        corrections
                        engineLines
                        variations
                        notation
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
                    .frame(minHeight: readHeight, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { readHeight = $0 }
                // Faded off at the bottom, and only when there is more page than window — a line cut
                // in half by the edge of the deck reads as a mistake, and the same line fading out
                // reads as what it is. Never while it all fits, or the last move played would be
                // the one drawn dimmest.
                .mask {
                    VStack(spacing: 0) {
                        Rectangle()
                        // A line's worth of fade, in points rather than a fraction of the window:
                        // it is at its most squeezed that the cut needs explaining, and a fraction
                        // of a squeezed window is a fade too small to read as one.
                        if pageHeight > readHeight + 1 {
                            LinearGradient(
                                colors: [.black, .black.opacity(0.04)],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 26)
                        }
                    }
                }
                // And what there is to do, held out of the scroll at the bottom of the screen.
                deck
            }
            .frame(maxWidth: .infinity)
        }
        .background(Palette.parchment)
        .navigationTitle("对局")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.parchment, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(Palette.analysis)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        path.append(.review(session))
                    } label: {
                        Label("复盘", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    // Here rather than under the board, where it used to be the widest button on
                    // the screen. Taking a move off is not how a game is read — 最初 and 上一步 go
                    // back through it without touching it, and playing something else from where
                    // you stopped keeps what it replaced (a Variation). What is left for this is
                    // the honest case: a move played by mistake, which is rare and belongs here.
                    Button {
                        selected = nil
                        session.undo()
                    } label: {
                        Label("悔棋", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!session.isAtLatest || session.game.plies.isEmpty)
                    Button {
                        path.append(.confirm(PositionProposal(reopening: session)))
                    } label: {
                        Label("改棋子", systemImage: "hand.point.up.left")
                    }
                    Toggle(isOn: $isSoundOn) {
                        Label("音效", systemImage: isSoundOn ? "speaker.wave.2" : "speaker.slash")
                    }
                    if let url = session.url {
                        ShareLink(item: url) {
                            Label("导出 PGN", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            // Re-attached on every appearance: the engine may have finished starting while the
            // library was on screen, and coming back from a Review means the search this screen
            // wants is not the one that just ran.
            session.attach(engine: engine.service, library: library)
            session.retune()
        }
        .onDisappear { session.suspend() }
        .onChange(of: isSoundOn) { _, isOn in Sounds.current.isSoundOn = isOn }
        // The setting travels between devices (docs/adr/0012), so it can change while this
        // screen is the one on show — and a toggle that disagrees with the sound is worse than
        // no toggle.
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
            isSoundOn = Sounds.current.isSoundOn
        }
        .onChange(of: engine.isReady) { _, ready in
            guard ready else { return }
            session.attach(engine: engine.service, library: library)
            session.retune()
        }
        // The Analysis this screen wants is unbounded, and the engine will not start one while
        // the app is away — so leaving is a suspend and coming back is a fresh `retune`, not a
        // search that was left running underneath. `EngineHost.isActive` rather than the scene
        // phase, so there is one answer to when that is.
        .onChange(of: engine.isActive) { _, active in
            if active {
                session.retune()
            } else {
                session.suspend()
            }
        }
        .confirmationDialog(
            "升变成什么？", isPresented: .constant(promotion != nil), titleVisibility: .visible
        ) {
            ForEach(promotion?.moves ?? [], id: \.uci) { move in
                Button(move.promotion?.chinese ?? move.uci) {
                    session.play(move)
                    promotion = nil
                }
            }
            Button("取消", role: .cancel) { promotion = nil }
        }
    }

    // ------------------------------------------------------------------ parts

    /// Who is on the clock, and what the engine currently thinks of it.
    ///
    /// Two lines: the state of the game and the number share a baseline, so the eye reads them
    /// as one sentence; everything about how the number was arrived at sits under it.
    private var header: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(viewed.chineseTurn).eyebrow()
                if viewed.state.inCheck, !viewed.isOver {
                    Text("被将")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.alarm)
                }
                Spacer(minLength: 8)
                if session.isPractising {
                    // Where the number lives, so its absence is accounted for rather than just an
                    // empty corner someone reads as a broken engine.
                    HStack(spacing: 5) {
                        Image(systemName: "eye.slash").font(.caption)
                        Text("练习").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(Palette.inkSoft)
                } else if let finish {
                    // The number people have been watching, resolved: a finished game has no Score
                    // to show, and what belongs in its place is the one it ended on.
                    Text(finish.scoreline)
                        .font(.clock(32))
                        .foregroundStyle(Palette.ink)
                } else {
                    Text(headlineScore?.displayText ?? "—")
                        .font(.clock(32))
                        .foregroundStyle(headlineScore == nil ? Palette.inkSoft : Palette.analysis)
                        .contentTransition(.numericText())
                }
            }

            HStack(spacing: 8) {
                if session.isThinking {
                    // Mirrored Time means the engine takes about as long as the player just did,
                    // which is right most of the time and longer than anyone wants to sit through
                    // the rest of it. Stopping the search does not change which move it picks; it
                    // just stops waiting.
                    Button { session.moveNow() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "forward.fill").font(.caption2)
                            Text("马上走").font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(Palette.parchment)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Palette.analysis, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if !session.isAtLatest {
                    Button {
                        selected = nil
                        session.jumpToLatest()
                    } label: {
                        Text("在看第 \(session.cursor)/\(session.game.plies.count) 步 · 回到最新")
                            .font(.caption)
                            .foregroundStyle(Palette.analysis)
                    }
                    .buttonStyle(.plain)
                } else if engine.unavailableReason != nil {
                    Text("没有引擎").font(.caption).foregroundStyle(Palette.alarm)
                }
                Spacer(minLength: 4)
                SearchMeter(analysis: session.analysis)
            }
            .frame(height: 18)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    /// What the number at the top says. The engine's view of the position on screen, or nothing
    /// at all until it has one — never a stale number from the previous position.
    private var headlineScore: Score? { session.analysis?.best?.score }

    /// How the game on screen ended, if it has.
    ///
    /// A finished game has no Score: there is nothing left to search, so the engine says nothing and
    /// the bar would sit exactly half and half — the same picture it shows for a position nobody has
    /// looked at yet, and the opposite of the truth when someone has just been mated.
    private var finish: EvalBar.Finish? {
        switch viewed.state.outcome {
        case .ongoing: nil
        case .checkmate: .won(viewed.state.sideToMove.opposite)
        default: .drawn
        }
    }

    /// How big the board is, and it depends on the screen and nothing else.
    ///
    /// It used to take whatever height was left over, which meant the board changed size when the
    /// engine found a third line to show — the one thing on this screen that must never move. So
    /// it is sized from the width, all but full bleed, and only shrinks on a screen too short to
    /// leave anything for the panel underneath. Rounded to a multiple of eight so every square is
    /// a whole number of points and no grid line lands on a half pixel.
    static func boardSide(in size: CGSize) -> CGFloat {
        let byWidth = size.width - 16
        let byHeight = max(240, size.height - 300)
        return (min(byWidth, byHeight) / 8).rounded(.down) * 8
    }

    private var board: some View {
        BoardView(
            pieces: pieces,
            orientation: session.orientation,
            lastMove: session.lastMove,
            checks: viewed.state.checkSquares,
            // The doubtful squares stay ringed on the board being played on, right up until the
            // first move — which is what replaces the old gate: the reading's own uncertainty is
            // visible where it matters, and 改棋子 is one tap away (docs/adr/0011).
            suspects: session.unconfirmedSquares,
            selected: selected,
            destinations: Set(candidateMoves.map(\.to)),
            captures: Set(candidateMoves.filter(\.isCapture).map(\.to)),
            recommendation: recommendation,
            isInteractive: session.isHandTurn,
            onTap: tap
        )
    }

    /// Where this game sits in its collection, and the way to the next one.
    ///
    /// Working through a set is the reason collections exist, and going back to the library between
    /// every position is the thing that makes anyone stop. The order is the library's own — by name
    /// — read fresh each time rather than captured when the game opened, so renaming a game during a
    /// session moves it where you just said it goes.
    @ViewBuilder private var series: some View {
        if let collection = session.collection, let place = placeInSeries {
            HStack(spacing: 10) {
                seriesButton("上一局", symbol: "chevron.left", at: place.index - 1)
                VStack(spacing: 1) {
                    Text(collection)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("第 \(place.index + 1)/\(place.entries.count) 局")
                        .font(.caption2)
                        .foregroundStyle(Palette.inkSoft)
                }
                .frame(maxWidth: .infinity)
                seriesButton("下一局", symbol: "chevron.right", at: place.index + 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Palette.chipRest, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    private func seriesButton(_ label: String, symbol: String, at index: Int) -> some View {
        let target = placeInSeries?.entries[safe: index]
        return Button {
            if let target { drill(to: target) }
        } label: {
            HStack(spacing: 3) {
                if symbol == "chevron.left" { Image(systemName: symbol).font(.caption2) }
                Text(label).font(.caption.weight(.semibold))
                if symbol == "chevron.right" { Image(systemName: symbol).font(.caption2) }
            }
            .foregroundStyle(target == nil ? Palette.inkSoft : Palette.analysis)
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .opacity(target == nil ? 0.4 : 1)
    }

    /// The games in this one's collection, and which one this is. Nil for a game that is not in a
    /// collection, or one not yet written to disk — there is nothing to be next to.
    private var placeInSeries: (entries: [GameLibrary.Entry], index: Int)? {
        guard let collection = session.collection, let url = session.url,
            let entries = library.collections.first(where: { $0.name == collection })?.entries,
            let index = entries.firstIndex(where: { $0.url == url })
        else { return nil }
        return (entries, index)
    }

    /// The way back to the editor, shown as a job to do rather than hidden in a menu — a piece
    /// read wrong is the one thing about a photographed game that has to be easy to fix.
    @ViewBuilder private var corrections: some View {
        if session.canEditPosition {
            Button {
                path.append(.confirm(PositionProposal(reopening: session)))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: session.shaky.isEmpty ? "hand.point.up.left" : "questionmark.circle")
                    Text(correctionText)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text("改棋子").font(.footnote.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .foregroundStyle(session.shaky.isEmpty ? Palette.ink : Palette.alarm)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    (session.shaky.isEmpty ? Palette.chipRest : Palette.alarm.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    private var correctionText: String {
        session.shaky.shakySummary ?? "照片认错了棋子？"
    }

    /// What the engine is looking at, three lines deep. A fixed height, because the lines change
    /// several times a second as the search deepens and a moving layout would be unreadable.
    private var engineLines: some View {
        VStack(alignment: .leading, spacing: 5) {
            // First, and ahead of the game being over: someone practising has asked for this space
            // to be quiet, and what belongs in it instead is where the comparison happens.
            if session.isPractising {
                Text(
                    viewed.isOver
                        ? "这局走完了。去「复盘」，引擎会把每一步重新打一遍分。"
                        : "练习中，引擎不给意见。走完用「复盘」跟它对一遍。"
                )
                .font(.footnote)
                .foregroundStyle(Palette.inkSoft)
            } else if let analysis = session.analysis, !analysis.lines.isEmpty {
                ForEach(Array(analysis.lines.prefix(3).enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        ScoreCell(score: line.score, prominent: index == 0)
                            .frame(width: 56, alignment: .leading)
                        Text(line.san.prefix(8).joined(separator: " "))
                            .font(.notation)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(index == 0 ? Palette.ink : Palette.inkSoft)
                    }
                }
            } else if viewed.isOver {
                // The result is at the top and on the bar; what is left to say is what to do next.
                Text("这局走完了。去「复盘」看每一步的得失。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
            } else if let reason = engine.unavailableReason {
                Text(reason).font(.footnote).foregroundStyle(Palette.alarm)
            } else {
                Text("引擎在算").font(.footnote).foregroundStyle(Palette.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        // The recommendation keeps changing as the search deepens, and that is the point
        // (docs/adr/0009) — so it must not make the layout jump while it does.
        .animation(.none, value: session.analysis?.depth)
    }

    /// The moves, set on the page rather than in a card: it is a record, not a control.
    ///
    /// The tallest thing under the board, because it is the only thing down there that grows: three
    /// or four lines of a game where there used to be one, and the slack a big phone has left over
    /// goes here rather than into a gap above the controls.
    private var notation: some View {
        ScrollView {
            Text(notationText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The end of the game, but only once there is more of it than fits: anchoring the
        // alignment as well would hold a four-move game against the bottom of the box and leave a
        // hole under the engine's lines. So the offset starts at the end and stays there as moves
        // are added, and a short game simply sits where it is written.
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        // No minimum: on a short phone with a correction to make and the setup chips open there is
        // very little left, and a record that insisted on 74 points would push the deck off the
        // bottom of the screen. It compresses to a line and scrolls instead.
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5).padding(.horizontal, 16)
        }
    }

    /// Everything you do to the game, at the bottom of the screen where a thumb is.
    ///
    /// It is held out of the scroll and given the raised colour, which makes one honest division of
    /// the screen: above the line is what there is to look at — the board, the number, the lines,
    /// the moves — and below it is what there is to press. The walk through a game is the control
    /// used most on this screen, and it used to be the one a drag could hide.
    private var deck: some View {
        VStack(spacing: 9) {
            transport
            setup
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 2)
        .background(Palette.raised)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
    }

    /// Where the eye is looking, and the one thing that moves a piece.
    ///
    /// The three on the left are one control in three parts: 最初 is the same journey as 上一步 taken
    /// all the way, so they are built into one segmented block, and none of them changes the game
    /// by a single character. 让引擎走 stands apart because it is the opposite — it is the only
    /// button down here that plays a move, and it plays the one the arrow on the board is pointing
    /// at. It is here at all times, including before the first move, where "let it open" is a
    /// perfectly good way to start.
    private var transport: some View {
        HStack(spacing: 7) {
            // Nothing to walk through until something has been played.
            if !session.game.plies.isEmpty { browse }
            HoldButton(
                label: "让引擎走",
                symbol: "cpu",
                isHeld: isAsking,
                fill: Double(session.searchProgress?.depth ?? 0) / SearchMeter.deepEnough,
                isEnabled: session.canPlayBestMove,
                onPress: {
                    selected = nil
                    isAsking = true
                    session.beginAskedMove()
                },
                onRelease: {
                    isAsking = false
                    session.endAskedMove()
                }
            )
            .frame(width: session.game.plies.isEmpty ? nil : 104)
            .accessibilityLabel("让引擎走")
            .accessibilityHint("按住不放，引擎算得更深；松手就走")
        }
    }

    private var browse: some View {
        HStack(spacing: 1.5) {
                TransportButton(
                    label: "最初", symbol: "backward.end.fill", corners: .leading(11)
                ) {
                    selected = nil
                    session.jumpToStart()
                }
                .disabled(session.cursor == 0)
                .opacity(session.cursor == 0 ? 0.4 : 1)

                TransportButton(label: "上一步", symbol: "chevron.left", corners: .joined()) {
                    selected = nil
                    session.step(by: -1)
                }
                .disabled(session.cursor == 0)
                .opacity(session.cursor == 0 ? 0.4 : 1)

                TransportButton(
                    label: "下一步", symbol: "chevron.right", trailingSymbol: true,
                    corners: .trailing(11)
                ) {
                    selected = nil
                    session.step(by: 1)
                }
                .disabled(session.isAtLatest)
                .opacity(session.isAtLatest ? 0.4 : 1)
        }
    }

    /// Who plays which side, which way up the board is, and whether the engine talks.
    ///
    /// Said in words always, offered as chips on request. These are facts about the game in front
    /// of you rather than settings, so they stay on the screen — but they are decided once and then
    /// read for the rest of the game, and ten wooden pills standing under the board for an hour is
    /// a settings panel where a game should be. The line states every one of them; the chips that
    /// change them fold away.
    ///
    /// Open while there is nothing played yet, because that is when they are all still questions,
    /// and closed once a game is under way — until someone says otherwise, and then it is their
    /// answer that stands.
    private var setup: some View {
        VStack(alignment: .leading, spacing: 9) {
            // While the engine is being held, this line is the engine's: what it has spent and how
            // deep it has got, on the line directly under the thumb spending it. The line is the
            // same height either way, so nothing moves under the finger.
            if isAsking {
                Text(askedReadout)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Palette.analysis)
                    .lineLimit(1)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.22)) { isSetupOpenByHand = !isSetupOpen }
                } label: {
                    HStack(spacing: 6) {
                        Text(setupSummary)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 4)
                        Image(systemName: isSetupOpen ? "chevron.down" : "chevron.up")
                            .font(.caption2)
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSetupOpen ? "收起对局设置" : "打开对局设置")
                .accessibilityValue(setupSummary)
            }

            if isSetupOpen, !isAsking { setupChips }
        }
    }

    /// What a thumb on 让引擎走 is being told: what the engine has spent, how deep it has got, and
    /// how to finish. Before the first snapshot lands there is nothing to report but the bargain.
    private var askedReadout: String {
        guard let progress = session.searchProgress, progress.depth > 0 else {
            return "按住越久，算得越深 · 松手就走"
        }
        return String(
            format: "想了 %.1f 秒 · 深 %d/%d · 松手就走",
            progress.seconds, progress.depth, progress.selectiveDepth
        )
    }

    /// Everything the summary line says, in the order it says it.
    ///
    /// The engine's clock is in it whenever the engine is holding a Controller, because that is
    /// when it decides something — how long the next move takes — and the chips that set it are
    /// folded away for most of a game.
    private var setupSummary: String {
        var said = [
            "白方 \(session.controller(for: .white).chinese)",
            "黑方 \(session.controller(for: .black).chinese)",
        ]
        if session.isEnginePlaying { said.append(session.thinkingTime.chineseSummary) }
        said.append(session.orientation == .whiteAtBottom ? "白在下" : "黑在下")
        said.append(session.isPractising ? "自己练" : "看引擎")
        return said.joined(separator: " · ")
    }

    private var setupChips: some View {
        VStack(alignment: .leading, spacing: 9) {
            // White's player only means anything next to Black's, so they share a line.
            HStack(spacing: 10) {
                ForEach([PieceColour.white, .black], id: \.self) { colour in
                    ChipCluster(
                        title: colour.chinese,
                        options: Controller.allCases.map {
                            .init(
                                value: $0, label: $0.chinese,
                                isEnabled: $0 == .hand || engine.isReady
                            )
                        },
                        selection: session.controller(for: colour)
                    ) { controller in
                        session.setController(controller, for: colour)
                    }
                    if colour == .white { Spacer(minLength: 2) }
                }
            }

            // How long the engine gets over a move it plays for itself, and only while it is
            // holding a Controller — on a game two hands are playing there is nothing on this
            // clock. It is the only dial in the app: the engine is never handicapped, so time is
            // the whole of how hard it is playing (docs/adr/0009).
            //
            // 跟着我 is Mirrored Time, and it stands down when the engine is playing itself:
            // there is no player's last move to mirror, so the game names a clock instead.
            if session.isEnginePlaying {
                HStack(spacing: 10) {
                    ChipCluster(
                        title: "每步",
                        options: ThinkingTime.offered.map {
                            .init(
                                value: $0, label: $0.chinese,
                                isEnabled: $0 != .mirrored || !session.isSelfPlaying
                            )
                        },
                        selection: session.thinkingTime
                    ) { time in
                        session.setThinkingTime(time)
                    }
                    Spacer(minLength: 2)
                }
            }

            // What a game with nobody on the clock does, and how to stop it — which is the one
            // thing about self-play that is not on the screen already. Stepping back is a stop
            // because the engine only plays from the latest position, so browsing is where a
            // machine game is paused and 回到最新 is where it carries on.
            if session.isSelfPlaying {
                // One line's worth, because it sits between two rows of chips and a caption that
                // wraps there is a paragraph in the middle of a control panel.
                Text("双方都是引擎，程序自己走下去；翻回上一步就停")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Whether the engine talks, and which way up the board is. Those two say what the
            // engine does; flipping the board says nothing about the game at all, which is why it
            // is one button rather than a choice of two: the answer is already on the screen, in
            // the board itself.
            HStack(spacing: 10) {
                ChipCluster(
                    title: "意见",
                    options: [
                        .init(value: false, label: "看引擎", isEnabled: engine.isReady),
                        .init(value: true, label: "自己练"),
                    ],
                    selection: session.isPractising
                ) { practising in
                    session.setPractising(practising)
                }
                Spacer(minLength: 2)
                flip
            }

            // Last, and it is the one thing here that can throw a game away — which is what the
            // line underneath is for. It stays on offer for as long as the game lasts, because
            // whose move it was is a field no photograph could settle, and finding out it was
            // guessed wrong three moves later is the normal way to find out.
            HStack(spacing: 10) {
                ChipCluster(
                    title: "先走",
                    options: [
                        .init(
                            value: PieceColour.white, label: "白先走",
                            isEnabled: session.canStart(withSideToMove: .white)
                        ),
                        .init(
                            value: PieceColour.black, label: "黑先走",
                            isEnabled: session.canStart(withSideToMove: .black)
                        ),
                    ],
                    selection: session.startingSideToMove
                ) { colour in
                    selected = nil
                    session.restart(withSideToMove: colour)
                }
                Spacer(minLength: 2)
            }

            if !session.game.plies.isEmpty {
                Text("换先走方会重开一局，走过的这局留在记录里")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Turns the board round. The state it is in is the board, so it needs no label saying so.
    private var flip: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                session.orientation =
                    session.orientation == .whiteAtBottom ? .blackAtBottom : .whiteAtBottom
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down").font(.caption2)
                Text("翻转").font(.footnote)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Palette.chipRest, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("翻转棋盘")
    }

    /// The lines that were played from here instead of the move that follows. With the moves,
    /// because that is what they are: a piece of the record that was left to one side.
    @ViewBuilder private var variations: some View {
        if !session.variationsHere.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(session.variationsHere.enumerated()), id: \.offset) { index, line in
                    Button {
                        selected = nil
                        session.enterVariation(index)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch").font(.caption2)
                            Text(line.prefix(6).map(\.san).joined(separator: " "))
                                .font(.notation)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Palette.analysis)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Palette.analysis.opacity(0.10), in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // ------------------------------------------------------------------ doing

    /// Opens the next game in the collection in place of this one.
    ///
    /// It replaces the top of the path rather than pushing, so working through fifty positions does
    /// not build a stack of fifty screens to come back through — and the way back is still the
    /// library, which is where it was. How you are working carries over — that is `session.next`.
    private func drill(to entry: GameLibrary.Entry) {
        session.suspend()
        guard let next = session.next(entry) else { return }
        selected = nil
        path[path.count - 1] = .game(next)
    }

    private func tap(_ square: Square) {
        guard session.isHandTurn else { return }

        if let selected {
            let moves = viewed.state.moves(from: selected).filter { $0.to == square }
            // More than one move to the same square means a promotion, and only a promotion.
            if moves.count > 1 {
                promotion = PromotionRequest(moves: moves)
                self.selected = nil
                return
            }
            if let move = moves.first {
                session.play(move)
                self.selected = nil
                return
            }
        }

        // Not a destination, so it is either a new selection or a deselection.
        if let piece = pieces[square], piece.colour == viewed.state.sideToMove {
            selected = square
        } else {
            if selected != nil { Sounds.current.play(.refused) }
            selected = nil
        }
    }

    /// The game where the player is looking, which is what everything on this screen is about.
    private var viewed: Game { session.viewed }

    private var pieces: [Square: Piece] {
        BoardRenderer.placement(viewed.state.fen) ?? [:]
    }

    private var candidateMoves: [Move] {
        guard let selected, session.isHandTurn else { return [] }
        return viewed.state.moves(from: selected)
    }

    private var recommendation: MoveSquares? {
        session.analysis?.bestMove.flatMap { MoveSquares(uci: $0) }
    }

    private var notationText: AttributedString {
        var text = AttributedString()
        var number = session.game.startingFullmoveNumber
        var sideToMove = session.game.startingSideToMove

        for (index, ply) in session.game.plies.enumerated() {
            if sideToMove == .white {
                text += styled("\(number). ", Palette.inkSoft)
            } else if text.characters.isEmpty {
                text += styled("\(number)... ", Palette.inkSoft)
            }
            // The move that led to the position on screen, so browsing has somewhere to point.
            let isCursor = index == session.cursor - 1
            var san = styled(ply.san, isCursor ? Palette.analysis : Palette.ink)
            if isCursor { san.font = .notation.weight(.bold) }
            text += san
            if !ply.variations.isEmpty {
                text += styled("⁽\(ply.variations.count)⁾", Palette.inkSoft)
            }
            text += styled(" ", Palette.ink)
            if sideToMove == .black { number += 1 }
            sideToMove = sideToMove.opposite
        }
        return text.characters.isEmpty ? styled("从这里开始走", Palette.inkSoft) : text
    }

    private func styled(_ string: String, _ colour: Color) -> AttributedString {
        var piece = AttributedString(string)
        piece.font = .notation
        piece.foregroundColor = colour
        return piece
    }
}
