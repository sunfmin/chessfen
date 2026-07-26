"""Turn one square's reading into a piece (or nothing)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Final

import chess
import numpy as np

from .imaging import iou, normalize_shape
from .squares import SquareReading
from .templates import SHAPE_SIZE, piece_shapes

#: Above this brightness the piece body is white, below it black.
_WHITE_LUMA: Final = 128.0
#: Shape agreement below this, or a margin below the next best below this, is shaky.
LOW_SCORE: Final = 0.55
LOW_MARGIN: Final = 0.04


@dataclass(frozen=True, slots=True)
class SquareVerdict:
    """What was found on a square, and how sure the matcher is."""

    piece: chess.Piece | None
    score: float
    """Silhouette IoU with the winning template, or ink coverage for an empty square."""
    margin: float
    """Gap to the runner-up template; 1.0 when the square is empty."""

    @property
    def confident(self) -> bool:
        if self.piece is None:
            return True
        return self.score >= LOW_SCORE and self.margin >= LOW_MARGIN


def classify_square(reading: SquareReading) -> SquareVerdict:
    """Match the square's ink against the piece silhouettes of its own colour."""
    if not reading.occupied:
        return SquareVerdict(piece=None, score=reading.coverage, margin=1.0)
    color = chess.WHITE if reading.interior_luma >= _WHITE_LUMA else chess.BLACK
    shape = normalize_shape(reading.ink, SHAPE_SIZE)
    scored = sorted(
        (
            (max(iou(shape, template), iou(shape, np.fliplr(template))), piece_type)
            for piece_type, template in piece_shapes(color)
        ),
        reverse=True,
    )
    (best_score, best_type), (runner_up, _) = scored[0], scored[1]
    return SquareVerdict(
        piece=chess.Piece(best_type, color),
        score=best_score,
        margin=best_score - runner_up,
    )
