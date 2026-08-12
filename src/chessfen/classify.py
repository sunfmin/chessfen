"""Turn one square's reading into a piece (or nothing)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Final

import chess
import numpy as np

from .imaging import iou, normalize_shape
from .squares import SquareReading
from .templates import SHAPE_SIZE, piece_shapes

#: A body at least this fraction of its local light is a white piece. Measured over
#: photographs and screenshots alike, white bodies come out from about 0.6 of their local
#: light upwards and black bodies below about 0.36 - the two are far apart, and half way is
#: the emptiest place between them.
_WHITE_FRACTION: Final = 0.5
#: Shape agreement below this, or a margin below the next best below this, is shaky.
LOW_SCORE: Final = 0.55
LOW_MARGIN: Final = 0.04
#: A body this near the white/black line was a coin toss, and the square is shaky however
#: well its shape matched. A red check halo under a white king lands here, and so does a
#: piece read off a screen through a moiré.
LOW_COLOR_MARGIN: Final = 0.1


@dataclass(frozen=True, slots=True)
class SquareVerdict:
    """What was found on a square, and how sure the matcher is."""

    piece: chess.Piece | None
    score: float
    """Silhouette IoU with the winning template, or ink coverage for an empty square."""
    margin: float
    """Gap to the runner-up template; 1.0 when the square is empty."""
    color_margin: float
    """How far the body sat from the line between white and black, as a fraction of the
    local light; 1.0 when the square is empty."""

    @property
    def confident(self) -> bool:
        if self.piece is None:
            return True
        return (
            self.score >= LOW_SCORE
            and self.margin >= LOW_MARGIN
            and self.color_margin >= LOW_COLOR_MARGIN
        )


def classify_square(reading: SquareReading, light: float) -> SquareVerdict:
    """Match the square's ink against the piece silhouettes of its own colour.

    ``light`` is the local light beside this cell - the brightness the body is judged
    against, since brightness on its own is a fact about the photograph and not about the
    piece.
    """
    if not reading.occupied:
        return SquareVerdict(
            piece=None, score=reading.coverage, margin=1.0, color_margin=1.0
        )
    brightness = reading.interior_luma / max(1.0, light)
    color = chess.WHITE if brightness >= _WHITE_FRACTION else chess.BLACK
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
        color_margin=abs(brightness - _WHITE_FRACTION),
    )
