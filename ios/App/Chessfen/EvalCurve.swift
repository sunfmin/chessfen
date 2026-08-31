import ChessfenKit
import SwiftUI

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
