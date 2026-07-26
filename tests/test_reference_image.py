"""The end-to-end case that matters: a real screenshot, not something we rendered.

Different piece artwork, coordinate labels drawn *inside* the board, a highlighted
square with a frame around it, and a rounded, padded board edge.
"""

from __future__ import annotations

import chess
import numpy as np
import pytest

from chessfen import BoardNotFoundError, Castling, recognize
from chessfen.imaging import load_rgb

EXPECTED_PLACEMENT = "r3k3/2N5/8/8/8/8/8/8"


def test_reference_screenshot_gives_the_right_fen(reference_image):
    result = recognize(reference_image, turn=chess.BLACK, castling=Castling.NONE)
    assert result.fen == f"{EXPECTED_PLACEMENT} b - - 0 1"


def test_castling_rights_are_inferred_from_home_squares(reference_image):
    # The black king and the a8 rook are untouched, so queenside stays available.
    result = recognize(reference_image, castling=Castling.AUTO)
    assert result.fen == f"{EXPECTED_PLACEMENT} w q - 0 1"


def test_every_square_of_the_reference_is_matched_confidently(reference_image):
    result = recognize(reference_image)
    assert result.shaky == {}


def test_board_is_found_despite_the_padding(reference_image):
    result = recognize(reference_image)
    cell = result.rect.size / 8
    assert 90 < cell < 105  # ~98 px squares in this screenshot


def test_a_picture_with_no_board_is_rejected():
    noise = np.full((300, 300, 3), 200, dtype=np.uint8)
    noise[100:200, 100:200] = 40
    with pytest.raises(BoardNotFoundError):
        recognize(noise)


def test_pixels_and_paths_are_interchangeable(reference_image):
    assert recognize(load_rgb(reference_image)).fen == recognize(reference_image).fen
