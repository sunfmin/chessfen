"""Render a FEN, recognise it back, demand the same string.

This covers the whole pipeline - board location, square segmentation, piece colour and
shape matching, FEN assembly - against boards that vary in size, palette, coordinates
and orientation.
"""

from __future__ import annotations

import chess
import pytest
from conftest import playout

from chessfen import (
    Castling,
    Highlight,
    HighlightStyle,
    Orientation,
    RenderOptions,
    recognize,
)
from chessfen.render import render_png

POSITIONS = {
    "start": chess.Board(),
    "empty": chess.Board(None),
    "opening": playout(seed=1, plies=8),
    "middlegame": playout(seed=2, plies=30),
    "endgame": playout(seed=3, plies=70),
    "lone-kings": chess.Board("4k3/8/8/8/8/8/8/4K3 w - - 0 1"),
    "all-piece-types": chess.Board(
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    ),
    "promotion-mess": chess.Board("QQQQQQQQ/8/8/4k3/3K4/8/8/qqqqqqqq w - - 0 1"),
}

PALETTES = {
    "default": {},
    "lichess-blue": {"square light": "#dee3e6", "square dark": "#8ca2ad"},
    "green": {"square light": "#eeeed2", "square dark": "#769656"},
    "low-contrast-grey": {"square light": "#ffffff", "square dark": "#dcdcdc"},
    "dark-theme": {"square light": "#6d6d6d", "square dark": "#3d3d3d"},
}


def read_back(
    board: chess.Board,
    tmp_path,
    options: RenderOptions,
    *,
    orientation: Orientation = Orientation.AUTO,
) -> str:
    path = render_png(board, tmp_path / "board.png", options)
    return recognize(
        path, turn=board.turn, orientation=orientation, castling=Castling.NONE
    ).fen


def expected(board: chess.Board) -> str:
    without_castling = board.copy()
    without_castling.set_castling_fen("-")
    without_castling.halfmove_clock = 0
    without_castling.fullmove_number = 1
    return without_castling.fen()


@pytest.mark.parametrize("name", sorted(POSITIONS))
def test_positions_round_trip(name, tmp_path):
    # Orientation is pinned: "promotion-mess" has white on the eighth rank, which is
    # exactly the case no image can resolve. Auto-detection is tested on its own below.
    board = POSITIONS[name]
    assert read_back(
        board, tmp_path, RenderOptions(), orientation=Orientation.WHITE
    ) == expected(board)


@pytest.mark.parametrize("palette", sorted(PALETTES))
def test_palettes_round_trip(palette, tmp_path):
    board = POSITIONS["middlegame"]
    options = RenderOptions(colors=PALETTES[palette])
    assert read_back(board, tmp_path, options) == expected(board)


@pytest.mark.parametrize("size", [200, 320, 480, 800])
def test_sizes_round_trip(size, tmp_path):
    board = POSITIONS["opening"]
    assert read_back(board, tmp_path, RenderOptions(size=size)) == expected(board)


def test_coordinate_margin_is_cropped_away(tmp_path):
    board = POSITIONS["middlegame"]
    options = RenderOptions(size=600, coordinates=True)
    assert read_back(board, tmp_path, options) == expected(board)


def test_flat_highlight_does_not_confuse_the_piece(tmp_path):
    # The common case: a last-move or selection tint, flat fill, as on lichess and
    # chess.com. The reference screenshot adds a frame on top of one, and works too.
    board = chess.Board("4k3/8/8/8/8/8/4r3/4K3 w - - 0 1")
    options = RenderOptions(highlight=Highlight("e1"))
    assert read_back(board, tmp_path, options) == expected(board)


def test_gradient_highlight_is_reported_as_shaky_rather_than_guessed(tmp_path):
    # A radial check halo breaks the flat-background assumption. Being wrong here is a
    # known limitation; being wrong *quietly* would not be acceptable.
    board = chess.Board("4k3/8/8/8/8/8/4r3/4K3 w - - 0 1")
    options = RenderOptions(highlight=Highlight("e1", HighlightStyle.GRADIENT))
    path = render_png(board, tmp_path / "board.png", options)
    result = recognize(path, orientation=Orientation.WHITE, castling=Castling.NONE)
    assert chess.E1 in result.shaky


def test_flipped_board_needs_the_orientation_flag(tmp_path):
    board = POSITIONS["opening"]
    options = RenderOptions(flipped=True)
    assert read_back(
        board, tmp_path, options, orientation=Orientation.BLACK
    ) == expected(board)


def test_flipped_board_is_detected_from_where_the_armies_sit(tmp_path):
    # A flip is a point reflection, so only the layout of the two armies can betray it.
    board = POSITIONS["start"]
    options = RenderOptions(flipped=True)
    assert read_back(board, tmp_path, options) == expected(board)
