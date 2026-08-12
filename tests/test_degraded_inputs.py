"""Screenshots in the wild are recompressed, rescaled and pasted onto pages."""

from __future__ import annotations

import chess
import numpy as np
import pytest
from PIL import Image

from chessfen import Castling, Orientation, RenderOptions, recognize
from chessfen.render import render_png

EXPECTED = "r3k3/2N5/8/8/8/8/8/8 w - - 0 1"


@pytest.fixture
def screenshot(reference_image):
    with Image.open(reference_image) as handle:
        return handle.convert("RGB")


def _rescaled(screenshot: Image.Image, tmp_path, scale: float):
    path = tmp_path / f"board-{scale}.png"
    size = (round(screenshot.width * scale), round(screenshot.height * scale))
    screenshot.resize(size, Image.Resampling.LANCZOS).save(path)
    return path


@pytest.mark.parametrize("quality", [85, 55, 30])
def test_jpeg_artefacts_are_tolerated(screenshot, tmp_path, quality):
    path = tmp_path / "board.jpg"
    screenshot.save(path, quality=quality)
    assert recognize(path, castling=Castling.NONE).fen == EXPECTED


@pytest.mark.parametrize("scale", [0.5, 0.35])
def test_small_renderings_are_tolerated(screenshot, tmp_path, scale):
    assert (
        recognize(_rescaled(screenshot, tmp_path, scale), castling=Castling.NONE).fen
        == EXPECTED
    )


def test_below_about_thirty_pixel_squares_it_says_so(screenshot, tmp_path):
    # Shape matching against another piece set needs roughly 35 px squares. Past that
    # the answer degrades, and the point of the confidence numbers is to admit it.
    result = recognize(_rescaled(screenshot, tmp_path, 0.25), castling=Castling.NONE)
    assert result.fen != EXPECTED
    assert result.shaky


def test_a_board_lit_from_one_side_is_read_at_the_dark_end_too(tmp_path):
    # The position, and the ramp, of a photograph of a book page taken under a lamp: the
    # paper reads 230 at the lit edge and 110 at the other, and the white king and rook at
    # the dark end came back black. Anything absolute cuts a board like this in half -
    # 0.45 * 255 is 115, below any fixed line drawn between white pieces and black ones.
    board = chess.Board("r4rk1/pp3ppp/8/2p2p2/4Pq2/NP1Pn2P/PBP1Q3/R5KR w - - 0 1")
    options = RenderOptions(
        size=640, colors={"square light": "#ffffff", "square dark": "#808080"}
    )
    path = render_png(board, tmp_path / "board.png", options)
    with Image.open(path) as handle:
        lit = np.asarray(handle.convert("RGB"), dtype=np.float64)
    ramp = np.linspace(1.0, 0.45, lit.shape[1])[None, :, None]
    shaded = Image.fromarray(np.rint(lit * ramp).astype(np.uint8))
    shaded.save(path)

    result = recognize(path, orientation=Orientation.WHITE, castling=Castling.NONE)
    assert result.fen == board.fen()
    assert result.shaky == {}


def test_board_pasted_off_centre_onto_a_page_is_found(screenshot, tmp_path):
    path = tmp_path / "page.png"
    page = Image.new("RGB", (1100, 950), (245, 245, 247))
    page.paste(screenshot, (60, 120))
    page.save(path)
    result = recognize(path, castling=Castling.NONE)
    assert result.fen == EXPECTED
    # The screenshot carries ~15 px of its own padding, which the search sees through.
    assert (result.rect.left, result.rect.top) == pytest.approx((75, 129), abs=4)
