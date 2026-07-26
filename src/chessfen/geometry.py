"""Locate the 8x8 grid inside a board image.

The objective is the thing that makes a chessboard a chessboard: split the candidate
rectangle into 64 cells and ask how cleanly their mean brightnesses fall into two
alternating groups. A misaligned grid blends light and dark squares together, which
drops the separation and raises the spread, so the measure has its maximum exactly at
the true grid.

The search is *exhaustive* over a window around the coarse content crop rather than a
descent, because the objective has local optima: a grid a few percent too large (say,
one that swallowed a coordinate margin) still scores respectably and no single-pixel
move improves on it. Exhaustive is affordable because a summed-area table makes each
of the 64 cell means four lookups, independent of image resolution.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Final

import numpy as np
import numpy.typing as npt

from .imaging import LumaImage, RgbImage, luma, mad

#: Channel distance from the page background that counts as content.
_CONTENT_TOLERANCE: Final = 16.0
#: Border band of each square dropped when cropping, as a cell fraction.
_SEAM_FRACTION: Final = 0.035
#: Side of the corner patches used to sample a square's background, as a cell fraction.
_CORNER_FRACTION: Final = 0.18
#: Board size search window, as a fraction of the content box's smaller side.
_SIZE_WINDOW: Final = (0.75, 1.05)
#: How far outside the content box the top left corner may sit, as a box fraction.
_SEARCH_SLACK: Final = 0.06
#: Coarse then fine step of the search, in pixels.
_SEARCH_STEPS: Final = (4, 1)
#: Smallest square side, in pixels, that this recogniser will try to read.
_MIN_CELL: Final = 8
#: Minimum checkerboard contrast for an image to count as containing a board.
_MIN_CHECKER_SCORE: Final = 1.0


class BoardNotFoundError(ValueError):
    """Raised when the image has no plausible 8x8 checkerboard in it."""


@dataclass(frozen=True, slots=True)
class BoardRect:
    """The board's pixel square. Rows count from the top, columns from the left."""

    left: int
    top: int
    size: int

    def cell(self, row: int, col: int) -> tuple[int, int, int, int]:
        """Pixel box ``(x0, y0, x1, y1)`` of one square, rounded to whole pixels."""
        x0 = self.left + round(self.size * col / 8)
        x1 = self.left + round(self.size * (col + 1) / 8)
        y0 = self.top + round(self.size * row / 8)
        y1 = self.top + round(self.size * (row + 1) / 8)
        return x0, y0, x1, y1

    def crop(self, image: RgbImage, row: int, col: int) -> RgbImage:
        """One square, shrunk by a hair to leave the seam between squares outside.

        The anti-aliased seam is a blend of the two square colours, so it reads as ink
        and - being connected to a piece that reaches the square edge - would drag a
        full ring into the silhouette. Pieces are drawn with more padding than this.
        """
        x0, y0, x1, y1 = self.cell(row, col)
        inset = max(1, round(self.size / 8 * _SEAM_FRACTION))
        return image[y0 + inset : y1 - inset, x0 + inset : x1 - inset]


def find_board(rgb: RgbImage) -> BoardRect:
    """Best-fitting board rectangle for ``rgb``."""
    gray = luma(rgb)
    integral = _integral(gray)
    left, top, right, bottom = _content_box(rgb)
    span = min(right - left + 1, bottom - top + 1)
    slack = round(span * _SEARCH_SLACK)
    height, width = gray.shape

    coarse, fine = _SEARCH_STEPS
    sizes = range(
        max(8 * _MIN_CELL, round(span * _SIZE_WINDOW[0])),
        round(span * _SIZE_WINDOW[1]) + 1,
    )
    best = _search(
        integral,
        sizes=range(sizes.start, sizes.stop, coarse),
        lefts=range(max(0, left - slack), min(width, right + 1 + slack), coarse),
        tops=range(max(0, top - slack), min(height, bottom + 1 + slack), coarse),
        bounds=(height, width),
    )
    best = _search(
        integral,
        sizes=range(max(sizes.start, best.size - coarse), best.size + coarse + 1, fine),
        lefts=range(max(0, best.left - coarse), best.left + coarse + 1, fine),
        tops=range(max(0, best.top - coarse), best.top + coarse + 1, fine),
        bounds=(height, width),
    )
    if _checker_score(gray, best) < _MIN_CHECKER_SCORE:
        raise BoardNotFoundError(
            "no 8x8 checkerboard found - crop the image down to the board"
        )
    return best


def _content_box(rgb: RgbImage) -> tuple[int, int, int, int]:
    """Inclusive ``(left, top, right, bottom)`` of everything unlike the page corners."""
    height, width = rgb.shape[:2]
    if min(height, width) < 8 * _MIN_CELL:
        raise BoardNotFoundError(f"image is too small: {width}x{height}")
    patch = max(2, min(height, width) // 20)
    corners = np.concatenate(
        [
            rgb[:patch, :patch].reshape(-1, 3),
            rgb[:patch, -patch:].reshape(-1, 3),
            rgb[-patch:, :patch].reshape(-1, 3),
            rgb[-patch:, -patch:].reshape(-1, 3),
        ]
    ).astype(np.float64)
    background = np.median(corners, axis=0)
    content = (
        np.abs(rgb.astype(np.float64) - background).max(axis=2) > _CONTENT_TOLERANCE
    )
    rows = np.flatnonzero(content.any(axis=1))
    cols = np.flatnonzero(content.any(axis=0))
    if rows.size == 0 or cols.size == 0:
        # A uniform border colour everywhere: treat the whole image as the board.
        return 0, 0, width - 1, height - 1
    return int(cols[0]), int(rows[0]), int(cols[-1]), int(rows[-1])


def _integral(gray: LumaImage) -> npt.NDArray[np.float64]:
    """Summed-area table, so any rectangle's total is four lookups."""
    return np.pad(gray.cumsum(axis=0).cumsum(axis=1), ((1, 0), (1, 0)))


def _search(
    integral: npt.NDArray[np.float64],
    *,
    sizes: range,
    lefts: range,
    tops: range,
    bounds: tuple[int, int],
) -> BoardRect:
    """Exhaustive best grid over the given candidate ranges."""
    height, width = bounds
    best = BoardRect(left=lefts.start, top=tops.start, size=sizes.start)
    best_score = -1.0
    for size in sizes:
        valid_lefts = np.array([x for x in lefts if x + size <= width], dtype=np.int64)
        valid_tops = np.array([y for y in tops if y + size <= height], dtype=np.int64)
        if valid_lefts.size == 0 or valid_tops.size == 0:
            continue
        scores = _grid_scores(integral, valid_lefts, valid_tops, size)
        flat = int(scores.argmax())
        score = float(scores.flat[flat])
        if score > best_score:
            row, col = divmod(flat, valid_lefts.size)
            best_score = score
            best = BoardRect(
                left=int(valid_lefts[col]), top=int(valid_tops[row]), size=size
            )
    return best


def _grid_scores(
    integral: npt.NDArray[np.float64],
    lefts: npt.NDArray[np.int64],
    tops: npt.NDArray[np.int64],
    size: int,
) -> npt.NDArray[np.float64]:
    """Checkerboard score of every ``(top, left)`` pair at one board size."""
    edges = np.rint(np.arange(9) * size / 8).astype(np.int64)
    xs = lefts[:, None] + edges[None, :]  # (n_left, 9)
    ys = tops[:, None] + edges[None, :]  # (n_top, 9)
    # (n_top, 9, n_left, 9) lookups, from which the 64 cell sums fall out by slicing.
    corner = integral[ys[:, :, None, None], xs[None, None, :, :]]
    sums = (
        corner[:, 1:, :, 1:]
        - corner[:, :-1, :, 1:]
        - corner[:, 1:, :, :-1]
        + corner[:, :-1, :, :-1]
    )
    spans = np.diff(edges)
    areas = spans[None, :, None, None] * spans[None, None, None, :]
    means = np.moveaxis(sums / areas, 2, 1)  # (n_top, n_left, 8, 8)

    parity = (np.arange(8)[:, None] + np.arange(8)[None, :]) % 2 == 0
    light = means[:, :, parity]
    dark = means[:, :, ~parity]
    separation = np.abs(light.mean(axis=-1) - dark.mean(axis=-1))
    return separation / (1.0 + light.std(axis=-1) + dark.std(axis=-1))


def _checker_score(gray: LumaImage, rect: BoardRect) -> float:
    """Robust contrast between the two square colours, used as the accept/reject gate.

    Corner patches and medians, rather than whole-cell means: this one has to survive
    pieces and highlight overlays without being fooled, and it only runs once.
    """
    if not _inside(rect, gray.shape):
        return 0.0
    brightness = _square_backgrounds(gray, rect)
    parity = (np.arange(8)[:, None] + np.arange(8)[None, :]) % 2 == 0
    light, dark = brightness[parity], brightness[~parity]
    separation = abs(float(np.median(light)) - float(np.median(dark)))
    return separation / (1.0 + mad(light) + mad(dark))


def _inside(rect: BoardRect, shape: tuple[int, ...]) -> bool:
    height, width = shape[0], shape[1]
    return (
        rect.size >= 8 * _MIN_CELL
        and rect.left >= 0
        and rect.top >= 0
        and rect.left + rect.size <= width
        and rect.top + rect.size <= height
    )


def _square_backgrounds(gray: LumaImage, rect: BoardRect) -> npt.NDArray[np.float64]:
    """Median corner brightness of each of the 64 squares."""
    out = np.zeros((8, 8))
    inset = max(1, round(rect.size / 8 * _CORNER_FRACTION))
    for row in range(8):
        for col in range(8):
            x0, y0, x1, y1 = rect.cell(row, col)
            samples = np.concatenate(
                [
                    gray[y0 : y0 + inset, x0 : x0 + inset].ravel(),
                    gray[y0 : y0 + inset, x1 - inset : x1].ravel(),
                    gray[y1 - inset : y1, x0 : x0 + inset].ravel(),
                    gray[y1 - inset : y1, x1 - inset : x1].ravel(),
                ]
            )
            out[row, col] = np.median(samples) if samples.size else 0.0
    return out
