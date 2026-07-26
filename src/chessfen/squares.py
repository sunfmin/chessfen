"""Separate "what is drawn on this square" from "what colour the square is".

Three ideas carry this stage:

* The background is the square's *modal* colour, not its border or its median. A square
  is the largest flat-coloured region in the cell, so the mode survives a piece covering
  more than half the square and survives a highlight frame drawn inside the square edge.
* The piece is the connected blob that covers the *centre* of the square. Highlight
  frames, borders and rank/file labels all live at the edges, and no shape heuristic is
  needed to reject them - they simply are not in the middle.
* Holes get filled, so a piece whose fill matches its square (white on white) still
  yields a silhouette rather than a ring.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Final

import numpy as np
import numpy.typing as npt

from .imaging import Mask, RgbImage, close, components, erode, fill_holes, luma

#: Channel distances from the background that count as ink, tried in order. Escalating
#: rescues squares whose background is not flat at all (gradients, JPEG mush).
_INK_TOLERANCES: Final = (32.0, 48.0, 64.0, 80.0)
#: Coverage above which the background estimate is deemed to have failed.
_IMPLAUSIBLE_COVERAGE: Final = 0.55
#: Blobs smaller than this fraction of the square are noise.
_MIN_BLOB_FRACTION: Final = 0.01
#: The piece must own at least this fraction of the centred box below.
_MIN_CENTRE_FRACTION: Final = 0.05
#: Hairline gaps up to this fraction of the square are bridged when grouping ink.
_BRIDGE_FRACTION: Final = 0.025
#: The centred box, as an inset fraction on each side.
_CENTRE_INSET: Final = 0.3
#: Below this total ink fraction the square is called empty.
_MIN_INK_FRACTION: Final = 0.04
#: Bits dropped per channel when histogramming for the modal colour.
_QUANTISE_BITS: Final = 3


@dataclass(frozen=True, slots=True)
class SquareReading:
    """Everything the classifier needs to know about one square."""

    background: npt.NDArray[np.float64]
    ink: Mask
    interior_luma: float
    """Median brightness of the piece body with its outline eroded away, else NaN."""

    @property
    def coverage(self) -> float:
        return float(self.ink.mean())

    @property
    def occupied(self) -> bool:
        return self.coverage >= _MIN_INK_FRACTION


def read_square(cell: RgbImage) -> SquareReading:
    """Estimate the square colour and extract the piece silhouette, if any."""
    background = modal_color(cell)
    distance = np.abs(cell.astype(np.float64) - background).max(axis=2)
    ink = np.zeros(distance.shape, dtype=np.bool_)
    for tolerance in _INK_TOLERANCES:
        ink = _select_piece(distance > tolerance)
        if ink.mean() <= _IMPLAUSIBLE_COVERAGE:
            break
    return SquareReading(
        background=background,
        ink=ink,
        interior_luma=_interior_luma(cell, ink),
    )


def modal_color(cell: RgbImage) -> npt.NDArray[np.float64]:
    """The most common colour in the cell, refined to the median of its histogram bin."""
    flat = cell.reshape(-1, 3)
    binned = flat >> _QUANTISE_BITS
    levels = 1 << (8 - _QUANTISE_BITS)
    keys = (
        binned[:, 0].astype(np.int64) * levels * levels
        + binned[:, 1].astype(np.int64) * levels
        + binned[:, 2].astype(np.int64)
    )
    top = int(np.bincount(keys).argmax())
    return np.median(flat[keys == top].astype(np.float64), axis=0)


def _select_piece(ink: Mask) -> Mask:
    """Keep the ink belonging to the object that covers the centre of the square.

    Connectivity is decided on a *closed* copy of the mask: a piece's internal detail
    lines pass through the background colour where they are anti-aliased against the
    fill, which cuts a one-pixel gap through the silhouette and would otherwise leave
    the matcher looking at a rook's shaft with no crenellations. The gap is bridged for
    the purpose of grouping, then the original ink is kept for the shape itself.
    """
    height, width = ink.shape
    centre = np.zeros_like(ink)
    y0, y1 = round(height * _CENTRE_INSET), round(height * (1 - _CENTRE_INSET))
    x0, x1 = round(width * _CENTRE_INSET), round(width * (1 - _CENTRE_INSET))
    centre[y0:y1, x0:x1] = True
    centre_area = max(1, int(centre.sum()))

    bridged = close(ink, max(1, round(min(height, width) * _BRIDGE_FRACTION)))
    blobs = components(
        bridged, min_area=max(4, round(height * width * _MIN_BLOB_FRACTION))
    )
    if not blobs:
        return np.zeros_like(ink)
    body = max(blobs, key=lambda blob: int((blob & centre).sum()))
    if int((body & centre).sum()) / centre_area < _MIN_CENTRE_FRACTION:
        return np.zeros_like(ink)
    return fill_holes(ink & body)


def _interior_luma(cell: RgbImage, ink: Mask) -> float:
    """Brightness of the piece body, with the dark outline stripped off.

    Eroding is what makes this piece-set independent: whether the outline is black on a
    white piece or white on a black piece, the body wins once the outline is gone.
    """
    if not ink.any():
        return float("nan")
    brightness = luma(cell)
    body = ink
    for radius in range(max(1, round(min(cell.shape[:2]) * 0.05)), 0, -1):
        eroded = erode(ink, radius)
        if eroded.sum() >= max(8, 0.2 * ink.sum()):
            body = eroded
            break
    return float(np.median(brightness[body]))
