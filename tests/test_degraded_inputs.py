"""Screenshots in the wild are recompressed, rescaled and pasted onto pages."""

from __future__ import annotations

import pytest
from PIL import Image

from chessfen import Castling, recognize

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


def test_board_pasted_off_centre_onto_a_page_is_found(screenshot, tmp_path):
    path = tmp_path / "page.png"
    page = Image.new("RGB", (1100, 950), (245, 245, 247))
    page.paste(screenshot, (60, 120))
    page.save(path)
    result = recognize(path, castling=Castling.NONE)
    assert result.fen == EXPECTED
    # The screenshot carries ~15 px of its own padding, which the search sees through.
    assert (result.rect.left, result.rect.top) == pytest.approx((75, 129), abs=4)
