import ChessfenKit
import SwiftUI

// ===================================================================== the card

/// How far a pull left the card, in points above the peek.
///
/// The board does not move — that is the one promise this screen makes, and there is a test that
/// reads pixels to hold it to it. So a card that needs more than the room under the board takes it
/// by sliding **over** the board, and gives it back when a finger pulls down. There are no
/// detents: the card stays at the height the finger left it, clamped between the peek and the
/// board's own top edge. A tap never changes that height.
enum DeckLift {
    /// Where the card sits after a drag. `drag` is points up (SwiftUI's translation flipped).
    static func settled(lift: CGFloat, drag: CGFloat, maxLift: CGFloat) -> CGFloat {
        min(max(lift + drag, 0), max(maxLift, 0))
    }
}

/// The surface the cards are dealt onto: a raised card with a rounded top, a hairline edge, a
/// shadow that lifts it off the page, and a handle you can pull.
///
/// It is a *card* now rather than the bottom of a scroll, because a person has to be able to see
/// that there is a stack of them and that this one can be moved. The handle is the whole of that:
/// it says «grab me» in the one place both gestures live — up for more room, sideways for the next
/// card (docs/adr/0023).
struct DeckSurface<Head: View, Content: View>: View {
    /// Extra height above the peek, in points. Follows the finger and stays where it stopped.
    @Binding var lift: CGFloat
    /// The height the deck has when it is left alone. Measured from the layout rather than guessed,
    /// so peek is to the pixel what the deck occupied before it could be pulled at all.
    let peek: CGFloat
    /// How tall it is allowed to go, which is as far as the board's own top edge and no further:
    /// covering the position you are being told about would be a card talking to itself.
    let raised: CGFloat
    /// The handle and the rail. Always draggable. The body below is too, except a mostly-horizontal
    /// swipe still turns the page.
    @ViewBuilder var head: () -> Head
    @ViewBuilder var content: () -> Content

    /// Live drag, in points above the settled lift. A GestureState so it tracks the finger without
    /// going through an animated @State write every pixel — that was the hitch.
    @GestureState private var pull: CGFloat = 0

    private var maxLift: CGFloat { max(raised - peek, 0) }
    private var height: CGFloat {
        let value = peek + DeckLift.settled(lift: lift, drag: pull, maxLift: maxLift)
        return value.isFinite ? max(value, 0) : 0
    }
    /// The size the body is laid out at. Changing the *visible* height must not relayout the
    /// TabView every pixel of a drag, or the pull stutters. Layout once at the raised size, clip
    /// to what the finger has revealed.
    private var layoutHeight: CGFloat { max(raised, height, peek) }

    var body: some View {
        VStack(spacing: 0) {
            head()
                .contentShape(Rectangle())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: layoutHeight, alignment: .top)
        .frame(height: height, alignment: .top)
        .clipped()
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                topTrailingRadius: 18
            )
            .fill(Palette.raised)
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 18, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                    topTrailingRadius: 18
                )
                .stroke(Palette.hairline, lineWidth: 0.5)
            }
            .shadow(color: Palette.lift, radius: 9, x: 0, y: -3)
        }
        .simultaneousGesture(pullGesture)
        .animation(nil, value: height)
    }

    private var pullGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($pull) { value, state, transaction in
                transaction.animation = nil
                guard abs(value.translation.height) >= abs(value.translation.width) else { return }
                state = -value.translation.height
            }
            .onEnded { value in
                guard abs(value.translation.height) >= abs(value.translation.width) else { return }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    lift = DeckLift.settled(
                        lift: lift, drag: -value.translation.height, maxLift: maxLift
                    )
                }
            }
    }
}

/// While a card's search is in flight: the word, and how deep it has got. A number that
/// quietly stops moving is indistinguishable from an engine that died (docs/adr/0019).
struct CardSearching: View {
    let progress: GameSession.SearchProgress?
    var phrase: String = "正在算"

    var body: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.mini)
            Text(label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Palette.inkSoft)
                .animation(.none, value: progress?.depth)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityLabel(phrase)
        .accessibilityValue(depthValue)
    }

    private var label: String {
        if let depth = progress?.depth, depth > 0 {
            return "\(phrase) · 深 \(depth)"
        }
        return "\(phrase)…"
    }

    private var depthValue: String {
        if let depth = progress?.depth, depth > 0 { return "深 \(depth)" }
        return "开始"
    }
}

/// The handle, and the one thing it has to say: this can be pulled. A grabber, not a button —
/// tapping it does nothing; only a drag changes the height.
struct DeckHandle: View {
    var body: some View {
        Capsule()
            .fill(Palette.inkSoft.opacity(0.45))
            .frame(width: 34, height: 4)
            .frame(height: 13)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .accessibilityLabel("拉卡片")
            .accessibilityHint("向上滑看更多，向下滑放回去")
    }
}

// ====================================================================== the rail

/// What the ten cards are *about*, which is the one thing a row of ten identical dots could not
/// say. Four groups, and the gaps between them on the rail are the grouping.
///
/// This is not decoration: which group a card is in is the difference between a question about the
/// board in front of you and a question about a game you finished. Somebody who knows that much
/// can find a card without learning ten names.
enum DeckGroup: Hashable, CaseIterable {
    /// News about the position on the board right now.
    case now
    /// About the move you are standing on — the one the record's cursor is after.
    case thisMove
    /// The question that can be asked of any square at any time.
    case anySquare
    /// About the whole game, rather than about one position in it.
    case thisGame

    var name: String {
        switch self {
        case .now: "现在"
        case .thisMove: "这一步"
        case .anySquare: "任何一格"
        case .thisGame: "这一局"
        }
    }
}

/// Ten tabs, grouped, with the one you are on grown into a tab and the group you are in named
/// beside them.
///
/// A tab rather than a dot because these are cards: the mark on the edge of a card is what you
/// riffle to. It is also readable without colour — the current tab is taller and wider, not merely
/// darker — which matters for the one tab that wears a colour of its own.
struct DeckRail<Card: Hashable>: View {
    let cards: [Card]
    let current: Card
    let group: (Card) -> DeckGroup
    /// The colour of a tab. The screen decides: 杀 wears whose mate it is, everything else is ink.
    let tint: (Card) -> Color
    let name: (Card) -> String
    let go: (Card) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(DeckGroup.allCases.enumerated()), id: \.element) { index, kind in
                let members = cards.filter { group($0) == kind }
                if !members.isEmpty {
                    if index > 0 { Spacer().frame(width: 15) }
                    HStack(spacing: 0) {
                        ForEach(members, id: \.self) { card in tab(card) }
                    }
                }
            }
            Spacer(minLength: 8)
            Text(group(current).name)
                .font(.caption2.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(height: 20)
        .padding(.horizontal, 16)
    }

    private func tab(_ card: Card) -> some View {
        let isOn = card == current
        return Button {
            withAnimation(.snappy(duration: 0.22)) { go(card) }
        } label: {
            Capsule()
                .fill(isOn ? tint(card) : Palette.inkSoft.opacity(0.3))
                .frame(width: isOn ? 4 : 3, height: isOn ? 14 : 9)
                .frame(width: 13, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name(card))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// ================================================================= what is on it

/// The answer, in one sentence, and it is the first thing on every card.
///
/// Ten cards used to open ten different ways — a chip here, a heading there, a bare paragraph on a
/// third — so a person swiping through them had to work out the shape of each one before they
/// could read it. Now the first line is always the answer and everything else is under it.
struct CardLede: View {
    let text: String
    var tint: Color = Palette.ink

    init(_ text: String, tint: Color = Palette.ink) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A line of moves, numbered to match the arrows on the board.
///
/// The number is the join and the whole reason a line is drawn at all: the figure on the chip is
/// the figure on the arrow. Horizontal, because a sequence of moves is a sequence — six of them
/// down the card would be six paragraphs of nothing.
struct CardMoves: View {
    struct Move: Hashable {
        let step: Int
        let san: String
        let isYours: Bool
    }

    let moves: [Move]
    /// Which step the eye is on, when one of them is being walked.
    var standing: Int?
    var tap: ((Int) -> Void)?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(moves, id: \.self) { move in
                    let chip = HStack(spacing: 5) {
                        Text("\(move.step)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 15, height: 15)
                            .background(move.isYours ? Palette.mine : Palette.alarm, in: Circle())
                        Text(move.san).font(.notation).foregroundStyle(Palette.ink)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        standing == move.step ? Palette.chipRest.opacity(2) : Palette.chipRest,
                        in: Capsule()
                    )
                    .overlay {
                        if standing == move.step {
                            Capsule().stroke(Palette.ink.opacity(0.5), lineWidth: 1)
                        }
                    }
                    if let tap {
                        Button { tap(move.step) } label: { chip }.buttonStyle(.plain)
                    } else {
                        chip
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// One numbered row: a badge, and a sentence about the thing it is numbered on the board.
///
/// The badge's colour is the same violet-and-red the arrows and the ringed squares use — yours
/// near, theirs far — so a row needs no swatch and no legend beside it.
struct CardRow: View {
    /// What stands at the head of a row. Three kinds and no more: the figure that is also on the
    /// board, a mark that says which way this reading went, or nothing at all.
    enum Badge: Hashable {
        /// Numbered to match an arrow or a ring on the board.
        case step(Int, isYours: Bool)
        /// A gain or a cost — the scanner's two readings, and anything else that is one or the
        /// other without being part of a sequence.
        case mark(isGain: Bool)
        case none
    }

    let badge: Badge
    /// The move this row is about, set in the notation face. Above the sentence rather than
    /// inside it: a move is a name, and a name that has to be picked out of prose is a name
    /// nobody picks out.
    var move: String?
    /// One word qualifying the move — 对方, when a row of a line is a reply rather than a plan.
    var tag: String?
    var tagTint: Color = Palette.alarm
    let text: String
    /// A second line, in the small voice: what the move gives away, what the square costs.
    var under: String?
    var underTint: Color = Palette.alarm
    /// A row whose first line is the name of something rather than a sentence about it.
    var isNamed = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            mark
            VStack(alignment: .leading, spacing: 2) {
                if move != nil || tag != nil {
                    HStack(spacing: 6) {
                        if let move {
                            Text(move).font(.notation).foregroundStyle(Palette.ink)
                        }
                        if let tag {
                            Text(tag).font(.caption2).foregroundStyle(tagTint)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if !text.isEmpty {
                    Text(text)
                        .font(isNamed ? .footnote : .caption)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let under {
                    Text(under)
                        .font(.caption2)
                        .foregroundStyle(underTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var mark: some View {
        switch badge {
        case .step(let step, let isYours):
            Text("\(step)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(isYours ? Palette.mine : Palette.alarm, in: Circle())
        case .mark(let isGain):
            Circle()
                .fill(isGain ? Palette.mine : Palette.alarm)
                .frame(width: 6, height: 6)
                .frame(width: 16, height: 16)
        case .none:
            EmptyView()
        }
    }
}

/// Named figures, in one column of labels and one of numbers.
///
/// The numbers are set in the clock face the big Score uses and they are monospaced, so three
/// rows of them line up on the decimal point and can be compared by eye rather than read one at
/// a time. Every place in the app that puts a move beside what it is worth uses this.
struct CardFigures: View {
    struct Row: Hashable {
        let label: String
        let move: String?
        let value: String?
        var tint: Color = Palette.inkSoft
        var isProminent = false
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 34, alignment: .leading)
                    if let move = row.move {
                        Text(move).font(.notation).foregroundStyle(Palette.ink)
                    }
                    Spacer(minLength: 6)
                    if let value = row.value {
                        Text(value)
                            .font(.clock(row.isProminent ? 15 : 14, weight: row.isProminent ? .semibold : .regular))
                            .foregroundStyle(row.tint)
                    }
                }
            }
        }
    }
}

/// The small print: what did not happen, what is not written down, why there is nothing here.
///
/// A voice of its own because it is a different kind of statement from the answer above it — and
/// having one means the answer never has to be shrunk to make room for a caveat.
struct CardNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The bottom edge of a card with more on it than fits: the last line fades out instead of being
/// chopped. A cut sentence looks like a bug; a fading one looks like a card that can be pulled up,
/// which is exactly what it is.
struct CardFade: View {
    var body: some View {
        LinearGradient(
            colors: [Palette.raised.opacity(0), Palette.raised],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 22)
        .allowsHitTesting(false)
    }
}

/// The things you can press, in one row, in the same place on every card: last.
///
/// Explain, then offer. A card that opens with a button is a card that asks before it has said
/// what it is asking about.
struct CardActions<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            content()
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }
}

/// A chip that presses. The one control idiom on the screen (`Chip`), wired to an action, so a
/// card never has to reach for a bordered button and look like a form.
struct CardButton: View {
    let label: String
    var isOn = false
    var isEnabled = true
    let act: () -> Void

    var body: some View {
        Button(action: act) {
            Chip(label: label, isOn: isOn, isEnabled: isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
