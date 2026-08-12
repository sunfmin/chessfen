"""How bright the board's own light squares are, cell by cell.

A piece body's brightness says nothing on its own. Photograph a printed diagram and the
paper runs from 230 at the lit edge of the page down to 110 in the shade at the other end,
all in one picture - so a white rook standing in the shade comes out darker than a black
rook standing in the light, and no fixed brightness can be the line between the two
colours. Measured against the light squares *beside* it, though, a white body sits around
three quarters of its local light and a black one around a third, wherever on the board it
stands and whatever the camera did.

Light squares rather than dark ones because light is the end that carries the answer: a
board's dark squares are only a little darker than its light ones, while black pieces are
darker than everything.
"""

from __future__ import annotations

from typing import Final

import numpy as np
import numpy.typing as npt

#: How many cells away still counts as beside. Two rings in from a corner is nine light
#: squares to take a median of - enough that a piece with an unusually flat square, or a
#: highlight frame, cannot move the answer - and close enough that a gradient across the
#: board is followed rather than averaged away.
_NEIGHBOURHOOD: Final = 2


def local_light(backgrounds: npt.NDArray[np.float64]) -> npt.NDArray[np.float64]:
    """The light-square level beside each of the 64 cells, in the image's own row order."""
    if backgrounds.shape != (8, 8):
        raise ValueError(f"expected an 8x8 grid of square backgrounds, got {backgrounds.shape}")

    rows, columns = np.indices((8, 8))
    even = (rows + columns) % 2 == 0
    # Which of the two colourings is the light one is a question about this board, not about
    # chess: nothing says a1 is dark in a photograph that may be seen from either side, or
    # in a diagram drawn either way round.
    light = even if np.median(backgrounds[even]) >= np.median(backgrounds[~even]) else ~even
    overall = float(np.median(backgrounds[light]))

    out = np.full((8, 8), overall)
    for row in range(8):
        for column in range(8):
            top, bottom = max(0, row - _NEIGHBOURHOOD), min(8, row + _NEIGHBOURHOOD + 1)
            left, right = max(0, column - _NEIGHBOURHOOD), min(8, column + _NEIGHBOURHOOD + 1)
            nearby = backgrounds[top:bottom, left:right][light[top:bottom, left:right]]
            if nearby.size:
                out[row, column] = float(np.median(nearby))
    return out
