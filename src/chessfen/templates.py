"""Piece silhouettes, derived at runtime from python-chess's own SVG piece set.

No PNG assets are checked in: the shapes have exactly one home (``chess.svg.PIECES``)
and are rasterised on first use, so they cannot drift from the renderer in
:mod:`chessfen.render`.
"""

from __future__ import annotations

import io
from functools import cache
from typing import Final

import cairosvg
import chess
import chess.svg
import numpy as np
from PIL import Image

from .imaging import Mask, normalize_shape

#: Side of the normalised shape space, in pixels.
SHAPE_SIZE: Final = 64
#: Alpha above which a rasterised pixel counts as part of the silhouette.
_ALPHA_TOLERANCE: Final = 96
#: Rasterisation size; larger than SHAPE_SIZE so downscaling stays smooth.
_RASTER_SIZE: Final = 256

PIECE_TYPES: Final = (
    chess.PAWN,
    chess.KNIGHT,
    chess.BISHOP,
    chess.ROOK,
    chess.QUEEN,
    chess.KING,
)


@cache
def piece_shapes(color: chess.Color) -> tuple[tuple[int, Mask], ...]:
    """Normalised silhouettes for one side, as ``(piece_type, mask)`` pairs."""
    return tuple(
        (piece_type, _silhouette(chess.Piece(piece_type, color)))
        for piece_type in PIECE_TYPES
    )


def _silhouette(piece: chess.Piece) -> Mask:
    svg = chess.svg.piece(piece)
    png: bytes = cairosvg.svg2png(
        bytestring=svg.encode(),
        output_width=_RASTER_SIZE,
        output_height=_RASTER_SIZE,
    )
    with Image.open(io.BytesIO(png)) as handle:
        alpha = np.asarray(handle.convert("RGBA"))[:, :, 3]
    return normalize_shape(alpha > _ALPHA_TOLERANCE, SHAPE_SIZE)
