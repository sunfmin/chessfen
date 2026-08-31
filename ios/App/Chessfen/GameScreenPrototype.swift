import ChessfenKit
import SwiftUI

// ============================================================================
//  PROTOTYPE — throwaway. Not shipped, not tested beyond the pictures it draws.
//
//  The question: what does the game screen look like when each colour's controls
//  sit on that colour's own side of the board — white's under the board when
//  white is at the bottom, black's above it — and the record of moves is a
//  chess.com-style single line you scroll sideways, with arrows, where tapping a
//  move rewinds to it?
//
//  Three variants, switchable from the floating bar at the bottom. They disagree
//  about where the controls live and what the primary affordance is, on purpose:
//
//    A 对局台   Two player bars sandwiching the board, deck at the bottom.
//              Closest to chess.com. Costs the most vertical space.
//    B 贴边     The bars are hairlines flush against the board's edges — one
//              tappable pill each, no panel. The board is as big as it can be.
//    C 各管各的  Each side's row IS its control panel, and the side on the clock
//              carries the action: 让引擎走 and the engine's line move into the
//              bar of whoever is to move. Tap a bar to unfold its options.
//
//  Fold the winner into GameScreen.swift properly; delete this file.
// ============================================================================

enum PrototypeVariant: String, CaseIterable, Identifiable {
    case a, b, c
    var id: String { rawValue }

    var key: String { rawValue.uppercased() }

    var name: String {
        switch self {
        case .a: "对局台"
        case .b: "贴边"
        case .c: "各管各的"
        }
    }
}

/// One ply, ready to be drawn in a strip: where it sits, what it is called, and the move
/// number it belongs to.
private struct PlyCell: Identifiable {
    let index: Int
    let number: Int
    let isWhite: Bool
    let san: String
    var id: Int { index }
    /// The cursor value that puts this move on the board.
    var cursor: Int { index + 1 }
}

private struct MovePair: Identifiable {
    let number: Int
    let white: PlyCell?
    let black: PlyCell?
    var id: Int { number }
}

// ---------------------------------------------------------------------------

struct PrototypeGameScreen: View {
    let session: GameSession
    @State var variant: PrototypeVariant = .a

    @Environment(EngineHost.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Square?
    @State private var promotion: PromotionRequest?
    @State private var isAsking = false
    /// Which colour's bar is unfolded, in variant C. One at a time. Not private, so a
    /// screenshot can open one.
    @State var unfolded: PieceColour? = nil

    struct PromotionRequest: Identifiable {
        let id = UUID()
        let moves: [Move]
    }

    var body: some View {
        Group {
            switch variant {
            case .a: variantA
            case .b: variantB
            case .c: variantC
            }
        }
        .background(Palette.parchment)
        .navigationTitle("对局")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.parchment, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(Palette.analysis)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("关掉原型") { dismiss() }
            }
        }
        .overlay(alignment: .bottom) { PrototypeSwitcher(variant: $variant) }
        .onAppear { session.attach(engine: engine.service, library: nil); session.retune() }
        .onDisappear { session.suspend() }
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

    // ======================================================== A — 对局台
    //
    //  header
    //  ┌ player bar (far side) ─────────────┐
    //  │  ● 黑方   [手动|引擎]   每步 3 秒    │
    //  └────────────────────────────────────┘
    //  board
    //  ┌ player bar (near side) ────────────┐
    //  eval bar
    //  ‹  开局 · 1.e4 · e5 · 2.Nf3 …  ›
    //  engine lines
    //  ┌ deck: 让引擎走 · 翻转 · 意见 ───────┐

    private var variantA: some View {
        GeometryReader { proxy in
            let side = Self.boardSide(in: proxy.size, spare: 396)
            VStack(spacing: 0) {
                aHeader
                barA(for: topColour).padding(.bottom, 6)
                board.frame(width: side, height: side)
                barA(for: bottomColour).padding(.top, 6)
                if !session.isPractising {
                    EvalBar(
                        score: session.analysis?.best?.score,
                        orientation: session.orientation,
                        finish: finish
                    )
                    .frame(width: side)
                    .padding(.top, 8)
                }
                filmstripA.padding(.top, 10)
                aLines
                Spacer(minLength: 0)
                aDeck
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var aHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(viewed.chineseTurn).eyebrow()
            if viewed.state.inCheck, !viewed.isOver {
                Text("被将").font(.caption2.weight(.semibold)).foregroundStyle(Palette.alarm)
            }
            Spacer(minLength: 8)
            SearchMeter(analysis: session.analysis)
            Text(headline)
                .font(.clock(28))
                .foregroundStyle(session.analysis == nil ? Palette.inkSoft : Palette.analysis)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// One colour's whole hand: who is playing it, and how long that player gets.
    ///
    /// A panel rather than a line, because it is where the eye goes to ask "who am I playing
    /// against" — and it sits on the side of the board that colour's pieces are on, so the
    /// question answers itself.
    private func barA(for colour: PieceColour) -> some View {
        HStack(spacing: 9) {
            Swatch(colour: colour)
            Text(colour.chinese).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)

            SegmentedPair(
                left: "手动", right: "引擎",
                isRightOn: session.controller(for: colour) == .engine,
                isRightEnabled: engine.isReady
            ) { wantsEngine in
                session.setController(wantsEngine ? .engine : .hand, for: colour)
            }

            if session.controller(for: colour) == .engine {
                Menu {
                    ForEach(ThinkingTime.offered, id: \.self) { time in
                        Button(time.chinese) { session.setThinkingTime(time) }
                            .disabled(time == .mirrored && session.isSelfPlaying)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(session.thinkingTime.chinese).font(.caption)
                        Image(systemName: "chevron.down").font(.system(size: 8))
                    }
                    .foregroundStyle(Palette.inkSoft)
                }
            }

            Spacer(minLength: 4)
            statusA(for: colour)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isOnClock(colour) ? Palette.analysis.opacity(0.55) : .clear, lineWidth: 1.5)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private func statusA(for colour: PieceColour) -> some View {
        if isOnClock(colour) {
            if session.isThinking {
                Button { session.moveNow() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "forward.fill").font(.system(size: 9))
                        Text("马上走").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Palette.parchment)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Palette.analysis, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 5) {
                    Circle().fill(Palette.analysis).frame(width: 6, height: 6)
                    Text("走棋").font(.caption).foregroundStyle(Palette.analysis)
                }
            }
        }
    }

    /// The record as one line you push sideways, the way a phone reads a game.
    ///
    /// Per-ply pills with the move number attached to White's, so the numbering is in the strip
    /// rather than in a gutter that has nowhere to be. The arrows step; the pills jump.
    private var filmstripA: some View {
        HStack(spacing: 4) {
            stripArrow("chevron.left", enabled: session.cursor > 0) { hop(-1) }

            ScrollViewReader { scroller in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        Button { hop(to: 0) } label: {
                            Text("开局")
                                .font(.caption)
                                .foregroundStyle(session.cursor == 0 ? Palette.parchment : Palette.inkSoft)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(
                                    session.cursor == 0 ? AnyShapeStyle(Palette.analysis) : AnyShapeStyle(Palette.chipRest),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .id(0)

                        ForEach(plyCells) { cell in
                            Button { hop(to: cell.cursor) } label: {
                                HStack(spacing: 3) {
                                    if cell.isWhite {
                                        Text("\(cell.number).")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(
                                                cell.cursor == session.cursor
                                                    ? Palette.parchment.opacity(0.7) : Palette.inkSoft
                                            )
                                    }
                                    Text(cell.san).font(.notation)
                                }
                                .foregroundStyle(cell.cursor == session.cursor ? Palette.parchment : Palette.ink)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(
                                    cell.cursor == session.cursor
                                        ? AnyShapeStyle(Palette.analysis) : AnyShapeStyle(Palette.chipRest),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                            .id(cell.cursor)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .onChange(of: session.cursor, initial: true) { _, now in
                    withAnimation(.snappy(duration: 0.2)) { scroller.scrollTo(now, anchor: .center) }
                }
            }

            stripArrow("chevron.right", enabled: !session.isAtLatest) { hop(1) }
        }
        .frame(height: 34)
        .padding(.horizontal, 12)
    }

    private var aLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            if session.isPractising {
                Text("练习中，引擎不给意见。").font(.footnote).foregroundStyle(Palette.inkSoft)
            } else if let analysis = session.analysis, !analysis.lines.isEmpty {
                ForEach(Array(analysis.lines.prefix(2).enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        ScoreCell(score: line.score, prominent: index == 0)
                            .frame(width: 52, alignment: .leading)
                        Text(line.san.prefix(7).joined(separator: " "))
                            .font(.notation).lineLimit(1)
                            .foregroundStyle(index == 0 ? Palette.ink : Palette.inkSoft)
                    }
                }
            } else {
                Text(viewed.isOver ? "这局走完了。" : "引擎在算").font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .animation(.none, value: session.analysis?.depth)
    }

    private var aDeck: some View {
        HStack(spacing: 8) {
            HoldButton(
                label: "让引擎走", symbol: "cpu", isHeld: isAsking,
                fill: Double(session.searchProgress?.depth ?? 0) / SearchMeter.deepEnough,
                isEnabled: session.canPlayBestMove,
                onPress: { selected = nil; isAsking = true; session.beginAskedMove() },
                onRelease: { isAsking = false; session.endAskedMove() }
            )
            flipButton
            practiceButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 46)
        .background(Palette.raised)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
    }

    // ======================================================== B — 贴边
    //
    //  The bars stop being panels. Each is a 26-point line pressed against the board's
    //  edge, carrying one pill that says who is playing that colour and toggles it. The
    //  board takes everything that buys.

    private var variantB: some View {
        GeometryReader { proxy in
            let side = Self.boardSide(in: proxy.size, spare: 312)
            VStack(spacing: 0) {
                bHeader
                edgeB(for: topColour, isTop: true).frame(width: side)
                board.frame(width: side, height: side)
                edgeB(for: bottomColour, isTop: false).frame(width: side)
                if !session.isPractising {
                    EvalBar(
                        score: session.analysis?.best?.score,
                        orientation: session.orientation,
                        finish: finish
                    )
                    .frame(width: side)
                    .padding(.top, 10)
                }
                filmstripB.padding(.top, 12)
                bLine
                Spacer(minLength: 0)
                bDeck
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var bHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(viewed.chineseTurn).eyebrow()
            Spacer(minLength: 6)
            SearchMeter(analysis: session.analysis)
            Text(headline)
                .font(.clock(30))
                .foregroundStyle(session.analysis == nil ? Palette.inkSoft : Palette.analysis)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// One colour, one tap. No panel, no chips: the pill says what is playing this side and
    /// tapping it says the other thing. What it costs the board is 26 points, twice.
    private func edgeB(for colour: PieceColour, isTop: Bool) -> some View {
        HStack(spacing: 7) {
            Swatch(colour: colour)
            Text(colour.chinese).font(.caption.weight(.medium)).foregroundStyle(Palette.ink)
            if isOnClock(colour) {
                Circle().fill(Palette.analysis).frame(width: 5, height: 5)
            }
            Spacer(minLength: 4)
            if session.controller(for: colour) == .engine {
                Menu {
                    ForEach(ThinkingTime.offered, id: \.self) { time in
                        Button(time.chinese) { session.setThinkingTime(time) }
                            .disabled(time == .mirrored && session.isSelfPlaying)
                    }
                } label: {
                    Text(session.thinkingTime.chinese).font(.caption2).foregroundStyle(Palette.inkSoft)
                }
            }
            Button {
                let now = session.controller(for: colour)
                session.setController(now == .hand ? .engine : .hand, for: colour)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: session.controller(for: colour) == .engine ? "cpu" : "hand.point.up.left")
                        .font(.system(size: 10))
                    Text(session.controller(for: colour).chinese).font(.caption.weight(.medium))
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 8))
                }
                .foregroundStyle(session.controller(for: colour) == .engine ? Palette.analysis : Palette.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Palette.chipRest, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(colour.chinese)由\(session.controller(for: colour).chinese)走，点一下换")
        }
        .frame(height: 26)
        .padding(.horizontal, 2)
        .overlay(alignment: isTop ? .bottom : .top) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
    }

    /// The record as a continuous run, the way it is written on paper — no pills, just the
    /// moves, with the one being looked at picked out. Cheapest strip there is, and the one
    /// that reads most like a game score.
    private var filmstripB: some View {
        ZStack {
            ScrollViewReader { scroller in
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(plyCells) { cell in
                            Button { hop(to: cell.cursor) } label: {
                                HStack(spacing: 3) {
                                    if cell.isWhite {
                                        Text("\(cell.number).")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(Palette.inkSoft)
                                    }
                                    Text(cell.san)
                                        .font(cell.cursor == session.cursor ? .notation.weight(.bold) : .notation)
                                        .foregroundStyle(cell.cursor == session.cursor ? Palette.analysis : Palette.ink)
                                }
                                .padding(.vertical, 6)
                                .overlay(alignment: .bottom) {
                                    if cell.cursor == session.cursor {
                                        Capsule().fill(Palette.analysis).frame(height: 2)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .id(cell.cursor)
                        }
                        if session.game.plies.isEmpty {
                            Text("从这里开始走").font(.notation).foregroundStyle(Palette.inkSoft)
                        }
                    }
                    .padding(.horizontal, 44)
                }
                .scrollIndicators(.hidden)
                .onChange(of: session.cursor, initial: true) { _, now in
                    withAnimation(.snappy(duration: 0.2)) { scroller.scrollTo(now, anchor: .center) }
                }
            }
            // The arrows sit over the strip's own ends, on the fade that says there is more
            // out there — one control, not a control and a hint about a control.
            HStack {
                edgeArrow("chevron.left", enabled: session.cursor > 0, edge: .leading) { hop(-1) }
                Spacer()
                edgeArrow("chevron.right", enabled: !session.isAtLatest, edge: .trailing) { hop(1) }
            }
        }
        .frame(height: 34)
    }

    private var bLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if session.isPractising {
                Text("练习中，引擎不给意见。").font(.footnote).foregroundStyle(Palette.inkSoft)
            } else if let best = session.analysis?.best {
                ScoreCell(score: best.score, prominent: true).frame(width: 52, alignment: .leading)
                Text(best.san.prefix(8).joined(separator: " "))
                    .font(.notation).lineLimit(1).foregroundStyle(Palette.ink)
            } else {
                Text(viewed.isOver ? "这局走完了。" : "引擎在算").font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .animation(.none, value: session.analysis?.depth)
    }

    private var bDeck: some View {
        HStack(spacing: 8) {
            HoldButton(
                label: "让引擎走", symbol: "cpu", isHeld: isAsking,
                fill: Double(session.searchProgress?.depth ?? 0) / SearchMeter.deepEnough,
                isEnabled: session.canPlayBestMove,
                onPress: { selected = nil; isAsking = true; session.beginAskedMove() },
                onRelease: { isAsking = false; session.endAskedMove() }
            )
            flipButton
            practiceButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 46)
        .background(Palette.raised)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
    }

    // ======================================================== C — 各管各的
    //
    //  There is no deck. Whoever is on the clock holds the controls: 让引擎走 and the
    //  engine's line are drawn in that colour's own bar, so the thing you press is on the
    //  side of the board you are pressing it for. Tap a bar's chevron for that side's
    //  options; only one unfolds at a time.

    private var variantC: some View {
        GeometryReader { proxy in
            let side = Self.boardSide(in: proxy.size, spare: unfolded == nil ? 300 : 372)
            VStack(spacing: 0) {
                panelC(for: topColour)
                board.frame(width: side, height: side).padding(.vertical, 8)
                if !session.isPractising {
                    EvalBar(
                        score: session.analysis?.best?.score,
                        orientation: session.orientation,
                        finish: finish
                    )
                    .frame(width: side)
                    .padding(.bottom, 8)
                }
                panelC(for: bottomColour)
                filmstripC
                Spacer(minLength: 0)
                cFooter
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func panelC(for colour: PieceColour) -> some View {
        let live = isOnClock(colour)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Swatch(colour: colour, size: 16)
                Text(colour.chinese).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(session.controller(for: colour).chinese)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                if live {
                    Text(viewed.isOver ? "" : "该走了")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.analysis)
                }
                Spacer(minLength: 4)

                // The action belongs to the side on the clock, so it is drawn in that side's bar.
                if live, session.isThinking {
                    Button { session.moveNow() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "forward.fill").font(.system(size: 9))
                            Text("马上走").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Palette.parchment)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Palette.analysis, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if live, session.canPlayBestMove {
                    CompactHold(
                        isHeld: isAsking,
                        fill: Double(session.searchProgress?.depth ?? 0) / SearchMeter.deepEnough,
                        onPress: { selected = nil; isAsking = true; session.beginAskedMove() },
                        onRelease: { isAsking = false; session.endAskedMove() }
                    )
                }

                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        unfolded = unfolded == colour ? nil : colour
                    }
                } label: {
                    Image(systemName: unfolded == colour ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(Palette.inkSoft)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(colour.chinese)的设置")
            }

            // What the engine is saying, said to the side it concerns — one line, and only
            // for whoever is to move.
            if live, !session.isPractising, let best = session.analysis?.best {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ScoreCell(score: best.score, prominent: true)
                    Text(best.san.prefix(6).joined(separator: " "))
                        .font(.notation).lineLimit(1).foregroundStyle(Palette.inkSoft)
                    Spacer(minLength: 0)
                    SearchMeter(analysis: session.analysis)
                }
                .animation(.none, value: session.analysis?.depth)
            }

            if unfolded == colour {
                VStack(alignment: .leading, spacing: 8) {
                    ChipCluster(
                        title: "谁走",
                        options: Controller.allCases.map {
                            .init(value: $0, label: $0.chinese, isEnabled: $0 == .hand || engine.isReady)
                        },
                        selection: session.controller(for: colour)
                    ) { session.setController($0, for: colour) }

                    if session.controller(for: colour) == .engine {
                        ChipCluster(
                            title: "每步",
                            options: ThinkingTime.offered.map {
                                .init(
                                    value: $0, label: $0.chinese,
                                    isEnabled: $0 != .mirrored || !session.isSelfPlaying
                                )
                            },
                            selection: session.thinkingTime
                        ) { session.setThinkingTime($0) }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(live ? Palette.raised : Palette.parchment)
        .overlay(alignment: .leading) {
            Rectangle().fill(live ? Palette.analysis : .clear).frame(width: 3)
        }
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
    }

    /// A move at a time rather than a ply at a time: one card per move number, both halves in
    /// it, the way a scoresheet is ruled. The arrows walk whole moves, which is how anyone
    /// says where they are in a game.
    private var filmstripC: some View {
        HStack(spacing: 6) {
            stripArrow("chevron.left", enabled: session.cursor > 0) { hop(-1) }

            ScrollViewReader { scroller in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(movePairs) { pair in
                            HStack(spacing: 6) {
                                Text("\(pair.number)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Palette.inkSoft)
                                    .frame(minWidth: 14, alignment: .trailing)
                                if let white = pair.white { pairHalf(white) }
                                if let black = pair.black { pairHalf(black) }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Palette.chipRest, in: RoundedRectangle(cornerRadius: 9))
                        }
                        if session.game.plies.isEmpty {
                            Text("从这里开始走").font(.notation).foregroundStyle(Palette.inkSoft)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .onChange(of: session.cursor, initial: true) { _, now in
                    withAnimation(.snappy(duration: 0.2)) { scroller.scrollTo(now, anchor: .center) }
                }
            }

            stripArrow("chevron.right", enabled: !session.isAtLatest) { hop(1) }
        }
        .frame(height: 42)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func pairHalf(_ cell: PlyCell) -> some View {
        Button { hop(to: cell.cursor) } label: {
            Text(cell.san)
                .font(cell.cursor == session.cursor ? .notation.weight(.bold) : .notation)
                .foregroundStyle(cell.cursor == session.cursor ? Palette.parchment : Palette.ink)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(
                    cell.cursor == session.cursor ? AnyShapeStyle(Palette.analysis) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .buttonStyle(.plain)
        .id(cell.cursor)
    }

    /// What is left when the controls have gone to the sides: the two things that belong to
    /// the game rather than to a colour.
    private var cFooter: some View {
        HStack(spacing: 10) {
            flipButton
            practiceButton
            Spacer(minLength: 0)
            if !session.isAtLatest {
                Button { selected = nil; session.jumpToLatest() } label: {
                    Text("回到最新").font(.caption.weight(.semibold)).foregroundStyle(Palette.analysis)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 46)
    }

    // ================================================================ shared bits
    //
    //  Plumbing, not layout: the board, the tap, the numbers. Every variant is free to throw
    //  its own arrangement away without touching any of this.

    private var board: some View {
        BoardView(
            pieces: BoardRenderer.placement(viewed.state.fen) ?? [:],
            orientation: session.orientation,
            lastMove: session.lastMove,
            checks: viewed.state.checkSquares,
            suspects: session.unconfirmedSquares,
            selected: selected,
            destinations: Set(candidateMoves.map(\.to)),
            captures: Set(candidateMoves.filter(\.isCapture).map(\.to)),
            recommendation: session.analysis?.bestMove.flatMap { MoveSquares(uci: $0) },
            isInteractive: session.isHandTurn,
            onTap: tap
        )
    }

    private var flipButton: some View {
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
            .padding(.horizontal, 11).padding(.vertical, 10)
            .background(Palette.chipRest, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("翻转棋盘")
    }

    private var practiceButton: some View {
        Button { session.setPractising(!session.isPractising) } label: {
            HStack(spacing: 5) {
                Image(systemName: session.isPractising ? "eye.slash" : "eye").font(.caption2)
                Text(session.isPractising ? "自己练" : "看引擎").font(.footnote)
            }
            .foregroundStyle(session.isPractising ? Palette.inkSoft : Palette.ink)
            .padding(.horizontal, 11).padding(.vertical, 10)
            .background(Palette.chipRest, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func stripArrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, height: 34)
                .background(Palette.chipRest, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func edgeArrow(
        _ symbol: String, enabled: Bool, edge: HorizontalEdge, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 44, height: 34)
                .background(
                    LinearGradient(
                        colors: [Palette.parchment, Palette.parchment, Palette.parchment.opacity(0)],
                        startPoint: edge == .leading ? .leading : .trailing,
                        endPoint: edge == .leading ? .trailing : .leading
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    private func tap(_ square: Square) {
        guard session.isHandTurn else { return }
        if let selected {
            let moves = viewed.state.moves(from: selected).filter { $0.to == square }
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
        if let piece = (BoardRenderer.placement(viewed.state.fen) ?? [:])[square],
            piece.colour == viewed.state.sideToMove
        {
            selected = square
        } else {
            selected = nil
        }
    }

    private func hop(_ delta: Int) {
        selected = nil
        session.step(by: delta)
    }

    private func hop(to cursor: Int) {
        selected = nil
        session.step(by: cursor - session.cursor)
    }

    private var viewed: Game { session.viewed }

    private var candidateMoves: [Move] {
        guard let selected, session.isHandTurn else { return [] }
        return viewed.state.moves(from: selected)
    }

    private var headline: String {
        if session.isPractising { return "练习" }
        if let finish { return finish.scoreline }
        return session.analysis?.best?.score.displayText ?? "—"
    }

    private var finish: EvalBar.Finish? {
        switch viewed.state.outcome {
        case .ongoing: nil
        case .checkmate: .won(viewed.state.sideToMove.opposite)
        default: .drawn
        }
    }

    /// The colour whose pieces are at the top of the board — and so the colour whose controls
    /// belong above it. This is the whole point of the layout: flipping the board moves the
    /// controls with it.
    private var topColour: PieceColour {
        session.orientation == .whiteAtBottom ? .black : .white
    }

    private var bottomColour: PieceColour {
        session.orientation == .whiteAtBottom ? .white : .black
    }

    private func isOnClock(_ colour: PieceColour) -> Bool {
        !viewed.isOver && viewed.state.sideToMove == colour
    }

    private var plyCells: [PlyCell] {
        var cells: [PlyCell] = []
        var number = session.game.startingFullmoveNumber
        var side = session.game.startingSideToMove
        for (index, ply) in session.game.plies.enumerated() {
            cells.append(
                PlyCell(index: index, number: number, isWhite: side == .white, san: ply.san)
            )
            if side == .black { number += 1 }
            side = side.opposite
        }
        return cells
    }

    private var movePairs: [MovePair] {
        var pairs: [MovePair] = []
        for cell in plyCells {
            if cell.isWhite {
                pairs.append(MovePair(number: cell.number, white: cell, black: nil))
            } else if let last = pairs.last, last.number == cell.number {
                pairs[pairs.count - 1] = MovePair(number: last.number, white: last.white, black: cell)
            } else {
                pairs.append(MovePair(number: cell.number, white: nil, black: cell))
            }
        }
        return pairs
    }

    /// The board takes what the arrangement above and below it has left over. Every variant
    /// spends a different amount, which is most of what makes them different.
    static func boardSide(in size: CGSize, spare: CGFloat) -> CGFloat {
        let byWidth = size.width - 16
        let byHeight = max(200, size.height - spare)
        return (min(byWidth, byHeight) / 8).rounded(.down) * 8
    }
}

// ------------------------------------------------------------------- pieces

/// The colour, as the thing itself. A disc of the piece colour beside the word does in one
/// glance what "白方" does in two characters, and it is what ties the bar to its half of the board.
private struct Swatch: View {
    let colour: PieceColour
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(colour == .white ? Palette.barWhite : Palette.barBlack)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Palette.walnut.opacity(0.45), lineWidth: 0.8))
    }
}

/// Two words in one groove — the switch a player bar needs when the choice is binary and
/// permanent-looking. Not a `ChipCluster`, because that has a title and this bar is the title.
private struct SegmentedPair: View {
    let left: String
    let right: String
    let isRightOn: Bool
    var isRightEnabled = true
    let pick: (Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            half(left, on: !isRightOn, enabled: true) { pick(false) }
            half(right, on: isRightOn, enabled: isRightEnabled) { pick(true) }
        }
        .padding(1.5)
        .background(Palette.chipRest, in: Capsule())
    }

    private func half(
        _ text: String, on: Bool, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Palette.parchment : Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(on ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(.clear), in: Capsule())
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// 让引擎走, small enough to live inside a player bar. Same bargain as the full-width one:
/// held is thinking, letting go plays.
private struct CompactHold: View {
    let isHeld: Bool
    var fill: Double = 0
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu").font(.system(size: 10))
            Text("让引擎走").font(.caption.weight(.medium))
        }
        .foregroundStyle(isHeld ? Palette.parchment : Palette.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            ZStack(alignment: .leading) {
                Palette.chipRest
                GeometryReader { proxy in
                    Palette.analysis
                        .frame(width: proxy.size.width * (isHeld ? min(max(fill, 0), 1) : 0))
                        .animation(.easeOut(duration: 0.3), value: fill)
                }
            }
            .clipShape(Capsule())
        }
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isHeld { onPress() } }
                .onEnded { _ in if isHeld { onRelease() } }
        )
        .accessibilityLabel("让引擎走")
    }
}

/// The prototype's own bar, and it is meant to look like it does not belong: high contrast,
/// floating, obviously not part of anything being judged.
struct PrototypeSwitcher: View {
    @Binding var variant: PrototypeVariant

    var body: some View {
        HStack(spacing: 2) {
            step("chevron.left", by: -1)
            Text("\(variant.key) — \(variant.name)")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 116)
            step("chevron.right", by: 1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(.black.opacity(0.86), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
        .padding(.bottom, 6)
    }

    private func step(_ symbol: String, by delta: Int) -> some View {
        Button {
            let all = PrototypeVariant.allCases
            let index = (all.firstIndex(of: variant) ?? 0) + delta
            variant = all[(index % all.count + all.count) % all.count]
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
