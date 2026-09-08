import ChessfenKit
// For `onReceive` only: the sound setting travels through iCloud, and a notification is how a
// device hears that another one has changed it.
import Combine
import SwiftUI

/// The board, who is playing each colour, and what there is to do about it.
///
/// Each colour's controls sit on that colour's own side of the board: who is playing it, how long
/// the engine gets over a move, and — for whoever is on the clock — the one button that plays a
/// move and the line the engine would play. Turn the board round and they change places with it,
/// because they belong to the pieces and not to the screen. It also answers the question a fixed
/// deck could not: the button that plays a move is beside the half of the board it plays into.
///
/// No scrolling above the record: the board is the hero and it has to sit still under a navigation
/// bar, not slide beneath it. Everything above and below it is a strip of fixed height, and the
/// board takes whatever is left over — which on a small phone means a slightly smaller board
/// rather than a screen that has to be dragged. The one part that scrolls is the reading below
/// the record: the collection, the corrections, the lines the engine is weighing, the Variations.
struct GameScreen: View {
    let session: GameSession
    @Binding var path: [Step]
    /// Which card of the deck to open on. Nil means the position decides, which is what the app
    /// does; a screenshot test passes one in to photograph a card that is not the one on top.
    var opening: Card?

    @Environment(EngineHost.self) private var engine
    @Environment(GameLibrary.self) private var library

    @State private var selected: Square?
    @State private var promotion: PromotionRequest?
    @State private var isSoundOn = Sounds.current.isSoundOn
    /// Which side's own controls are open. Nobody's, unless somebody said otherwise — and then
    /// their answer stands for as long as the screen does. Never derived from the game: an unfold
    /// that answers to the moves is an unfold that opens and shuts under your thumb, and the board
    /// walks up and down the screen every time it does.
    @State private var unfolded: PieceColour?
    /// Whether the opening guess below has been made yet. Once, on the way in — not on every
    /// appearance, or coming back from a Review would shut what somebody had just opened.
    @State private var hasGuessedUnfold = false
    /// Whether the deck has been dealt yet. Once, for the same reason.
    @State private var hasDealt = false
    /// Whether it was arriving at 杀 or 战术 that turned the finder on, rather than a person
    /// pressing its switch. Only what a swipe turned on does a swipe turn off again.
    @State private var finderIsOurs = false
    /// The room the deck occupies under the record, measured from the layout.
    @State private var peek: CGFloat = 0
    /// Whether a thumb is on 让引擎走 right now. The engine is thinking for exactly as long as it is —
    /// which is why this is read off the session rather than kept here as well. A screen holding
    /// its own copy of "a finger is down" is a screen that can be left holding it: a press that
    /// ends any way other than a release leaves the flag set, and the button then draws itself
    /// full and held with nobody touching it.
    private var isAsking: Bool { session.thinking == .asked }

    /// Which card of the deck under the record is showing.
    ///
    /// A kind rather than an index (see `Card`): the deck is dealt from the position, so an index
    /// would point at a different card every time the position changed shape.
    @State private var card: Card = .key
    /// Whether the mate line is drawn on the board. Set by arriving at the news, because a mate
    /// drawn is the whole of what the news is for, and cleared by leaving it.
    @State private var showsMateLine = false

    struct PromotionRequest: Identifiable {
        let id = UUID()
        let moves: [Move]
    }

    /// A guess at what to open, made once and then never again.
    ///
    /// A board with nothing played on it opens the side to move, because that is the side every
    /// unanswered question is about — who is playing it, and whether it really is the one to move.
    /// A game already under way opens nothing. After this, only a thumb changes it.
    private func guessUnfold() {
        guard !hasGuessedUnfold else { return }
        hasGuessedUnfold = true
        unfolded = session.game.plies.isEmpty ? viewed.state.sideToMove : nil
    }

    /// Which card the deck opens on: the work this position is for, and **never the news**. A mate
    /// you were shown without asking for it is the one thing this deck deliberately will not do —
    /// its dot is lit and the rest is your move (docs/adr/0023).
    private var opensOn: Card {
        if let opening { return opening }
        // News before work: a mate on the board is the reason 「直接给予提示」 was asked for, and a
        // coloured dot among five is not a prompt (docs/adr/0023). Only ever the latest position —
        // a past Ply is a Drill and is handed no mate at all.
        if session.mateNews != nil { return .mate }
        if isPast, session.isStudying || session.guess != nil { return .drill }
        return .key
    }

    /// Deals the deck, once, and does whatever arriving at that card does — an opening card whose
    /// layer never came on is a card that lies about what it is showing.
    private func deal() {
        guard !hasDealt else { return }
        hasDealt = true
        card = opensOn
        arrive(at: card)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = Self.boardSide(in: proxy.size)
            VStack(spacing: 0) {
                playerBar(topColour)
                board.frame(width: side, height: side)
                standing.frame(width: side).padding(.vertical, 6)
                playerBar(bottomColour)
                record
                // The room the deck rests in, measured rather than guessed. The deck is laid over
                // the top of this so the board never moves when the cards change.
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { peek = $0 }
            }
            .frame(maxWidth: .infinity)
            // One card at a time, the same ten whatever the position (docs/adr/0023). This was a
            // single scroll with eleven sections stacked in it, in the order they had been written
            // rather than the order the position asks for — six switches and ten paragraphs, most
            // of them about something this position could not do anything with.
            .overlay(alignment: .bottom) {
                DeckSurface(peek: peek) {
                    rail
                } content: {
                    deckView
                }
                .opacity(peek == 0 ? 0 : 1)
            }
        }
        .background(Palette.parchment)
        // No title, and now nothing in its place either. The screen is a board; a word saying
        // "game" over the top of one is a row of a phone spent on something nobody was in any
        // doubt about. The engine's switch stood here for a while, which was better than the strip
        // of its own it had before — but a switch in the navigation bar is still a long way from
        // the bar it governs, and it has gone down to join it under the board.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.parchment, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(Palette.analysis)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { flip }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // No 复盘 here any more. It was a destination; it is a switch now, in the
                    // navigation bar, and the report it turns on appears on this board
                    // (docs/adr/0015).
                    //
                    // Here rather than under the board, where it used to be the widest button on
                    // the screen. Taking a move off is not how a game is read — the record goes
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
                    // Time is the only dial (docs/adr/0009), and here it is spent per ply: a
                    // deeper pass is a better opinion and a longer wait, and nothing else changes.
                    // It used to be a 重算 menu on a row of its own under the report, next to a
                    // sentence naming the depth. The depth is said once now, beside the score it
                    // produced, and changing it is here with the other things done rarely.
                    Menu {
                        ForEach([10, 14, 18, 22], id: \.self) { depth in
                            Button("深度 \(depth)") { session.startReview(depth: depth) }
                        }
                    } label: {
                        Label("重新打分", systemImage: "arrow.clockwise")
                    }
                    .disabled(session.reviewPass?.isRunning == true || !engine.isReady)
                    Toggle(isOn: $isSoundOn) {
                        Label("音效", systemImage: isSoundOn ? "speaker.wave.2" : "speaker.slash")
                    }
                    if let url = session.url {
                        ShareLink(item: url) {
                            Label("导出 PGN", systemImage: "square.and.arrow.up")
                        }
                    }
                    // 先走 throws a game away, and it stays on offer for as long as the game lasts,
                    // because whose move it was is a field no photograph could settle and finding
                    // out it was guessed wrong three moves later is the normal way to find out.
                    // What it does is said where it is about to matter, rather than in a chip
                    // standing under the board for the rest of the game.
                    Section("换先走方会重开一局，走过的这局留在记录里") {
                        Button("白先走") {
                            selected = nil
                            session.restart(withSideToMove: .white)
                        }
                        .disabled(!session.canStart(withSideToMove: .white))
                        Button("黑先走") {
                            selected = nil
                            session.restart(withSideToMove: .black)
                        }
                        .disabled(!session.canStart(withSideToMove: .black))
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多，先走的是\(session.startingSideToMove.chinese)")
            }
        }
        .onAppear {
            guessUnfold()
            deal()
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
                Button(move.promotion?.name ?? move.uci) {
                    if session.isStudying {
                        session.offer(move)
                    } else {
                        session.play(move)
                    }
                    promotion = nil
                }
            }
            Button("取消", role: .cancel) { promotion = nil }
        }
    }

    // ------------------------------------------------------------------ the standing

    /// Who is ahead, said once, along the foot of the board.
    ///
    /// It used to be said twice: a number in a line above the board and a bar below it, with the
    /// engine's speed and depth between them. Two pictures of one fact cost a row each on a phone,
    /// and the row they cost came out of the report — which is the part of this screen anybody
    /// learns anything from. So the number moved down to the end of its own bar, and the speed and
    /// depth went altogether: they said what the phone was doing, never what the position was.
    ///
    /// Always here, whatever the switch is doing, so the board does not walk up the screen when
    /// the engine is asked to be quiet. What changes is what stands in it: a bar and a number when
    /// there is an opinion, the word 练习 when there is deliberately none.
    ///
    /// A finished game keeps its bar, and that is not a leak: what it carries then is the result,
    /// and who won is a fact about the game rather than the engine's opinion of it. Practice hides
    /// what the engine thinks, never what happened.
    ///
    /// **Everything the engine has to say is now in this one strip**, including the switch that
    /// decides whether it says anything — which used to live in the navigation bar, a screen away
    /// from the bar it governs. Four things that are one thought: whether it is talking, who is
    /// ahead, by how much, and how far it has got working it out. The last of those is new, and it
    /// is here because a search that stops after ten seconds (docs/adr/0019) has to be able to say
    /// so — a number that quietly stopped moving is indistinguishable from an engine that died.
    private var standing: some View {
        HStack(spacing: 8) {
            opinionSwitch

            if viewed.isOver {
                // Who won is not a fact about one side, so it is said here rather than in a bar.
                Text(viewed.chineseTurn)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            } else if engine.unavailableReason != nil {
                Text("没有引擎").font(.caption).foregroundStyle(Palette.alarm)
            }

            if !session.isPractising || finish != nil {
                evalTrack
            } else {
                Spacer(minLength: 0)
            }

            if let finish {
                // The number people have been watching, resolved: a finished game has no Score to
                // show, and what belongs in its place is the one it ended on.
                Text(finish.scoreline)
                    .font(.clock(22))
                    .foregroundStyle(Palette.ink)
            } else if !session.isPractising {
                Text(session.analysis?.best?.score.displayText ?? "—")
                    .font(.clock(22))
                    .foregroundStyle(session.analysis == nil ? Palette.inkSoft : Palette.analysis)
                    .contentTransition(.numericText())
                effort
            }
        }
        .frame(height: 26)
    }

    /// The switch that used to sit in the navigation bar, brought down beside the bar it governs.
    ///
    /// Two shapes, because the two states are read for different reasons. Silent, it wears the
    /// word: 练习 is a thing to be *in*, and a strip with no number in it has the room to name it.
    /// Talking, the bar and the number have already said the engine is talking, so the control
    /// shrinks back to the eye that turns it off.
    ///
    /// One deliberate press either way, which is all ADR-0015 ever asked for: the engine's opinion
    /// is never found already on, and never lost by brushing past it.
    private var opinionSwitch: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { session.setPractising(!session.isPractising) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: session.isPractising ? "eye.slash" : "eye").font(.caption2)
                if session.isPractising {
                    Text("练习").font(.footnote.weight(.semibold))
                }
            }
            .foregroundStyle(session.isPractising ? Palette.inkSoft : Palette.analysis)
            .padding(.horizontal, session.isPractising ? 9 : 6)
            .padding(.vertical, 4)
            .background(Palette.chipRest, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!engine.isReady && session.isPractising)
        .accessibilityLabel("引擎意见")
        // The word the control is actually wearing, not a bare 关. A screen that draws 练习 and
        // reports "off" says two different things to two different readers, and the tree is the
        // one VoiceOver hears.
        .accessibilityValue(session.isPractising ? "练习" : "开")
    }

    /// Who is ahead, with how hard the engine is still working on that answer drawn underneath it.
    ///
    /// One control rather than a bar with a button next to it, because they are the same subject:
    /// the line is the search that produced the bar, and when the search has stopped the bar is
    /// what you press for more of it. The line fills with Depth — the same measure the hold button
    /// uses — so it is the picture of the number beside it rather than a second thing to read.
    ///
    /// It goes quiet rather than away when the Stint ends: how deep it got is worth keeping on
    /// screen, and a line that vanished would say the engine had never run.
    private var evalTrack: some View {
        VStack(spacing: 3) {
            EvalBar(
                score: session.analysis?.best?.score,
                orientation: session.orientation,
                finish: finish
            )
            if finish == nil, !session.isPractising {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Palette.analysis.opacity(session.isAdviceSpent ? 0.3 : 0.9))
                        .frame(width: proxy.size.width * depthFraction)
                        .animation(.easeOut(duration: 0.3), value: depthFraction)
                }
                .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { session.adviseAgain() }
    }

    /// How far the search has got, 0...1, by the same reckoning the hold button uses.
    private var depthFraction: Double {
        min(Double(session.searchProgress?.depth ?? 0) / SearchDepth.deepEnough, 1)
    }

    /// What the engine has got to, and — once it has stopped — what to do about that.
    ///
    /// A search with no readout is a phone that might be working or might be broken, and the
    /// answer used to be "it is always working", which was the problem. Now it stops, so it has to
    /// account for itself: a Depth while it climbs, and an offer of another ten seconds when it
    /// has stopped climbing.
    @ViewBuilder private var effort: some View {
        if session.isAdviceSpent {
            Button { session.adviseAgain() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 9))
                    Text("再算 10 秒").font(.caption.weight(.semibold))
                }
                .foregroundStyle(Palette.parchment)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Palette.analysis, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("再算 10 秒")
        } else if let depth = session.searchProgress?.depth, depth > 0 {
            Text("深 \(depth)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Palette.inkSoft)
                // It climbs several times a second, and a number that animates while it does is a
                // number nobody can read.
                .animation(.none, value: depth)
        }
    }

    // ------------------------------------------------------------------ the two sides

    /// One colour's whole hand, on that colour's side of the board.
    ///
    /// Folded, it states two facts that used to be a line of prose under a chevron: who is playing
    /// this side, and how long they get. Unfolded, it is where those two are changed — and only
    /// one side unfolds at a time, because ten pills standing under a board for an hour is a
    /// settings panel where a game should be.
    ///
    /// The side on the clock gets two more things, and they are the reason the controls are here
    /// rather than in a deck: the button that plays a move, and the move it would play.
    private func playerBar(_ colour: PieceColour) -> some View {
        let live = isOnClock(colour)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Swatch(colour: colour)
                Text(colour.chinese)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(session.controller(for: colour).chinese)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                // The engine's clock, and only where it decides something: how long this side's
                // next move takes. It is the only dial in the app (docs/adr/0009).
                if session.controller(for: colour) == .engine {
                    Text(session.thinkingTime.chinese)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                }
                if live, !viewed.isOver {
                    Text("该走了").font(.caption.weight(.semibold)).foregroundStyle(Palette.analysis)
                    if viewed.state.inCheck {
                        Text("被将").font(.caption.weight(.semibold)).foregroundStyle(Palette.alarm)
                    }
                    advice(for: colour)
                }
                Spacer(minLength: 4)
                if live { action }
                unfoldButton(colour)
            }
            .frame(height: 30)

            if unfolded == colour { chips(for: colour) }
        }
        .padding(.leading, 13)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(live ? Palette.raised : Palette.parchment)
        // The side on the clock, said as a mark down the edge of its own bar rather than as a
        // word: it is the one thing on this screen that changes every single move.
        .overlay(alignment: .leading) {
            Rectangle().fill(live ? Palette.analysis : .clear).frame(width: 3)
        }
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
    }

    /// The one button down here that plays a move, in the bar of the side it would play for.
    ///
    /// Two states and they are not the same act: while the engine holds this colour's Controller
    /// it is already walking the move and the only thing left to do is stop waiting; the rest of
    /// the time it is an Asked Move, and how long the button is held is the time the engine gets.
    ///
    /// Which one is on screen turns on *whose* move the engine is walking, never on whether it is
    /// searching at all. An Asked Move searches too, and choosing on that swapped this button for
    /// the other one on the first instant of a press — which took the button out from under the
    /// finger, so it was never let go of and the move it was asked for was never played.
    @ViewBuilder private var action: some View {
        if session.thinking == .own {
            // Mirrored Time means the engine takes about as long as the player just did, which is
            // right most of the time and longer than anyone wants to sit through the rest of it.
            // Stopping the search does not change which move it picks; it just stops waiting.
            Button { session.moveNow() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "forward.fill").font(.system(size: 9))
                    Text("马上走").font(.caption.weight(.semibold))
                }
                .foregroundStyle(Palette.parchment)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Palette.analysis, in: Capsule())
            }
            .buttonStyle(.plain)
        } else if session.canPlayBestMove {
            HoldButton(
                label: "让引擎走",
                symbol: "cpu",
                isHeld: isAsking,
                fill: Double(session.searchProgress?.depth ?? 0) / SearchDepth.deepEnough,
                onPress: {
                    selected = nil
                    session.beginAskedMove()
                },
                onRelease: { session.endAskedMove() }
            )
            .accessibilityLabel("让引擎走")
            .accessibilityHint("按住不放，引擎算得更深；松手就走")
        }
    }

    /// The engine's answer, in the row that already exists, for the side on the clock.
    ///
    /// **One move, not a line.** It used to be six of them — `d4 exd4 cxd4 Bb6 e5 d5` — which is a
    /// sentence in a language most people playing this have not learnt, spelling out a future
    /// nobody is obliged to walk into. What is useful is the move it would play now, which the
    /// board is already drawing as a teal arrow; this names the arrow. The number lives in the
    /// header, where it is one big figure instead of two small ones.
    ///
    /// A row of its own is what this cost before, in both bars, whether or not either had anything
    /// to say — fifty points of a phone, to keep the board from walking when the clock changed
    /// sides. In the row it needs no height of its own, and the board stands just as still.
    @ViewBuilder private func advice(for colour: PieceColour) -> some View {
        if isAsking {
            Text(askedReadout)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Palette.analysis)
                .lineLimit(1)
        } else if session.isPractising {
            // Nothing. The header already wears 练习 with an eye struck through it, and a bar that
            // says "no opinion" every move is an opinion about how much you are missing.
            EmptyView()
        } else if let best = session.analysis?.best?.san.first {
            Text("\(session.controller(for: colour) == .engine ? "会走" : "建议") \(best)")
                .font(.caption)
                .foregroundStyle(Palette.analysis)
                .lineLimit(1)
                // The recommendation changes several times a second as the search deepens, and
                // that is the point (docs/adr/0009) — so it must not animate while it does.
                .animation(.none, value: session.analysis?.depth)
        } else if let reason = engine.unavailableReason {
            Text(reason).font(.caption).foregroundStyle(Palette.alarm).lineLimit(1)
        } else {
            Text("在算").font(.caption).foregroundStyle(Palette.inkSoft)
        }
    }

    /// What a thumb on 让引擎走 is being told: how long the engine has had and how deep it has got.
    /// Before the first snapshot lands there is nothing to report but the bargain. How to finish is
    /// not said here — it is the button under the thumb, and it says it itself.
    private var askedReadout: String {
        guard let progress = session.searchProgress, progress.depth > 0 else {
            return "按住越久算得越深"
        }
        return String(format: "%.1f 秒 · 深 %d", progress.seconds, progress.depth)
    }

    private func unfoldButton(_ colour: PieceColour) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                unfolded = unfolded == colour ? nil : colour
            }
        } label: {
            Image(systemName: unfolded == colour ? "chevron.up" : "chevron.down")
                .font(.caption2)
                .foregroundStyle(Palette.inkSoft)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unfolded == colour ? "收起\(colour.chinese)的设置" : "打开\(colour.chinese)的设置")
    }

    /// Who plays this colour, and how long they get if it is the engine.
    private func chips(for colour: PieceColour) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ChipCluster(
                title: "谁走",
                options: Controller.allCases.map {
                    .init(value: $0, label: $0.chinese, isEnabled: $0 == .hand || engine.isReady)
                },
                selection: session.controller(for: colour)
            ) { controller in
                session.setController(controller, for: colour)
            }

            // 跟着我 is Mirrored Time, and it stands down when the engine is playing itself: there
            // is no player's last move to mirror, so the game names a clock instead.
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
                ) { time in
                    session.setThinkingTime(time)
                }
            }
        }
        .padding(.top, 1)
    }

    // ------------------------------------------------------------------ the record

    /// The moves, as one line you push sideways, over the shape of the game.
    ///
    /// A game is read a move at a time, so it is ruled a move at a time: one card per move number
    /// with both halves in it, the way a scoresheet is. Tapping a half is how you go back to it —
    /// which is browsing and not undoing, so the game is untouched and every move is still there.
    /// The arrows walk it a ply at a time for the times when the eye is following rather than
    /// looking something up.
    ///
    /// Behind the cards, when there is a Review to draw one from, is the curve — as a ground and
    /// not as a second control. It used to be 110 points of the reading below, which on a phone is
    /// most of the window a question has to fit in; here it costs nothing, because the strip was
    /// already saying where in the game the eye is and the curve says the same thing in a shape.
    /// It scrolls with the cards, and spans exactly what they span, so the dip under a card is the
    /// dip that card's move caused. A chart behind moves it does not describe would be worse than
    /// no chart — and the correspondence is only as exact as the cards are even, which is why this
    /// is a ground and the numbers are said in words underneath.
    private var record: some View {
        HStack(spacing: 6) {
            arrow("chevron.left", label: "上一步", enabled: session.cursor > 0) { walk(-1) }
            moveStrip
            arrow("chevron.right", label: "下一步", enabled: !session.isAtLatest) { walk(1) }
            // The way back to the present, beside the arrows that walked away from it. It used to
            // be a sentence above the board — "在看第 7/8 步 · 回到最新" — which spent a row saying
            // where the eye was, and where the eye is is what this whole strip is drawing.
            if !session.isAtLatest {
                arrow("forward.end.fill", label: "回到最新", enabled: true) {
                    selected = nil
                    session.jumpToLatest()
                }
            }
        }
        .frame(height: 42)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    /// Whether there is a curve to draw at all: one is made of Scores, and Scores are the engine's
    /// opinion — which practice is the state of not being given (docs/adr/0015). So a practising
    /// board has a plain strip, and so does a game nobody has scored.
    private var canShowCurve: Bool {
        !session.isPractising && session.game.isReviewed
    }

    /// The curve as a ground. It marks no cursor of its own — the card on the cursor is already
    /// filled, and a second mark is a second answer.
    private var curveGround: some View {
        EvalCurve(
            plies: session.game.plies.count,
            score: { session.game.reviewScore(atPly: $0) }
        )
        .accessibilityLabel("分数曲线")
        .accessibilityValue("第 \(session.cursor) 步")
    }

    private var moveStrip: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    openingCell
                    ForEach(moveCards) { card in
                        HStack(spacing: 6) {
                            Text("\(card.number)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Palette.inkSoft)
                                .frame(minWidth: 13, alignment: .trailing)
                            if let white = card.white { half(white) }
                            if let black = card.black { half(black) }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Palette.chipRest, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                .padding(.horizontal, 2)
                .background {
                    if canShowCurve { curveGround }
                }
            }
            .scrollIndicators(.hidden)
            // Where the eye is, kept in the middle of the strip as it moves — a record that
            // has scrolled off the position on the board is a record of somebody else's game.
            .onChange(of: session.cursor, initial: true) { _, now in
                withAnimation(.snappy(duration: 0.2)) { scroller.scrollTo(now, anchor: .center) }
            }
        }
    }

    /// The position the game began in, at the head of its own record. It is a place in the game
    /// like any other, and without it there is no way back to it in one tap.
    private var openingCell: some View {
        Button { walk(to: 0) } label: {
            Text(session.game.plies.isEmpty ? "从这里开始走" : "开局")
                .font(.caption)
                .foregroundStyle(session.cursor == 0 ? Palette.parchment : Palette.inkSoft)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    session.cursor == 0
                        ? AnyShapeStyle(Palette.analysis) : AnyShapeStyle(Palette.chipRest),
                    in: RoundedRectangle(cornerRadius: 9)
                )
        }
        .buttonStyle(.plain)
        .id(0)
    }

    private func half(_ cell: PlyCell) -> some View {
        Button { walk(to: cell.cursor) } label: {
            HStack(spacing: 1) {
                Text(cell.san)
                    .font(cell.cursor == session.cursor ? .notation.weight(.bold) : .notation)
                if cell.variations > 0 {
                    Text("⁽\(cell.variations)⁾").font(.caption2)
                }
            }
            .foregroundStyle(cell.cursor == session.cursor ? Palette.parchment : Palette.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                cell.cursor == session.cursor
                    ? AnyShapeStyle(Palette.analysis) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 5)
            )
        }
        .buttonStyle(.plain)
        .id(cell.cursor)
        // Said the way somebody reading a game aloud says it. A bare "Nf6" out of VoiceOver is a
        // move with no place in the game, and place is the whole of what this strip is for.
        .accessibilityLabel("第 \(cell.cursor) 步 \(cell.san)")
        .accessibilityHint("回到这一步")
    }

    private func arrow(
        _ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                // The 44 points a thumb is entitled to, at the two ends of the control it is used
                // on most.
                .frame(width: 38, height: 42)
                .background(Palette.chipRest, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    // ------------------------------------------------------------------ the reading

    // ------------------------------------------------------------------ the study

    /// The question, the answer, and what the answer was worth — all on the board that asked it.
    ///
    /// Browsing back to a past Ply with the engine silent *is* the Drill: there is no mode to
    /// enter and no screen to go to, so this is what appears under the board when the two things
    /// a person has already said — the switch is off, the eye is in the past — add up to a
    /// question (docs/adr/0015).
    @ViewBuilder private var study: some View {
        if let reveal = session.reveal {
            revealed(reveal)
        } else if session.isRevealing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在算这一步…").font(.footnote).foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        } else if let guess = session.guess {
            // Four rows and no more. The window under the record is short — shorter than this
            // question used to be — and a question a person has to scroll to finish answering is
            // one they answer badly. So the verbs are one row, and the two buttons ride beside
            // the line that says what the claim reads as.
            VStack(alignment: .leading, spacing: 8) {
                Text("你走 \(guess.san)。为什么？").font(.subheadline.weight(.medium))
                verbs
                HStack(spacing: 9) {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(
                            session.declaredIntent == nil ? Palette.inkSoft : Palette.analysis
                        )
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    CardButton(label: "收回") { session.withdrawGuess() }
                    CardButton(label: "就是这步", isOn: true, isEnabled: session.canCommitGuess) {
                        session.commitGuess()
                    }
                }
                if !engine.isReady {
                    Text("引擎还没准备好，没法给这步打分。")
                        .font(.caption)
                        .foregroundStyle(Palette.alarm)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        } else if session.isStudying {
            VStack(alignment: .leading, spacing: 4) {
                Text("轮到\(viewed.state.sideToMove.chinese)走。你会走哪一步？")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                // Why here. Tapping one of the three chips leaves the list behind, and a board
                // asking a question with no account of why it picked this position is a question
                // you can only take on trust.
                if let (place, ranked) = questionPlace {
                    Text(
                        session.isPractising
                            // The size is the answer to the question being asked, so while the
                            // engine is silent this says which of the three it is and no more.
                            ? "这是这局得失最大的第 \(place) 步。实战在这儿走的那步，引擎重算下来不值。"
                            : "这局得失第 \(place) 大的一步：实战走的 \(ranked.san)，\(Self.cost(ranked.lost)) 分。"
                    )
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Text("直接在棋盘上走一步。走完才会告诉你结果。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        } else if isPast {
            Text("引擎意见开着，这一步的分已经在上面了。关掉那只眼睛，这一步才能当题做。")
                .font(.caption)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
        }
    }

    /// 练习 — you play, then this card says what the move bought, what it cost, and what the
    /// engine would have done. A past Ply is a Drill; pointing at a square is how you think
    /// before you commit.
    @ViewBuilder private var drillBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            study
            if session.guess == nil, session.reveal == nil, !session.isRevealing {
                scannerBody
            }
        }
    }

    /// The eight answers to 为什么, in one row. Seven verbs that can be told false and 说不清,
    /// which is a declaration and not a refusal to make one — so it sits with the others, in the
    /// same row and the same shape (docs/adr/0018).
    ///
    /// One row and not two, because the room under the record is measured in tens of points: the
    /// eight of them are the question, and a question whose second half is below the fold is one
    /// half of a question.
    private var verbs: some View {
        HStack(spacing: 5) {
            ForEach(Intent.Verb.allCases, id: \.self) { verb in
                Button {
                    session.choose(session.declaringVerb == verb ? nil : verb)
                } label: {
                    Text(verb.label)
                        .font(.subheadline)
                        .frame(minWidth: 30)
                        .padding(.vertical, 7)
                        .foregroundStyle(
                            session.declaringVerb == verb ? Palette.parchment : Palette.ink
                        )
                        .background(
                            session.declaringVerb == verb ? Palette.analysis : Palette.chipRest,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            Button {
                session.declareUnclear()
            } label: {
                Text(Intent.unclearLabel)
                    .font(.footnote)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .foregroundStyle(
                        session.declaredIntent == .unclear ? Palette.parchment : Palette.inkSoft
                    )
                    .background(
                        session.declaredIntent == .unclear ? Palette.analysis : Palette.chipRest,
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
    }

    /// What the claim reads as so far — the one line that tells somebody a verb still needs a
    /// square, which is the only way this control can be got wrong.
    private var reason: String {
        if let intent = session.declaredIntent {
            return intent == .unclear ? "说不清 —— 记下来了。" : "因为 \(intent.label)。"
        }
        if let verb = session.declaringVerb {
            return "\(verb.label) 哪里？点棋盘上的格子。"
        }
        return "先说说这步是干什么的。"
    }

    /// Three moves side by side, never one number. "Your move" against "the engine's" against
    /// "what was actually played" — because being level with the engine, matching what you did
    /// last time, and finding the move are three different pieces of news.
    private func revealed(_ reveal: Reveal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The headline names both outcomes without multiplying them: right move for the wrong
            // reason and wrong move for the right reason are different failures with different
            // remedies, and only one of them is visible in any other chess app.
            Text(headline(reveal))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(reveal.counts == false ? Palette.alarm : Palette.ink)
            Text(verdict(reveal)).font(.caption).foregroundStyle(Palette.inkSoft)
            if let check = reveal.intentCheck, let intent = reveal.intent {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(intent.label).font(.footnote.weight(.medium))
                    Text(Self.intentVerdictLabel(check.verdict))
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Self.intentVerdictColour(check.verdict).opacity(0.2), in: Capsule()
                        )
                    Spacer(minLength: 0)
                }
                if let note = check.note {
                    Text(note).font(.caption).foregroundStyle(Palette.inkSoft)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                revealRow("你走", reveal.guess, reveal.guessScore, prominent: true)
                if !reveal.isSameAsBest {
                    revealRow("引擎", reveal.best ?? "—", reveal.bestScore)
                }
                if !reveal.isSameAsPlayed {
                    revealRow("实战", reveal.played, reveal.playedScore)
                }
            }
            // The engine's own reason, in the words the player just used for theirs. Two claims in
            // the same seven verbs is a comparison; a number against a sentence is not
            // (docs/adr/0020).
            if let reading = reveal.bestReading {
                let subject = reveal.isSameAsBest ? "这步" : "引擎那步"
                Text(
                    reading.opening.intent == .unclear
                        ? "\(subject)为什么好，这里说不清。"
                        : "\(subject)是为了 \(reading.sentence)"
                )
                .font(.caption)
                .foregroundStyle(Palette.inkSoft)
            }

            HStack(spacing: 9) {
                if !reveal.isSameAsPlayed {
                    CardButton(label: "改走这步") { session.keepGuess() }
                }
                CardButton(label: "再来一次") { session.withdrawGuess() }
                if let next = nextQuestion {
                    CardButton(label: "下一题", isOn: true) { jump(toQuestion: next) }
                }
            }
            Text("三步都按深度 \(reveal.depth) 算，所以彼此可以比。")
                .font(.caption)
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func revealRow(
        _ title: String, _ san: String, _ score: Score?, prominent: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.caption).foregroundStyle(Palette.inkSoft).frame(width: 30, alignment: .leading)
            Text(san).font(.notation).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            ScoreCell(score: score, prominent: prominent)
        }
    }

    /// Both verdicts in one sentence and no number over them.
    private func headline(_ reveal: Reveal) -> String {
        let moveIsFine = reveal.counts ?? false
        switch reveal.intentCheck?.verdict {
        case .held:
            return moveIsFine ? "走对了，理由也站得住。" : "理由是对的，这步棋没做到。"
        case .failed:
            return moveIsFine ? "这步棋没问题，但理由不成立。" : "棋和理由都没站住。"
        case .noClaim, nil:
            return moveIsFine ? "这步棋没问题。" : "这步棋没站住。"
        }
    }

    private static func intentVerdictLabel(_ verdict: IntentCheck.Verdict) -> String {
        switch verdict {
        case .held: "说对了"
        case .failed: "没做到"
        case .noClaim: "没说"
        }
    }

    private static func intentVerdictColour(_ verdict: IntentCheck.Verdict) -> Color {
        switch verdict {
        case .held: Palette.analysis
        case .failed: Palette.alarm
        case .noClaim: Palette.inkSoft
        }
    }

    private func verdict(_ reveal: Reveal) -> String {
        guard let lost = reveal.lost, let quality = reveal.quality else {
            return "引擎没给出意见，只能跟实战比。"
        }
        let gap = String(format: "%.2f", Double(abs(lost)) / 100)
        if reveal.isSameAsBest { return "就是引擎的第一选择。" }
        if lost <= 0 { return "比引擎的还好 \(gap)。" }
        return quality == .fine ? "过关：跟引擎差 \(gap)。" : "\(quality.label)：比引擎差 \(gap)。"
    }

    /// The Game's worst moves, as the questions they are (docs/adr/0017).
    ///
    /// Numbers and colours only while the engine is silent: the label 漏着 beside a move is the
    /// answer to the question about to be asked, so a list that carried it would give the game
    /// away before the board did.
    @ViewBuilder private var questions: some View {
        if let worst = session.worstMoves(3), !worst.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.isPractising ? "最该看的三步" : "这局最贵的三步")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.horizontal, 16)
                // Why these three and not three others. It is one sentence and it was missing
                // altogether: a list headed 最该看的三步 with no account of who decided is a list
                // you can only take on trust, and "我不懂这一步为什么最该看" is the right response
                // to one. The rank is on each chip for the same reason — three chips in a row do
                // not look ordered unless they say they are.
                Text("引擎按统一深度重算了全局，这三步的得失最大，从大到小排。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                // Sideways rather than squeezed. Three chips carrying a rank, a move and what it
                // cost do not fit across a phone, and the one that gave way was the move's own
                // name — truncated to "4…" inside a chip whose whole job is to name a move. It
                // only scrolls when it has to (`basedOnSize`), so on a game whose three fit it is
                // still just a row.
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                    ForEach(Array(worst.enumerated()), id: \.element.ply) { place, ranked in
                        Button { jump(toQuestion: ranked) } label: {
                            HStack(spacing: 5) {
                                Text("\(place + 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Palette.parchment)
                                    .frame(width: 15, height: 15)
                                    .background(Palette.inkSoft, in: Circle())
                                let number = session.game.moveNumber(ofPly: ranked.ply)
                                if session.isPractising {
                                    // No move to name, so the turn has to be named in words.
                                    Text("第 \(number) 回合").font(.caption)
                                    Text(ranked.mover.chinese).font(.caption)
                                } else {
                                    // The way a game is written down: "4." is White's fourth move
                                    // and "4…" is Black's answer to it. Three of these have to
                                    // stand side by side on a phone, where "第 4 回合 白方 c3 ??"
                                    // wrapped inside its own chip — and anybody reading a score
                                    // sheet has to know this notation anyway.
                                    Text("\(number)\(ranked.mover == .white ? "." : "…") \(ranked.san)")
                                        .font(.notation)
                                    // What it cost, which is the whole of why it is on this list —
                                    // and said instead of the 漏着 that used to stand here, not
                                    // beside it. The mark is a name for this number and the ply
                                    // report above is already wearing it; two of them in one chip
                                    // was what pushed the move's own name out of the chip.
                                    //
                                    // Only with the engine talking: while it is silent this is the
                                    // answer to the question about to be asked.
                                    Text(Self.cost(ranked.lost))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(
                                            ranked.lost > 0 ? Palette.alarm : Palette.analysis
                                        )
                                }
                            }
                            .lineLimit(1)
                            .foregroundStyle(
                                session.cursor == ranked.ply - 1 ? Palette.analysis : Palette.ink
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Palette.chipRest, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
        }
    }

    /// What a ranked move cost its mover, in pawns. A move that *gained* is ranked too and reads
    /// as a gain rather than a negative loss — "−0.30 丢分" is a sentence nobody parses.
    private static func cost(_ lost: Int) -> String {
        let pawns = String(format: "%.1f", Double(abs(lost)) / 100)
        return lost > 0 ? "−\(pawns)" : "+\(pawns)"
    }

    /// Where the position on screen stands in that list of three, when it is one of them.
    ///
    /// The list is ranked and the chips say so, but somebody who tapped one and is now looking at
    /// a board has left the list behind — and the board's own question, 你会走哪一步, says nothing
    /// about why it is being asked here.
    private var questionPlace: (place: Int, ranked: Criticality)? {
        guard let worst = session.worstMoves(3) else { return nil }
        guard let index = worst.firstIndex(where: { $0.ply - 1 == session.cursor }) else {
            return nil
        }
        return (index + 1, worst[index])
    }

    /// The next worst move that is not the one already on screen, so 下一题 walks the three in
    /// order rather than re-asking the one just answered.
    private var nextQuestion: Criticality? {
        guard let worst = session.worstMoves(3) else { return nil }
        return worst.first { $0.ply - 1 != session.cursor }
    }

    private func jump(toQuestion ranked: Criticality) {
        selected = nil
        // To the position the move was played *from*: the question is what to play here, so the
        // move itself has to still be ahead of the cursor.
        session.jump(toPly: ranked.ply - 1)
    }

    /// 五步计划 — one Intent over a line of your own rather than over one move.
    ///
    /// docs/adr/0017 said an Intent should be able to hang off a Variation and nothing was ever
    /// built for it; this is that. The mirror of the carousel: that one shows the engine's plan
    /// landing, this one puts your own on trial. The cap is five and its reason is on the screen,
    /// because a cap whose reason lives only in an ADR reads as an arbitrary limit.
    @ViewBuilder private var planBody: some View {
        if isPast {
            VStack(alignment: .leading, spacing: 6) {
                if let draft = session.planDraft {
                    drafting(draft)
                } else if session.planCheck == nil {
                    CardLede("在棋盘上走五步，说一个理由，让引擎判对错。")
                    CardActions {
                        CardButton(label: "开始写", isOn: true) {
                            selected = nil
                            withAnimation(.snappy(duration: 0.2)) { session.startPlan() }
                        }
                    }
                }
                if let check = session.planCheck { judged(check) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        } else {
            // A plan is committed as a Variation at a Ply (docs/adr/0018), and the latest position
            // has no Ply after it to hang one on: a plan from here is just playing the game.
            Text("五步计划要挂在走过的一步上 —— 交卷之后它作为一条变着存进棋谱。用记录条退回一步再来。")
                .font(.caption)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
        }
    }

    /// The board as a place to try a line out: what you walked, what the engine says next, and the
    /// one reason it is all for.
    @ViewBuilder private func drafting(_ draft: PlanDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // What you actually played. This is the plan — the rows below are advice.
            if draft.isEmpty {
                Text("在棋盘上随便走。走一步，下面就重算一次后面五步。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 7) {
                    Text("你走的")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                    Text(draft.sans.joined(separator: " "))
                        .font(.notation)
                        .foregroundStyle(Palette.mine)
                    Spacer(minLength: 0)
                }
            }

            if session.isPlanning {
                EmptyView()
            } else if session.planNotes.isEmpty {
                // Not an error and not a dead end: the board is still a board.
                Text("引擎没给出线路。自己在棋盘上走也行。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // One line, not three. It used to say the same thing twice — once about the
                // colours and once about the tapping — in a window 100 points tall.
                CardNote("紫色是你的，红色是对方最好的应手 —— 不是猜你对手；点哪一行就走到哪一步。")
                // The rows are the point of the whole section: five moves is a line, five moves each
                // with a reason and a cost is a plan somebody could have thought of.
                ForEach(session.planNotes, id: \.step) { note in
                    step(note)
                }
            }

            if draft.isTooLong {
                Text("走了 \(draft.steps.count) 步了。计划最多五步 —— 再长对方回得太多，对错就没法判了。退回五步以内才能交卷。")
                    .font(.caption)
                    .foregroundStyle(Palette.alarm)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !draft.isEmpty {
                // One reason for the whole of what you walked, said in the same eight words a single
                // move's is. The moves may have come from the engine; this half did not, and this is
                // the half that is marked (docs/adr/0021).
                Text("你走的这条线是为了什么？说错了会告诉你。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                verbs
                Text(reason).font(.caption).foregroundStyle(Palette.inkSoft)
                CardActions {
                    CardButton(label: "交卷", isOn: true, isEnabled: session.canCommitPlan) {
                        session.commitPlan()
                    }
                    CardButton(label: "退一步") { session.undoPlanMove() }
                    CardButton(label: "收起") {
                        withAnimation(.snappy(duration: 0.2)) { session.abandonPlan() }
                    }
                }
            }
        }
    }

    /// One numbered row: the move, what it is for, and what it gives away.
    ///
    /// Tappable, and what it does is *play* — tapping row three walks the board three moves down the
    /// line. The number on it is the number on an arrow, so what a tap does is visible before it
    /// happens. Every row is shown rather than only the next one: "and then what" is a question
    /// about the moves you have not got to yet.
    @ViewBuilder private func step(_ note: PlanNote) -> some View {
        Button {
            session.followPlan(through: note.step)
        } label: {
            // The same row every numbered thing on this screen uses: the figure that is also on
            // the board, the move, what it is for, and what it gives away.
            // No verb chip beside the move: the first line of 值 already opens with the verb and
            // its square, and the same two words twice on one row reads as two different claims.
            CardRow(
                badge: .step(note.step, isYours: note.isYours),
                move: note.san,
                tag: note.isYours ? nil : "对方",
                text: note.gains.joined(separator: "；"),
                under: note.costs.isEmpty ? nil : note.costs.joined(separator: "；")
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            // Tappable: the board walks to this step, which is what the number is for.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The verdict: which move of the plan made the claim true, or the state it actually left.
    @ViewBuilder private func judged(_ check: PlanCheck) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.game.plans(atPly: session.cursor).last?.intent.label ?? "")
                    .font(.footnote.weight(.medium))
                Text(Self.intentVerdictLabel(check.verdict))
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Self.intentVerdictColour(check.verdict).opacity(0.2), in: Capsule())
                if let step = check.step, let san = check.san {
                    Text(
                        check.held
                            ? "第 \(step) 步 \(san) 的时候成立"
                            : "走到第 \(step) 步 \(san) 还是没成立"
                    )
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                }
                Spacer(minLength: 0)
            }
            if let note = check.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let outcome = session.planOutcome {
                Text(outcome.sentence)
                    .font(.caption)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("这条线进了棋谱，是这一步的一个变着。")
                .font(.caption2)
                .foregroundStyle(Palette.inkSoft)
        }
    }

    /// 点一格问它 — the one thing on this screen allowed to speak before a Guess is committed.
    ///
    /// And it only ever speaks about the square somebody pointed at. Everything else on the layer
    /// waits for the commit, because a warning painted unprompted is the blunder check performed on
    /// the player's behalf, which is the one thing they are here to learn to do (docs/adr/0015).
    /// The order inside it is the whole design: which of your pieces can get there, then what the
    /// move you picked is worth in your own terms, and the engine's opinion last and only on a tap.
    /// Reversed, it is a hint button (docs/adr/0020).
    ///
    /// The chip that used to arm it has gone: arriving at this card is the arming, and leaving puts
    /// the board back. A layer that only *draws* may follow the card it is named on; anything that
    /// starts a search still keeps a press of its own (docs/adr/0023).
    @ViewBuilder private var scannerBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if session.planDraft != nil {
                Text("在写五步计划。问一格先让位 —— 一块棋盘上只放一个假设。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let scan = session.scan {
                scanned(scan)
            } else if session.isScannerArmed {
                Text("点棋盘上任意一格，看你哪些子能过去。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
            } else {
                CardButton(label: "再问一格") { session.armScanner() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    /// The ways in, then the trial, then the engine — in that order and never another.
    @ViewBuilder private func scanned(_ scan: Scan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if scan.isEmpty {
                Text("\(scan.target)：你一个子也过不去。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
            } else if let trial = session.trial {
                // One row shape for both readings, and the dot's colour is the only difference
                // between what a move buys and what it costs.
                CardRow(badge: .none, move: "\(trial.san)：", text: "", isNamed: true)
                ForEach(trial.gains, id: \.self) { line in
                    CardRow(badge: .mark(isGain: true), text: line)
                }
                ForEach(trial.costs, id: \.self) { line in
                    CardRow(badge: .mark(isGain: false), text: line)
                }
                HStack(spacing: 9) {
                    CardButton(label: "换一个") { session.takeBackTrial() }
                    if session.scanAnswer == nil, !session.isAsking {
                        // Last, and on a tap. Before this button is pressed the engine has not been
                        // asked anything at all — not asked and hidden, not asked (docs/adr/0015).
                        CardButton(label: "引擎怎么说", isOn: true) { session.askEngine() }
                    }
                    Spacer(minLength: 0)
                }
                if session.isAsking {
                    EmptyView()
                }
                if let answer = session.scanAnswer { engineAnswer(answer) }
            } else {
                Text("\(scan.target)：\(scan.arrivals.count) 个子能过去。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                // Cheapest first, because the cheapest way in is the one worth weighing first.
                HStack(spacing: 7) {
                    ForEach(scan.arrivals, id: \.san) { arrival in
                        Button { session.tryOut(arrival.move) } label: {
                            Text(arrival.san)
                                .font(.notation)
                                .foregroundStyle(Palette.ink)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Palette.chipRest, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private func engineAnswer(_ answer: ScanAnswer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(answer.isSameAsTrial ? "引擎也走" : "引擎走")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                Text(answer.best).font(.notation).foregroundStyle(Palette.ink)
                ScoreCell(score: answer.score)
                Spacer(minLength: 0)
            }
            if let reading = answer.reading {
                CardNote(
                    reading.opening.intent == .unclear
                        ? "引擎那步为什么好，这里说不清。"
                        : "引擎那步是为了 \(reading.sentence)"
                )
            }
            CardNote("深度 \(answer.depth)")
        }
    }

    /// Same family as 问一格: a layer you turn on, not a twin of 练习. 练习 is the eval strip;
    /// this is a question about the position (docs/adr/0022).
    ///
    /// It says what the press *does*, not what the card is called: a chip labelled 战术 under a
    /// head that also says 战术 is a switch nobody can read (docs/adr/0023).
    private var finderChip: some View {
        CardButton(
            label: session.isFindingTactics ? "不找了" : "找一记",
            isOn: !session.isFindingTactics,
            isEnabled: engine.isReady || session.isFindingTactics
        ) {
            withAnimation(.snappy(duration: 0.2)) {
                session.setFindingTactics(!session.isFindingTactics)
            }
        }
        .accessibilityLabel("战术发现器")
        .accessibilityValue(session.isFindingTactics ? "开" : "关")
    }

    /// 战术, and the one press ADR-0022 asked for.
    ///
    /// The switch did not become the card, and that is the line this deck draws: 要害 and 走马灯
    /// only *draw* on a board, so arriving at their card is enough, but the finder spends a search
    /// — bounded, but a real one — so it keeps a deliberate press of its own (docs/adr/0022, 0023).
    @ViewBuilder private var tacticsBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                finderChip
                Spacer(minLength: 0)
            }
            if session.isFindingTactics {
                tacticAnswer
            } else {
                Text("按一下「找一记」，引擎拿一次短搜索看这一步有没有一记赢子的 —— 顺手也就看出来有没有杀。不按就不算。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    /// The finder's answer, under the chip that asked — the same place a scan writes.
    @ViewBuilder private var tacticAnswer: some View {
        if let prompt = session.tacticPrompt {
            Button {
                guard let line = session.tactic?.line, !line.isEmpty else { return }
                selected = nil
                session.startWalk(line: line)
            } label: {
                Text(prompt)
                    .font(.caption)
                    .foregroundStyle(session.tactic == nil ? Palette.inkSoft : Palette.analysis)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .disabled(session.tactic?.line.isEmpty != false)
            .accessibilityLabel(prompt)
        }
    }

    private func sentence(_ text: String, colour: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(colour).frame(width: 6, height: 6)
                .padding(.top, 5)
            Text(text)
                .font(.caption)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 这步的要害 — what this move is for, and why it was played.
    ///
    /// The last Ply of the position on screen, including the latest: there is no rewind to wait
    /// for. An empty Game still answers, from the engine's next move. A Guess still being held
    /// is the player answering, and this card does not speak over that.
    @ViewBuilder private var keyBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if session.guess != nil, session.reveal == nil {
                Text("先交卷。交卷之前引擎不开口，这里也就还没有话说。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let purpose = movePurpose {
                if purpose.opening.intent == .unclear {
                    CardLede("\(purpose.opening.san) 为什么下，这里说不清。")
                } else {
                    CardLede("\(purpose.opening.san) 是为了\(purpose.opening.intent.goal)")
                    CardNote(purpose.opening.intent.label)
                    if let later = purpose.later {
                        if later.intent.goal == purpose.opening.intent.goal {
                            CardNote("第 \(later.step) 步再 \(later.label)")
                        } else {
                            CardNote(
                                "第 \(later.step) 步再\(later.intent.goal)：\(later.label)"
                            )
                        }
                    }
                }
            } else if !session.isSearching {
                Text("滑到这张卡会算 10 秒。算完就说这一步是为了什么。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !looseSquares.isEmpty, session.walk == nil {
                Text("红圈：被吃的子比守的多")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    /// What the move on screen is for. The last Ply if there is one, otherwise the engine's next.
    private var movePurpose: LineReading? {
        if session.guess != nil, session.reveal == nil { return nil }
        return viewed.purpose(continuation: session.viewedContinuation)
    }

    /// 走马灯 — the stored Line played out on the board, a Ply at a time.
    ///
    /// Never a line the app went and fetched: what plays is whichever one somebody already paid
    /// for, a Review's or a Reveal's (docs/adr/0019, 0020). Arriving at the card starts it and
    /// leaving puts the board back, which is what makes the whole thing ephemeral.
    @ViewBuilder private var walkBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let walk = session.walk {
                transport(walk)
            } else if session.viewedContinuation.isEmpty {
                if !session.isSearching {
                    Text("这一步还没有引擎的线可走。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                }
            } else {
                CardButton(label: "从这儿走一遍") { session.startWalk() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    /// The transport, and where the whole line arrives.
    ///
    /// Both halves matter and the second one is the point: a carousel that only recites moves leaves
    /// a beginner watching five plies go by and unable to say what changed. The sentence compares
    /// the end of the line with its start, out of the same fixed templates over checkable facts as
    /// the rest of the layer (docs/adr/0020).
    @ViewBuilder private func transport(_ walk: Walk) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // The line *is* the transport: tapping the third move walks to the third move. There
            // were three chevrons and a counter here, which is a tape deck for something that was
            // never a tape — and the numbers on the chips are the numbers on the board's arrows.
            CardLede(walk.outcome.sentence)
            HStack(spacing: 8) {
                Text("第 \(walk.step)/\(walk.line.count) 步")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                Spacer(minLength: 0)
                CardButton(label: "回到开头", isEnabled: !walk.isAtStart) {
                    session.stepWalk(by: -walk.step)
                }
            }
            CardMoves(
                moves: walk.line.enumerated().map { index, san in
                    CardMoves.Move(
                        step: index + 1, san: san, isYours: index.isMultiple(of: 2)
                    )
                },
                standing: walk.step,
                tap: { step in session.stepWalk(by: step - walk.step) }
            )
            Text("这几步没有走进棋谱，退出就回到原来的位置。")
                .font(.caption2)
                .foregroundStyle(Palette.inkSoft)
        }
    }



    // ------------------------------------------------------------------ the report

    /// What the engine has to say about the whole game, on the same screen it was played on.
    ///
    /// This is 复盘. It used to be a screen you went to; it is what the switch turns on
    /// (docs/adr/0015), and a Game that has never had a uniform-depth pass gets one here —
    /// turning the switch on is the only moment that can start one (docs/adr/0016).
    @ViewBuilder private var report: some View {
        if !session.isPractising {
            VStack(alignment: .leading, spacing: 10) {
                if let pass = session.reviewPass, pass.isRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在用深度 \(pass.depth) 重算：\(pass.completed)/\(max(pass.total, 1))")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                if session.game.isReviewed {
                    // No curve here: it is in the record, which is the other picture of the same
                    // thing and already on screen. What is left is what the curve cannot say —
                    // which move the eye is on, what the pass made of it, and at what Depth.
                    plyReport
                } else if let reason = engine.unavailableReason {
                    Text(reason).font(.caption).foregroundStyle(Palette.alarm)
                } else if session.reviewPass == nil, !session.game.plies.isEmpty {
                    HStack(spacing: 9) {
                        Text("这局还没打过分。").font(.footnote).foregroundStyle(Palette.inkSoft)
                        CardButton(label: "打分", isOn: true) { session.startReview() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        } else {
            // The one card a swipe does not open by itself: a pass re-scores the whole game at a
            // uniform depth and writes what it finds (docs/adr/0016), which is minutes and a
            // change to the file — not something to start by turning a page (docs/adr/0023).
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    session.game.plies.isEmpty
                        ? "还没走棋，没什么可复盘的。"
                        : "复盘要引擎开口：按统一深度把这一局每一步重算一遍，然后这局最贵的三步就在下面。"
                )
                .font(.caption)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                if !session.game.plies.isEmpty {
                    CardButton(label: "打分", isOn: true, isEnabled: engine.isReady) {
                        session.startReview()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    /// The move the eye is on, what the pass made of it, and its Score.
    @ViewBuilder private var plyReport: some View {
        let ply = session.cursor
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if ply > 0, let played = session.game.plies[safe: ply - 1] {
                Text("第 \(session.game.moveNumber(ofPly: ply)) 回合 \(session.game.mover(ofPly: ply).chinese) \(played.san)")
                    .font(.subheadline.weight(.medium))
                if let quality = session.game.quality(atPly: ply), quality != .fine {
                    Text(quality.label)
                        .font(.footnote.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (quality == .blunder ? Palette.alarm : Color.orange).opacity(0.2),
                            in: Capsule()
                        )
                }
            } else {
                Text("起始局面").font(.subheadline.weight(.medium))
            }
            // Named, because a Score without a depth compares to nothing — but said as two words
            // beside the number it qualifies rather than as a sentence on a row of its own. The
            // way to change it is in the ⋯ menu, with the other things done once a game.
            Text("深度 \(session.game.reviewDepth ?? GameSession.reviewDepth)")
                .font(.caption2)
                .foregroundStyle(Palette.inkSoft)
            Spacer(minLength: 0)
            ScoreCell(score: session.game.reviewScore(atPly: ply), prominent: true)
        }
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
            .padding(.top, 8)
        }
    }

    private func seriesButton(_ label: String, symbol: String, at index: Int) -> some View {
        let target = placeInSeries?.entries[safe: index]
        return Button {
            if let target { turnTo(target) }
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
                    Text(session.shaky.shakySummary ?? "照片认错了棋子？")
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
            .padding(.top, 8)
        }
    }

    /// The lines the engine is weighing behind the one it is offering.
    ///
    /// The first line is in the bar of the side it is advice for; these are the runners-up, and
    /// they are reading rather than acting — which is why they are down here, where a third line
    /// appearing cannot change the size of the board.
    @ViewBuilder private var alternatives: some View {
        let rest = Array((session.analysis?.lines ?? []).dropFirst().prefix(2))
            .compactMap { line in line.san.first.map { (san: $0, score: line.score) } }
        if !session.isPractising, !rest.isEmpty {
            // The moves, not the lines. Eight plies of notation per candidate is three sentences
            // of a language a club player reads and nobody else does, and it was two rows of a
            // window that has about four. What somebody can actually use is "these were the other
            // moves worth a look, and this is what each is worth".
            HStack(spacing: 8) {
                Text("其它选择").eyebrow()
                ForEach(Array(rest.enumerated()), id: \.offset) { _, candidate in
                    HStack(spacing: 5) {
                        Text(candidate.san).font(.notation).foregroundStyle(Palette.ink)
                        ScoreCell(score: candidate.score)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Palette.chipRest, in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .animation(.none, value: session.analysis?.depth)
        }
    }

    /// The lines that were played from here instead of the move that follows. With the record,
    /// because that is what they are: a piece of it that was left to one side.
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

    /// The few things the screen has to say in words rather than show — all of them about what
    /// to do next, which is why they come before the lines the engine is weighing.
    @ViewBuilder private var notes: some View {
        if viewed.isOver || session.isPractising || session.isSelfPlaying {
            notesBody
        }
    }

    private var notesBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewed.isOver {
                // The result is at the top and on the bar; what is left to say is what to do next.
                Text(
                    session.isPractising
                        ? "这局走完了。点棋盘下面那只眼睛，引擎会把每一步重新打一遍分。"
                        : "这局走完了。曲线和每一步的得失都在下面。"
                )
            }
            // Nothing here about practice any more. It used to say "练习中，引擎不给意见。想看它怎么
            // 说，打开上面的「引擎意见」" — a sentence that pointed up at a switch in the navigation
            // bar. The switch is now the eye in the strip directly under the board, wearing the
            // word 练习 while it is off, so the sentence was three lines of a phone spent
            // explaining a control that had come to explain itself.
            // What a game with nobody on the clock does, and how to stop it — which is the one
            // thing about self-play that is not on the screen already. Stepping back is a stop
            // because the engine only plays from the latest position, so browsing is where a
            // machine game is paused and 回到最新 is where it carries on.
            if session.isSelfPlaying {
                Text("双方都是引擎，程序自己走下去；翻回上一步就停")
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.inkSoft)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // ------------------------------------------------------------------ the deck

    /// One card of the deck under the record (docs/adr/0023).
    ///
    /// A kind and not an index, because the deck is **dealt from the position**: a live position
    /// deals 杀 / 战术 / 问一格, a past Ply deals 考一遍 / 要害 / 走马灯 / 五步计划, and a card that
    /// can do nothing here is not a page to swipe past. An index would land on a different card
    /// every time that changed.
    enum Card: Hashable {
        case key, mate, tactics, walk, drill
    }

    /// Every card, in one order, whatever the position.
    ///
    /// **The deck does not change shape.** Five cards that never move can be learnt; a card that
    /// cannot answer here says so on its own face.
    private var cards: [Card] {
        [.key, .mate, .tactics, .walk, .drill]
    }

    /// The deck, and the row of dots that says how many cards there are.
    ///
    /// The dots are the point as much as the paging is: eleven sections in a scroll never said how
    /// many there were, and 「这么多一连串的功能」 is what a screen gets called when it cannot.
    private var deckView: some View {
        TabView(selection: $card) {
            ForEach(cards, id: \.self) { kind in
                body(of: kind).tag(kind)
            }
        }
        // The index view is ours and it is above, on the card's own edge: a mate's tab wears a
        // colour of its own, and the built-in dots have no opinion about which page is urgent.
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: card) { was, now in turn(to: now, from: was) }
        // A move offered at a past Ply is the question being answered, so the deck goes to it.
        .onChange(of: session.guess?.san) { _, now in
            if now != nil { card = .drill }
        }
        // Arriving starts the walk when a line is already in hand; a Stint that lands later
        // has to start it then, or 走马灯 sits empty over a line that has just arrived.
        .onChange(of: session.viewedContinuation.isEmpty) { _, empty in
            if !empty, card == .walk, session.walk == nil { session.startWalk() }
        }
        // And a mate that turns up mid-game takes the eye, which is the whole of 「直接给予提示」
        // on a deck (docs/adr/0023). On the way in only: a 2 步杀 becoming a 1 步杀 is the same
        // news twice, and would drag somebody back to a card they had deliberately swiped away.
        .onChange(of: session.mateNews == nil) { was, now in
            guard was, !now else { return }
            // Never off a card that is already showing it — swiping to 战术 makes the probe find
            // the mate, and being thrown to 杀 for it would make 战术 unreachable — and never out
            // from under work in progress: leaving a plan card abandons the draft, and a feature
            // that eats somebody's line is worse than one that waits for a swipe.
            guard !wantsFinder(card), session.planDraft == nil, session.guess == nil else { return }
            card = .mate
        }
    }

    /// The five names, in a segmented row. The page still swipes; tapping a name is the other
    /// way to the same card.
    private var rail: some View {
        DeckRail(
            cards: cards,
            current: card,
            tint: tabColour,
            name: { $0.title },
            go: { card = $0 }
        )
    }

    /// A mate's tab wears whose it is, and only while there is a mate to be about. A tab that is
    /// red all game is not a warning, it is a decoration.
    private func tabColour(_ kind: Card) -> Color {
        if kind == .mate, let news = session.mateNews {
            return news.isOurs ? Palette.mine : Palette.alarm
        }
        return Palette.ink
    }

    @ViewBuilder private func body(of kind: Card) -> some View {
        switch kind {
        case .key: cardFrame(kind) { keyBody }
        case .mate: cardFrame(kind) { mateBody }
        case .tactics: cardFrame(kind) { tacticsBody }
        case .walk: cardFrame(kind) { walkBody }
        case .drill: cardFrame(kind) { drillBody }
        }
    }

    /// One card: one line saying what it answers, and then the thing itself. The name is on the
    /// rail above, so it is not said again here.
    private func cardFrame<Content: View>(
        _ kind: Card, @ViewBuilder body: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(kind.subtitle)
                    .font(.caption2)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                if kind == card, isCardSearching(kind) {
                    CardSearching(progress: session.searchProgress, phrase: searchPhrase(kind))
                }
                body()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { CardFade() }
    }

    private var mateInk: Color {
        guard let news = session.mateNews else { return Palette.ink }
        return news.isOurs ? Palette.mine : Palette.alarm
    }

    /// What arriving at a card does, and what leaving one undoes.
    ///
    /// **The card you are on is the card that acts.** Arriving turns its layer on — the scan, the
    /// walk, the squares, the mate's arrows, the finder — and leaving turns that layer off again,
    /// so the board is only ever drawing the one card in front of you and never the leftovers of
    /// three you swiped past (docs/adr/0023).
    ///
    /// A swipe therefore spends a Stint where the card reads a Line — 杀, 战术, 要害, 走马灯 —
    /// even during Practice: the swipe is the asking and the board stays silent. The one thing
    /// still behind a deliberate press is 复盘, which re-scores an entire game and writes what
    /// it finds (docs/adr/0016) — a swipe is not an instruction to spend minutes.
    private func turn(to now: Card, from was: Card) {
        selected = nil
        leave(was, for: now)
        arrive(at: now)
    }

    private func leave(_ was: Card, for now: Card) {
        switch was {
        case .drill: session.endScan()
        case .walk:
            session.endWalk()
            session.setShowsControlChange(false)
        case .key: session.setShowsControlChange(false)
        case .mate:
            showsMateLine = false
            if !wantsFinder(now) { closeFinder() }
        case .tactics: if !wantsFinder(now) { closeFinder() }
        }
    }

    private func arrive(at now: Card) {
        switch now {
        case .drill:
            if session.scan == nil, session.guess == nil { session.armScanner() }
        case .walk:
            session.setShowsControlChange(true)
            if session.walk == nil { session.startWalk() }
        case .mate:
            showsMateLine = true
            openFinder()
        case .tactics: openFinder()
        case .key: break
        }
        if wantsAdvice(now) { session.adviseForCard() }
    }

    /// Cards that read a Line spend a Stint on arrival, even during Practice. 练习 keeps its
    /// own bargain: the player answers first, the engine last.
    private func wantsAdvice(_ kind: Card) -> Bool {
        switch kind {
        case .mate, .tactics, .key, .walk: true
        case .drill: false
        }
    }

    /// Whether this card currently has a search in flight, so the frame can say 正在算 and the
    /// depth. Neighbouring pages stay alive in a paged TabView; only the card in front speaks.
    private func isCardSearching(_ kind: Card) -> Bool {
        switch kind {
        case .drill: session.isAsking || session.isRevealing
        default: wantsAdvice(kind) && session.isSearching && !session.isAdviceSpent
        }
    }

    private func searchPhrase(_ kind: Card) -> String {
        switch kind {
        case .walk: "正在算后面五步"
        default: "正在算"
        }
    }

    /// The two cards the finder answers for: the shot, and the mate that falls out of the same
    /// probe. Swiping between them does not stop and restart it.
    private func wantsFinder(_ kind: Card) -> Bool { kind == .mate || kind == .tactics }

    private func openFinder() {
        guard !session.isFindingTactics else { return }
        finderIsOurs = true
        session.setFindingTactics(true)
    }

    /// Puts back only what the swipe turned on. A switch somebody flipped by hand is theirs and
    /// stays as they left it — including on the strip, where it goes on colouring the mate's dot
    /// for the rest of the game.
    private func closeFinder() {
        guard finderIsOurs else { return }
        finderIsOurs = false
        session.setFindingTactics(false)
    }

    // ------------------------------------------------------------------ 杀

    /// The news: a mate somebody can already see, whoever it belongs to (docs/adr/0023).
    ///
    /// Not a switch and not an answer to anything — the one thing on this screen that arrives
    /// unbidden. It says how forced it is because that is the difference between a mate a person
    /// can follow and one they have to take on trust, and every clause of it was counted by the
    /// rules code rather than asserted.
    @ViewBuilder private var mateBody: some View {
        if let news = session.mateNews {
            VStack(alignment: .leading, spacing: 8) {
                Text(news.head)
                    .font(.cardName)
                    .foregroundStyle(mateInk)
                CardLede(news.sentence)
                if !news.san.isEmpty {
                    // The numbers are the join: the figure on a chip is the figure on its arrow.
                    CardMoves(
                        moves: news.san.enumerated().map { index, san in
                            CardMoves.Move(
                                step: index + 1,
                                san: san,
                                isYours: news.arrows.first { $0.step == index + 1 }?.isYours ?? false
                            )
                        }
                    )
                }
                HStack(spacing: 9) {
                    CardButton(
                        label: showsMateLine ? "把箭头收起" : "画在棋盘上",
                        isOn: showsMateLine,
                        isEnabled: !news.arrows.isEmpty
                    ) {
                        withAnimation(.snappy(duration: 0.2)) { showsMateLine.toggle() }
                    }
                    Spacer(minLength: 0)
                }
                if !news.isFullyDrawn {
                    CardNote("线太长，棋盘上只画了前 \(MateNews.arrowLimit) 步 —— 再多，一盘棋上就是一团线。")
                }
                CardNote("这几步没有走进棋谱。这是引擎已经算出来的东西，不是又替你算了一遍。")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        } else {
            // No news is news, and it is three different pieces of it. A card that goes blank when
            // there is no mate is a card that looks broken (docs/adr/0023).
            VStack(alignment: .leading, spacing: 6) {
                if viewed.isOver {
                    Text("这局已经走完了，没有下一步可算。")
                } else if session.isProbingTactics || session.isSearching {
                    EmptyView()
                } else if session.isFindingTactics || session.analysis != nil {
                    Text("这个局面几步之内没有杀 —— 双方都还没有强制的将死。")
                } else {
                    Text("滑到这张卡会算 10 秒。有杀的话算完就会说。")
                }
            }
            .font(.caption)
            .foregroundStyle(Palette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    /// The same violet and red the五步计划 arrows use: yours near, theirs far.
    private func arrowColour(ofStep step: Int, in news: MateNews) -> Color {
        let arrow = news.arrows.first { $0.step == step }
        return (arrow?.isYours ?? false) ? Palette.mine : Palette.alarm
    }

    /// The mate line as numbered arrows, while its own card is the one on show.
    private var mateArrows: [PlanArrow] {
        guard showsMateLine, card == .mate, let news = session.mateNews else { return [] }
        return news.arrows
    }

    // ------------------------------------------------------------------ 复盘 and the rest

    /// The pass, and the three moves it found — one card, because the three are its output and
    /// have no existence without it.
    @ViewBuilder private var reviewBody: some View {
        VStack(spacing: 0) {
            report
            questions
        }
    }

    /// The reading: where this game sits, a piece the camera got wrong, the lines that were played
    /// and left behind, and the runners-up. Nothing here is a thing to do to the position.
    @ViewBuilder private var readingBody: some View {
        VStack(spacing: 0) {
            series
            corrections
            variations
            notes
            alternatives
            if !hasReading {
                Text("这一局没有别的可读的：没归到任何合集，没有走过又放下的变着，引擎也没在权衡第二个选择。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
        }
    }

    /// Whether this card has anything on it: a collection to walk, a piece to correct, a
    /// Variation, a finished game, or the runners-up the engine is weighing. It no longer decides
    /// whether the card is dealt — every card is (docs/adr/0023) — only whether it has to explain
    /// itself.
    private var hasReading: Bool {
        session.collection != nil || session.canEditPosition || !session.variationsHere.isEmpty
            || viewed.isOver || session.isSelfPlaying
            || (!session.isPractising && (session.analysis?.lines.count ?? 0) > 1)
    }

    /// What this position cannot answer, and what would buy it.
    ///
    /// Every card is dealt now (docs/adr/0023), so no card goes quietly missing — but the
    /// dependencies are still real and are still worth having in one place: 最贵三步 is a Review's
    /// own output, 要害 and 走马灯 need a line somebody already paid for, and three of the cards
    /// want a Ply that has been played. Each of those cards says its own reason on its own face;
    /// this is the list, for somebody who would rather read it once than swipe through ten.
    @ViewBuilder private var missingBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if missing.isEmpty {
                Text("这个局面能问的，都在前面那几张卡上了。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
            } else {
                ForEach(missing, id: \.what) { row in
                    CardRow(
                        badge: .none,
                        text: row.what,
                        under: row.why,
                        underTint: Palette.inkSoft,
                        isNamed: true
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var missing: [(what: String, why: String)] {
        var rows: [(what: String, why: String)] = []
        if !isPast {
            rows.append(
                (
                    "考一遍 · 五步计划",
                    "它们说的是走过的一步 —— 用记录条退回走过的一步"
                )
            )
        } else if !session.isPractising {
            rows.append(("考一遍", "引擎意见开着，这一步的分已经在屏幕上了 —— 关掉那只眼睛才能当题做"))
        }
        if session.viewedContinuation.isEmpty, isPast {
            rows.append(
                (
                    "走马灯",
                    session.guess == nil
                        ? "滑到那张卡会算 10 秒；有线了它就有话说"
                        : "先交卷 —— 交卷之前引擎不开口"
                )
            )
        }
        if session.isPractising, !session.game.isReviewed, !session.game.plies.isEmpty {
            rows.append(("复盘 · 最贵三步", "统一深度重算全局要按一下「打分」；三步是那一遍重算的产物"))
        }
        if !session.isFindingTactics, session.analysis == nil {
            rows.append(("杀 · 战术", "滑到那两张卡会算 10 秒 —— 有杀、有战术就算完会说"))
        }
        return rows
    }

    // ------------------------------------------------------------------ the bar at the top

    /// Turns the board round — and with it, which side's controls are above and which below. The
    /// state it is in is the board, so it needs no label saying so.
    private var flip: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                session.orientation =
                    session.orientation == .whiteAtBottom ? .blackAtBottom : .whiteAtBottom
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(Palette.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("翻转棋盘")
    }

    // ------------------------------------------------------------------ the board

    /// How big the board is, and it depends on the screen and nothing else.
    ///
    /// It used to take whatever height was left over, which meant the board changed size when the
    /// engine found a third line to show — the one thing on this screen that must never move. So
    /// it is sized from the width, all but full bleed, and shrinks to leave the rest of the screen
    /// what it needs. Rounded to a multiple of eight so every square is a whole number of points
    /// and no grid line lands on a half pixel.
    ///
    /// Two bars and a record cost more than the deck they replaced, and the difference comes off
    /// the board rather than off the reading: a board forty points wider is not worth a 改棋子 row
    /// cut in half by the footer on the one screen — a board straight off a photograph — where
    /// that row is the whole job.
    static func boardSide(in size: CGSize) -> CGFloat {
        let byWidth = size.width - 16
        let byHeight = max(240, size.height - 388)
        return (min(byWidth, byHeight) / 8).rounded(.down) * 8
    }

    private var board: some View {
        BoardView(
            pieces: boardPieces,
            orientation: session.orientation,
            lastMove: session.boardLastMove,
            checks: viewed.state.checkSquares,
            // The doubtful squares stay ringed on the board being played on, right up until the
            // first move — which is what replaces the old gate: the reading's own uncertainty is
            // visible where it matters, and 改棋子 is one tap away (docs/adr/0011).
            suspects: session.unconfirmedSquares,
            selected: selected ?? session.scan?.target ?? session.declaredIntent?.target,
            destinations: Set(candidateMoves.map(\.to)),
            captures: Set(candidateMoves.filter(\.isCapture).map(\.to)),
            recommendation: recommendation,
            mine: myArrow,
            aim: session.declaredIntent?.target
                ?? (card == .key ? movePurpose?.opening.intent.target : nil),
            loose: looseSquares,
            ways: session.trial == nil ? (session.scan?.origins ?? []) : [],
            key: keySquares,
            // Whichever card is in front of you, and only that one: five arrows left over from a
            // plan you swiped away from are five arrows about a position nobody is looking at
            // (docs/adr/0023).
            plan: mateArrows,
            // Tappable while a verb is waiting for its target, too: the board is the only place a
            // claim's target can be said, which is the whole reason a verb has one.
            // Not while a line is being walked: the pieces on screen are five moves from where the
            // game is, and a tap would be a move made in a position nobody is standing in.
            isInteractive: (session.isHandTurn || session.declaringVerb != nil
                || session.isScannerArmed) && session.walk == nil,
            onTap: tap
        )
    }

    // ------------------------------------------------------------------ doing

    /// Opens the next game in the collection in place of this one.
    ///
    /// It replaces the top of the path rather than pushing, so working through fifty positions does
    /// not build a stack of fifty screens to come back through — and the way back is still the
    /// library, which is where it was. How you are working carries over — that is `session.next`.
    private func turnTo(_ entry: GameLibrary.Entry) {
        session.suspend()
        guard let next = session.next(entry) else { return }
        selected = nil
        path[path.count - 1] = .game(next)
    }

    private func tap(_ square: Square) {
        // A verb is chosen and waiting for the Square it is about, so the board is a place to
        // point at rather than a place to move on. One tap for the verb, one for the target — and
        // it goes before everything else here because it is the narrowest state on the screen.
        if session.declaringVerb != nil {
            session.aim(at: square)
            selected = nil
            return
        }
        // Armed, so the board is a place to ask about rather than a place to move on. Every tap is
        // a new question, including a tap while an answer is already up.
        if session.isScannerArmed {
            selected = nil
            session.scan(at: square)
            return
        }
        guard session.isHandTurn else { return }

        if let selected {
            let moves = tapPosition.state.moves(from: selected).filter { $0.to == square }
            // More than one move to the same square means a promotion, and only a promotion.
            if moves.count > 1 {
                promotion = PromotionRequest(moves: moves)
                self.selected = nil
                return
            }
            if let move = moves.first {
                // A plan being written takes the move instead: it is not an answer to this
                // position's question, it is the next move of a line (docs/adr/0017).
                if session.planDraft != nil {
                    session.playInPlan(move)
                    self.selected = nil
                    return
                }
                // The one difference a Drill makes to the board: while a past Ply is being
                // studied a move is *offered* — visible, uncommitted, and yours to take back —
                // rather than played into the game (docs/adr/0015).
                if session.isStudying {
                    session.offer(move)
                } else {
                    session.play(move)
                }
                self.selected = nil
                return
            }
        }

        // Not a destination, so it is either a new selection or a deselection.
        if let piece = boardPieces[square], piece.colour == tapPosition.state.sideToMove {
            selected = square
        } else {
            if selected != nil { Sounds.current.play(.refused) }
            selected = nil
        }
    }

    private func walk(_ delta: Int) {
        selected = nil
        session.step(by: delta)
    }

    private func walk(to cursor: Int) {
        selected = nil
        session.step(by: cursor - session.cursor)
    }

    // ------------------------------------------------------------------ reading the game

    /// The game where the player is looking, which is what everything on this screen is about.
    private var viewed: Game { session.viewed }

    private var pieces: [Square: Piece] {
        BoardRenderer.placement(viewed.state.fen) ?? [:]
    }

    /// What the board draws — the trial's position when one is being tried out, and the studied
    /// one otherwise. Only the board reads this: the engine, the record and the Review all go on
    /// seeing the real position, which is what keeps a trial a hypothesis (docs/adr/0020).
    private var boardPieces: [Square: Piece] {
        BoardRenderer.placement(session.board.state.fen) ?? [:]
    }

    private var candidateMoves: [Move] {
        guard let selected, session.isHandTurn else { return [] }
        return tapPosition.state.moves(from: selected)
    }

    /// The position a tap is read against — the plan's tip while one is being written, and the
    /// position being studied otherwise. Only moves go through this; everything the app *says*
    /// still comes from `viewed`.
    private var tapPosition: Game { session.planDraft != nil ? session.board : viewed }

    private var recommendation: MoveSquares? {
        // The shot is 战术's own drawing and is drawn while that card is up. The engine's
        // recommendation underneath it is the strip's — 引擎意见 is a switch on the board, not a
        // card — so it is not gated by the deck. Practice still hides it: a card's Stint may
        // have left an Analysis in hand, and that is for the card, not for the board.
        if card == .tactics, session.isFindingTactics, let tactic = session.tactic {
            return MoveSquares(from: tactic.move.from, to: tactic.move.to)
        }
        guard !session.isPractising else { return nil }
        return session.analysis?.bestMove.flatMap { MoveSquares(uci: $0) }
    }

    /// Whether the position on screen is one being studied rather than one about to be played
    /// into — the single gate both board layers hang off.
    ///
    /// The position and not the screen, and not the switch either: play and study share one board
    /// now (docs/adr/0015), so what decides whether the app is allowed to point at hanging pieces
    /// is whether the move in question has already been played. On the live position these layers
    /// would be the blunder-check performed on the player's behalf, which is precisely the habit
    /// they exist to build.
    private var isPast: Bool { !session.isAtLatest }

    /// The player's own move, drawn in their own colour beside the engine's.
    private var myArrow: MoveSquares? {
        if let trial = session.trial { return MoveSquares(uci: trial.move.uci) }
        guard let guess = session.guess else { return nil }
        return MoveSquares(from: guess.move.from, to: guess.move.to)
    }

    /// Every piece hanging in the position on screen — on the card that carries the word 红圈,
    /// and on no other. A ring with no legend anywhere on screen is a mark somebody has to guess
    /// at (docs/adr/0023).
    private var looseSquares: Set<Square> {
        guard card == .key else { return [] }
        return session.board.loosePieces ?? []
    }

    /// The one to three squares a walked Line is actually about (docs/adr/0020).
    ///
    /// The rules net is in the package; what the screen supplies is the engine's expected
    /// continuation, and it never starts a search to get one — it is whichever line a Review or a
    /// Reveal already produced. No line, no claim.
    private var keySquares: [KeySquare] {
        // 走马灯 still follows the squares; the 要害 card itself now names the move's purpose.
        guard card == .walk, session.showsControlChange else { return [] }
        return session.board.keySquares(continuation: session.boardContinuation)
    }

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

    /// The colour whose pieces stand at the top of the board, and so the colour whose controls
    /// belong above it. Flipping the board moves them, which is the whole idea.
    private var topColour: PieceColour {
        session.orientation == .whiteAtBottom ? .black : .white
    }

    private var bottomColour: PieceColour {
        session.orientation == .whiteAtBottom ? .white : .black
    }

    /// Whether this colour is the one to move in the position being looked at — which is where
    /// the mark down the bar, the action and the engine's line all go.
    private func isOnClock(_ colour: PieceColour) -> Bool {
        !viewed.isOver && viewed.state.sideToMove == colour
    }

    private var moveCards: [MoveCard] {
        var cards: [MoveCard] = []
        var number = session.game.startingFullmoveNumber
        var side = session.game.startingSideToMove

        for (index, ply) in session.game.plies.enumerated() {
            let cell = PlyCell(
                cursor: index + 1, san: ply.san, variations: ply.variations.count
            )
            if side == .white {
                cards.append(MoveCard(number: number, white: cell, black: nil))
            } else if let last = cards.last, last.number == number, last.black == nil {
                cards[cards.count - 1] = MoveCard(number: number, white: last.white, black: cell)
            } else {
                // A game that begins with Black to move, which is most games read off a photograph.
                cards.append(MoveCard(number: number, white: nil, black: cell))
            }
            if side == .black { number += 1 }
            side = side.opposite
        }
        return cards
    }
}

/// One ply as the record draws it: the cursor that puts it on the board, what it is called, and
/// how many lines were left behind at it.
struct PlyCell: Hashable {
    let cursor: Int
    let san: String
    let variations: Int
}

/// One move number and its two halves — the way a scoresheet is ruled, and the unit the record
/// is scrolled in.
struct MoveCard: Identifiable, Hashable {
    let number: Int
    let white: PlyCell?
    let black: PlyCell?
    var id: Int { number }
}

extension GameScreen.Card {
    var title: String {
        switch self {
        case .key: "要害"
        case .mate: "杀招"
        case .tactics: "战术"
        case .walk: "五步"
        case .drill: "练习"
        }
    }

    /// One line saying what the card answers, in the words of somebody who does not yet know the
    /// name above it.
    var subtitle: String {
        switch self {
        case .key: "刚走的这一步做了什么，为了什么"
        case .mate: "几步之内有人要被将死了"
        case .tactics: "这一步有没有一记赢子的"
        case .walk: "引擎说的后面几步，在棋盘上走一遍"
        case .drill: "你走一步，再看这一步的得失和引擎怎么走"
        }
    }
}
