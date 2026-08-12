import Foundation

/// Where a board sits in a picture: rows count from the top, columns from the left.
public struct BoardRect: Hashable, Sendable {
    public let left: Int
    public let top: Int
    public let size: Int

    public init(left: Int, top: Int, size: Int) {
        self.left = left
        self.top = top
        self.size = size
    }

    /// Pixel box of one Cell, rounded to whole pixels.
    public func cell(row: Int, column: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
        (
            x0: left + BoardGeometry.edge(size, column),
            y0: top + BoardGeometry.edge(size, row),
            x1: left + BoardGeometry.edge(size, column + 1),
            y1: top + BoardGeometry.edge(size, row + 1)
        )
    }

    /// One Cell, shrunk by a hair to leave the seam between squares outside.
    ///
    /// The anti-aliased seam is a blend of the two square colours, so it reads as Ink
    /// and — being connected to a piece that reaches the square edge — would drag a full
    /// ring into the Silhouette. Pieces are drawn with more padding than this.
    public func crop(_ image: RGBImage, row: Int, column: Int) -> RGBImage {
        let box = cell(row: row, column: column)
        let inset = max(1, BoardGeometry.rounded(Double(size) / 8 * BoardGeometry.seamFraction))
        return image.cropped(
            x: box.x0 + inset,
            y: box.y0 + inset,
            width: box.x1 - box.x0 - 2 * inset,
            height: box.y1 - box.y0 - 2 * inset
        )
    }
}

public enum RecognitionError: Error, Hashable, Sendable {
    /// No 8×8 checkerboard could be found — the picture may not be of a board at all.
    case boardNotFound
    case imageTooSmall(width: Int, height: Int)
}

/// Locates the 8×8 grid inside a board image.
///
/// The objective is the thing that makes a chessboard a chessboard: split the candidate
/// rectangle into 64 Cells and ask how cleanly their mean brightnesses fall into two
/// alternating groups. A misaligned grid blends light and dark squares together, which
/// drops the separation and raises the spread, so the measure has its maximum exactly at
/// the true grid.
///
/// The search is *exhaustive* over a window around the coarse content crop rather than a
/// descent, because the objective has local optima: a grid a few percent too large (say,
/// one that swallowed a coordinate margin) still scores respectably and no single-pixel
/// move improves on it. Exhaustive is affordable because a summed-area table makes each
/// of the 64 Cell means four lookups, independent of image resolution.
public enum BoardGeometry {
    /// Channel distance from the page background that counts as content.
    static let contentTolerance = 16.0
    /// Border band of each square dropped when cropping, as a Cell fraction.
    static let seamFraction = 0.035
    /// Side of the corner patches used to sample a square's background, as a Cell fraction.
    static let cornerFraction = 0.18
    /// Board size search window, as a fraction of the content box's smaller side.
    static let sizeWindow = (0.75, 1.05)
    /// How far outside the content box the top left corner may sit, as a box fraction.
    static let searchSlack = 0.06
    /// Coarse then fine step of the search, in pixels.
    static let searchSteps = (coarse: 4, fine: 1)
    /// Smallest square side, in pixels, that this recogniser will try to read.
    static let minimumCell = 8
    /// Minimum checkerboard contrast for an image to count as containing a board.
    static let minimumCheckerScore = 1.0

    /// Best-fitting board rectangle for `image`.
    public static func findBoard(in image: RGBImage) throws -> BoardRect {
        let grey = image.luma
        let integral = summedArea(grey)
        let box = try contentBox(image)
        let span = min(box.right - box.left + 1, box.bottom - box.top + 1)
        let slack = rounded(Double(span) * searchSlack)

        let smallest = max(8 * minimumCell, rounded(Double(span) * sizeWindow.0))
        let largest = rounded(Double(span) * sizeWindow.1)
        let (coarse, fine) = searchSteps

        var best = search(
            integral,
            sizes: stride(from: smallest, through: largest, by: coarse),
            lefts: stride(from: max(0, box.left - slack), to: min(grey.width, box.right + 1 + slack), by: coarse),
            tops: stride(from: max(0, box.top - slack), to: min(grey.height, box.bottom + 1 + slack), by: coarse),
            width: grey.width,
            height: grey.height
        )
        best = search(
            integral,
            sizes: stride(from: max(smallest, best.size - coarse), through: best.size + coarse, by: fine),
            lefts: stride(from: max(0, best.left - coarse), through: best.left + coarse, by: fine),
            tops: stride(from: max(0, best.top - coarse), through: best.top + coarse, by: fine),
            width: grey.width,
            height: grey.height
        )
        guard checkerScore(grey, best) >= minimumCheckerScore else {
            throw RecognitionError.boardNotFound
        }
        return best
    }

    /// Robust contrast between the two square colours, used as the accept/reject gate —
    /// and, once perspective correction is in play, as the judge between rectifications.
    ///
    /// Corner patches and medians, rather than whole-Cell means: this one has to survive
    /// pieces and highlight overlays without being fooled, and it only runs once.
    public static func checkerScore(_ grey: LumaImage, _ rect: BoardRect) -> Double {
        guard rect.size >= 8 * minimumCell, rect.left >= 0, rect.top >= 0,
              rect.left + rect.size <= grey.width, rect.top + rect.size <= grey.height
        else { return 0 }

        var light: [Double] = []
        var dark: [Double] = []
        let brightness = squareBackgrounds(grey, rect)
        for row in 0..<8 {
            for column in 0..<8 {
                if (row + column).isMultiple(of: 2) {
                    light.append(brightness[column, row])
                } else {
                    dark.append(brightness[column, row])
                }
            }
        }
        let separation = abs(LumaImage.median(light) - LumaImage.median(dark))
        return separation
            / (1 + LumaImage.medianAbsoluteDeviation(light)
                + LumaImage.medianAbsoluteDeviation(dark))
    }

    /// Median corner brightness of each of the 64 squares.
    private static func squareBackgrounds(_ grey: LumaImage, _ rect: BoardRect) -> Grid<Double> {
        var out = Grid<Double>(width: 8, height: 8, repeating: 0)
        let inset = max(1, rounded(Double(rect.size) / 8 * cornerFraction))
        for row in 0..<8 {
            for column in 0..<8 {
                let box = rect.cell(row: row, column: column)
                var samples: [Double] = []
                for corner in [
                    (box.x0, box.y0), (box.x1 - inset, box.y0),
                    (box.x0, box.y1 - inset), (box.x1 - inset, box.y1 - inset),
                ] {
                    for y in corner.1..<min(corner.1 + inset, grey.height) {
                        for x in corner.0..<min(corner.0 + inset, grey.width)
                        where x >= 0 && y >= 0 {
                            samples.append(grey[x, y])
                        }
                    }
                }
                out[column, row] = samples.isEmpty ? 0 : LumaImage.median(samples)
            }
        }
        return out
    }

    /// Inclusive bounds of everything unlike the page corners.
    static func contentBox(
        _ image: RGBImage
    ) throws -> (left: Int, top: Int, right: Int, bottom: Int) {
        guard min(image.width, image.height) >= 8 * minimumCell else {
            throw RecognitionError.imageTooSmall(width: image.width, height: image.height)
        }
        let patch = max(2, min(image.width, image.height) / 20)
        var reds: [Double] = [], greens: [Double] = [], blues: [Double] = []
        for (originX, originY) in [
            (0, 0), (image.width - patch, 0),
            (0, image.height - patch), (image.width - patch, image.height - patch),
        ] {
            for y in originY..<(originY + patch) {
                for x in originX..<(originX + patch) {
                    let (red, green, blue) = image.channels(x, y)
                    reds.append(red)
                    greens.append(green)
                    blues.append(blue)
                }
            }
        }
        let background = (
            LumaImage.median(reds), LumaImage.median(greens), LumaImage.median(blues)
        )

        var left = image.width, top = image.height, right = -1, bottom = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let (red, green, blue) = image.channels(x, y)
                let distance = max(
                    abs(red - background.0), abs(green - background.1),
                    abs(blue - background.2)
                )
                guard distance > contentTolerance else { continue }
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
            }
        }
        guard right >= left, bottom >= top else {
            // A uniform border colour everywhere: treat the whole image as the board.
            return (0, 0, image.width - 1, image.height - 1)
        }
        return (left, top, right, bottom)
    }

    /// Summed-area table, so any rectangle's total is four lookups. One row and column of
    /// zeroes are prepended, so the lookups never need a bounds check.
    static func summedArea(_ grey: LumaImage) -> Grid<Double> {
        var out = Grid<Double>(width: grey.width + 1, height: grey.height + 1, repeating: 0)
        for y in 0..<grey.height {
            var rowSum = 0.0
            for x in 0..<grey.width {
                rowSum += grey[x, y]
                out[x + 1, y + 1] = out[x + 1, y] + rowSum
            }
        }
        return out
    }

    /// Exhaustive best grid over the given candidate ranges.
    private static func search(
        _ integral: Grid<Double>,
        sizes: some Sequence<Int>,
        lefts: some Sequence<Int>,
        tops: some Sequence<Int>,
        width: Int,
        height: Int
    ) -> BoardRect {
        let leftCandidates = Array(lefts)
        let topCandidates = Array(tops)
        let sizeCandidates = Array(sizes)
        var best = BoardRect(
            left: leftCandidates.first ?? 0,
            top: topCandidates.first ?? 0,
            size: sizeCandidates.first ?? 8 * minimumCell
        )
        var bestScore = -1.0

        for size in sizeCandidates where size >= 8 * minimumCell {
            let edges = (0...8).map { edge(size, $0) }
            let spans = (0..<8).map { edges[$0 + 1] - edges[$0] }
            for top in topCandidates where top >= 0 && top + size <= height {
                for left in leftCandidates where left >= 0 && left + size <= width {
                    let score = gridScore(
                        integral, left: left, top: top, edges: edges, spans: spans
                    )
                    if score > bestScore {
                        bestScore = score
                        best = BoardRect(left: left, top: top, size: size)
                    }
                }
            }
        }
        return best
    }

    /// How cleanly the 64 Cell means fall into two alternating groups.
    private static func gridScore(
        _ integral: Grid<Double>,
        left: Int,
        top: Int,
        edges: [Int],
        spans: [Int]
    ) -> Double {
        var lightSum = 0.0, darkSum = 0.0
        var lightSquares = 0.0, darkSquares = 0.0

        for row in 0..<8 {
            let y0 = top + edges[row], y1 = top + edges[row + 1]
            for column in 0..<8 {
                let x0 = left + edges[column], x1 = left + edges[column + 1]
                let total =
                    integral[x1, y1] - integral[x0, y1] - integral[x1, y0] + integral[x0, y0]
                let mean = total / Double(spans[row] * spans[column])
                if (row + column).isMultiple(of: 2) {
                    lightSum += mean
                    lightSquares += mean * mean
                } else {
                    darkSum += mean
                    darkSquares += mean * mean
                }
            }
        }
        let lightMean = lightSum / 32, darkMean = darkSum / 32
        // Population standard deviation, as numpy's default.
        let lightDeviation = max(0, lightSquares / 32 - lightMean * lightMean).squareRoot()
        let darkDeviation = max(0, darkSquares / 32 - darkMean * darkMean).squareRoot()
        return abs(lightMean - darkMean) / (1 + lightDeviation + darkDeviation)
    }

    /// Pixel offset of grid line `index` in a board of side `size`.
    static func edge(_ size: Int, _ index: Int) -> Int {
        rounded(Double(size) * Double(index) / 8)
    }

    /// Half-to-even, which is what both Python's `round` and numpy's `rint` do — worth
    /// matching so a grid line never lands one pixel away from where it used to.
    static func rounded(_ value: Double) -> Int {
        Int(value.rounded(.toNearestOrEven))
    }
}
