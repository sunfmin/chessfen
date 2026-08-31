import ChessfenKit
import SwiftUI
import UIKit

/// The app's colours, and they are the board's colours.
///
/// The board is drawn from a palette that predates the app — the renderer's squares and the
/// piece artwork. Anything around it that reaches for the system's greys and blues instead ends
/// up looking like two designs stapled together, which is exactly what happens when a warm
/// wooden board sits inside stock iOS chrome. So the chrome is derived from the wood: the page
/// is a lift of the light square, the ink is a deepening of the dark one.
///
/// One colour is not wood, on purpose. Teal is what the wood cannot say: the engine's voice —
/// the recommendation arrow, the live score, the depth gauge — and the two squares of the move
/// just played. Those are the marks that have to win against the board rather than sit inside
/// it, and nothing in the wood's own range can.
/// Nonisolated, and it has to be. This target defaults every declaration to the main actor, which
/// is right for view code and wrong for a palette: SwiftUI resolves a colour on whichever thread
/// is drawing, and a dynamic provider closure that insists on the main actor traps the process the
/// first time the render thread asks it what colour it is.
nonisolated enum Palette {
    static let boardLight = Color(hex: 0xFFCE9E)
    static let boardDark = Color(hex: 0xD18B47)

    static let parchment = dynamic(light: 0xF7EDE1, dark: 0x17110C)
    /// One step up from the page, for the panels that hold data.
    static let raised = dynamic(light: 0xFFF7EE, dark: 0x241A12)
    static let ink = dynamic(light: 0x241A12, dark: 0xF2E4D5)
    static let inkSoft = dynamic(light: 0x7A6350, dark: 0xB09880)
    static let walnut = Color(hex: 0x6B4522)
    static let analysis = dynamic(light: 0x2E7D6E, dark: 0x4FB8A4)
    static let alarm = dynamic(light: 0xB3402A, dark: 0xE87A62)

    /// The two ends of the advantage bar. The pieces' own colours by day; by night the black end is
    /// lifted off the page, because a bar drawn in the page's own colour is not a bar, it is a hole
    /// — and the end of a lost game would read as an empty gauge.
    static let barBlack = dynamic(light: 0x241A12, dark: 0x4A3A2C)
    static let barWhite = dynamic(light: 0xFFFCF7, dark: 0xF2E4D5)

    /// A line and a resting chip, borrowed from whatever the page is made of: wood over paper,
    /// light over night. Tinted wood on a dark page is very nearly the dark page, which is how a
    /// deck of chips turns into an empty strip after sunset.
    static var hairline: Color { dynamic(light: walnut.opacity(0.18), dark: .white.opacity(0.16)) }
    static var chipRest: Color { dynamic(light: walnut.opacity(0.10), dark: .white.opacity(0.10)) }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        dynamic(light: Color(hex: light), dark: Color(hex: dark))
    }

    private static func dynamic(light: Color, dark: Color) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

extension Color {
    nonisolated fileprivate init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// ---------------------------------------------------------------------- type

extension View {
    /// A short label, letter-spaced. Chinese has no small caps to reach for, but 疏排 does the
    /// same work: it marks a handful of characters as a label rather than as prose.
    func eyebrow() -> some View {
        font(.caption.weight(.medium))
            .tracking(2)
            .foregroundStyle(Palette.inkSoft)
    }
}

extension Font {
    /// Numbers that change while you watch them. Rounded digits read as the numerals on a
    /// chess clock, and monospaced ones do not shuffle the layout as they tick.
    static func clock(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static let notation = Font.system(.footnote, design: .monospaced)
}

// ------------------------------------------------------------------ controls

/// The one control idiom on the screen: a wooden chip, either resting or chosen.
///
/// Before this there were four — capsules, a segmented picker, bordered buttons and plain
/// links — which is three too many for a screen whose whole job is a board and a number.
struct Chip: View {
    let label: String
    var isOn = false
    var isEnabled = true

    var body: some View {
        Text(label)
            .font(.footnote.weight(isOn ? .semibold : .regular))
            .foregroundStyle(isOn ? Palette.parchment : Palette.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(isOn ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Palette.chipRest))
            .clipShape(Capsule())
            .opacity(isEnabled ? 1 : 0.35)
    }
}

/// One colour, as the thing itself.
///
/// A disc of the piece colour beside the word does in a glance what 白方 does in two characters,
/// and it is what ties a bar to its own half of the board.
struct Swatch: View {
    let colour: PieceColour
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(colour == .white ? Palette.barWhite : Palette.barBlack)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Palette.walnut.opacity(0.45), lineWidth: 0.8))
    }
}

/// A label and its chips, hugging its content so two of them fit on one line. Kept on screen
/// rather than tucked into a menu, because what these say — which way up the board is, who
/// started, who is playing each side — are facts about the game in front of you, not settings.
struct ChipCluster<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var isEnabled = true
        var id: Value { value }
    }

    let title: String
    let options: [Option]
    let selection: Value
    let pick: (Value) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(title).eyebrow()
            ForEach(options) { option in
                Button {
                    pick(option.value)
                } label: {
                    Chip(
                        label: option.label,
                        isOn: selection == option.value,
                        isEnabled: option.isEnabled
                    )
                }
                .buttonStyle(.plain)
                .disabled(!option.isEnabled)
            }
        }
        .fixedSize()
    }
}

/// A button whose work happens while it is held down: pressing starts it, letting go finishes it.
///
/// The only one in the app, and it belongs to the engine. How long it is held is how long the engine
/// thinks (Mirrored Time, docs/adr/0009 — it is never handicapped, and time is the only dial), so
/// the control has to *be* the dial rather than a switch beside one. It fills as the search deepens,
/// which is the same gauge the header draws, under the thumb that is filling it.
///
/// Sized to sit in the bar of the side on the clock rather than to span the screen: it plays a move
/// for one colour, so it stands on that colour's side of the board.
struct HoldButton: View {
    let label: String
    let symbol: String
    /// Whether it is being held right now. Owned by the screen, because the screen has to say what
    /// the deck reads while it is.
    let isHeld: Bool
    /// How far the search has got, 0...1. Drawn only while the button is held: a search is running
    /// under this screen most of the time, and a meter standing at three quarters with nobody's
    /// thumb on it says the button is busy when it is waiting.
    var fill: Double = 0
    var isEnabled = true
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isHeld ? Palette.parchment : Palette.ink)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background {
            ZStack(alignment: .leading) {
                Palette.chipRest
                GeometryReader { proxy in
                    Palette.analysis
                        .frame(width: proxy.size.width * (isHeld ? min(max(fill, 0), 1) : 0))
                        .animation(.easeOut(duration: 0.3), value: fill)
                        .animation(.easeOut(duration: 0.2), value: isHeld)
                }
            }
            .clipShape(Capsule())
        }
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(Capsule())
        // A drag of no distance, which is a press: `onEnded` arrives wherever the finger lifts, so
        // sliding off the button still plays the move rather than leaving a search running.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled, !isHeld else { return }
                    onPress()
                }
                .onEnded { _ in
                    guard isHeld else { return }
                    onRelease()
                }
        )
    }
}

// ------------------------------------------------------------------- numbers

/// How far the engine has got, and how fast it is going.
///
/// The gauge is the signature of the screen. An engine's opinion is not finished — it deepens for
/// as long as you let it and changes its mind as it goes (docs/adr/0009) — and a filling hairline
/// says that, where a static "深度 23" label cannot. The speed is here because it is the honest
/// measure of what this phone is doing: a few million positions a second, in your hand, offline.
struct SearchMeter: View {
    let analysis: Analysis?

    /// Full depth as far as this display is concerned. Searches run deeper, and the gauge simply
    /// sits full when they do — past this point another ply is not news. Shared with the hold
    /// button, so a search reads as equally far along wherever it is drawn.
    static let deepEnough = 34.0

    var body: some View {
        HStack(spacing: 7) {
            if let analysis, analysis.depth > 0 {
                Text(Self.speed(analysis.nodesPerSecond))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Palette.inkSoft)
                Text("深 \(analysis.depth)/\(analysis.selectiveDepth)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Palette.inkSoft)
                gauge
            }
            // Nothing at all when no search has reported: an empty track is a gauge reading zero,
            // and there is no search for it to be reading zero about — over a finished game it is
            // just a grey line left on the page.
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("搜索深度 \(analysis?.depth ?? 0)")
    }

    private var gauge: some View {
        let filled = min(Double(analysis?.depth ?? 0) / Self.deepEnough, 1)
        return ZStack(alignment: .leading) {
            Capsule().fill(Palette.hairline)
            Capsule().fill(Palette.analysis).frame(width: 52 * filled)
        }
        .frame(width: 52, height: 2.5)
        .animation(.easeOut(duration: 0.35), value: filled)
    }

    private static func speed(_ nodesPerSecond: UInt64) -> String {
        nodesPerSecond >= 1_000_000
            ? String(format: "%.1fM", Double(nodesPerSecond) / 1_000_000)
            : "\(nodesPerSecond / 1000)k"
    }
}

/// Who is ahead, as a length. Laid along the bottom edge of the board rather than beside it:
/// a phone has width to spare under a square and none at all next to one, and the board is the
/// thing this screen is for.
///
/// Centipawns are unbounded and a bar is not, so the mapping squashes. A logistic curve is the
/// honest squash — it is roughly how a score turns into a winning chance, so equal-looking bars
/// mean equally close games rather than equal pawn counts.
struct EvalBar: View {
    let score: Score?
    /// The side at the left of the bar is the side at the bottom of the board.
    var orientation: Orientation = .whiteAtBottom
    /// Set once the game has ended, and then the bar reads the result instead of a Score. A
    /// finished game gives the engine nothing to search, so the number goes away — and a bar left
    /// to draw a missing number sits exactly half and half, which is the picture of a level game.
    /// Somebody who has just been mated is not level.
    var finish: Finish?

    /// How a game ended, as far as a bar is concerned.
    enum Finish: Hashable {
        case won(PieceColour)
        case drawn
    }

    var body: some View {
        let white = finish?.whiteShare ?? advantageFraction(score)
        let fraction = orientation == .whiteAtBottom ? white : 1 - white
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.barBlack)
                Rectangle()
                    .fill(Palette.barWhite)
                    .frame(width: proxy.size.width * fraction)
                // A draw is the one result that is genuinely half and half, so it cannot be said
                // with a length: it is said by taking both colours off the bar. Nobody won it.
                if finish == .drawn {
                    Rectangle().fill(Palette.walnut.opacity(0.45))
                }
            }
            // The balance point, and only while there is still a balance to be off.
            .overlay(alignment: .center) {
                if finish == nil {
                    Rectangle().fill(Palette.analysis).frame(width: 1)
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        // Outlined, or the white half vanishes into the page and an even position reads as a bar
        // that is only half there.
        .overlay(Capsule().stroke(Palette.walnut.opacity(0.35), lineWidth: 0.5))
        .animation(.easeOut(duration: 0.35), value: fraction)
        .accessibilityLabel("优势条")
        .accessibilityValue(finish?.chinese ?? score?.displayText ?? "未知")
    }
}

extension EvalBar.Finish {
    /// How much of the bar White holds at the end: all of it, none of it, or a bar that is neither.
    var whiteShare: Double {
        switch self {
        case .won(let colour): colour == .white ? 1 : 0
        case .drawn: 0.5
        }
    }

    var chinese: String {
        switch self {
        case .won(let colour): "\(colour.chinese)胜"
        case .drawn: "和棋"
        }
    }

    /// The result in the numerals a scoresheet uses, set to be read in the clock face the Score was
    /// read in — so "1/2-1/2" is written the way it is printed rather than as five characters.
    var scoreline: String {
        switch self {
        case .won(let colour): colour == .white ? "1-0" : "0-1"
        case .drawn: "½-½"
        }
    }
}

func advantageFraction(_ score: Score?) -> Double {
    guard let score else { return 0.5 }
    switch score {
    case .centipawns(let value):
        return 1 / (1 + pow(10, -Double(value) / 400))
    case .mate(let moves):
        return moves > 0 ? 1 : 0
    }
}

/// A score in a list of engine lines, in the same numerals as the big one so the eye can carry
/// a value from one to the other.
struct ScoreCell: View {
    let score: Score?
    var prominent = false

    var body: some View {
        Text(score?.displayText ?? "—")
            .font(.clock(prominent ? 15 : 14, weight: prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? Palette.analysis : Palette.inkSoft)
    }
}
