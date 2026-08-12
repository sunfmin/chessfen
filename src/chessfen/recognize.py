"""Image in, ``chess.Board`` out."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import assert_never

import chess
import numpy as np

from .classify import SquareVerdict, classify_square
from .geometry import BoardRect, find_board
from .imaging import RgbImage, load_rgb
from .lighting import local_light
from .squares import read_square


class Orientation(StrEnum):
    """Which side is at the bottom of the picture."""

    AUTO = "auto"
    WHITE = "white"
    BLACK = "black"


class Castling(StrEnum):
    """How to fill in the castling field, which an image cannot actually show."""

    AUTO = "auto"
    """Grant rights wherever a king and rook still sit on their home squares."""
    NONE = "none"


@dataclass(frozen=True, slots=True)
class Recognition:
    """The recognised position plus the evidence behind it."""

    board: chess.Board
    rect: BoardRect
    orientation: Orientation
    verdicts: dict[chess.Square, SquareVerdict]

    @property
    def fen(self) -> str:
        return self.board.fen()

    @property
    def shaky(self) -> dict[chess.Square, SquareVerdict]:
        """Squares whose match was weak - the ones worth a human glance."""
        return {
            square: verdict
            for square, verdict in sorted(self.verdicts.items())
            if not verdict.confident
        }


def recognize(
    source: Path | RgbImage,
    *,
    turn: chess.Color = chess.WHITE,
    orientation: Orientation = Orientation.AUTO,
    castling: Castling = Castling.AUTO,
) -> Recognition:
    """Recognise the position in a board image."""
    rgb = load_rgb(source) if isinstance(source, Path) else source
    rect = find_board(rgb)
    # Every cell is read before any of them is judged, because what tells a white piece from
    # a black one is how its body compares to the light of the board around it, and that is
    # a fact about the other sixty-three squares.
    readings = [
        [read_square(rect.crop(rgb, row, col)) for col in range(8)] for row in range(8)
    ]
    light = local_light(
        np.array([[reading.background_luma for reading in line] for line in readings])
    )
    grid = [
        [
            classify_square(readings[row][col], light=float(light[row, col]))
            for col in range(8)
        ]
        for row in range(8)
    ]
    resolved = _resolve_orientation(grid, orientation)
    verdicts = {
        _square_at(row, col, resolved): grid[row][col]
        for row in range(8)
        for col in range(8)
    }
    board = _build_board(verdicts, turn=turn, castling=castling)
    return Recognition(board=board, rect=rect, orientation=resolved, verdicts=verdicts)


def _square_at(row: int, col: int, orientation: Orientation) -> chess.Square:
    """Map a grid cell (row 0 = top of the image) to a board square."""
    match orientation:
        case Orientation.WHITE:
            return chess.square(col, 7 - row)
        case Orientation.BLACK:
            return chess.square(7 - col, row)
        case Orientation.AUTO:  # pragma: no cover - resolved before this point
            raise ValueError("orientation must be resolved before mapping squares")
        case _ as unreachable:
            assert_never(unreachable)


def _resolve_orientation(
    grid: list[list[SquareVerdict]], requested: Orientation
) -> Orientation:
    """Guess which side is at the bottom from where each colour's pieces sit.

    A flip is a point reflection, so it preserves every rule of chess - no legality
    check can tell the two readings apart. What does lean one way is that armies
    advance from their own side: the colour whose pieces sit lower in the picture is
    almost always the colour playing up the board. Ties go to white at the bottom, by
    far the common case; ``--orientation`` overrides when the guess is wrong.
    """
    if requested is not Orientation.AUTO:
        return requested
    white_rows = [
        row
        for row in range(8)
        for col in range(8)
        if (piece := grid[row][col].piece) is not None and piece.color == chess.WHITE
    ]
    black_rows = [
        row
        for row in range(8)
        for col in range(8)
        if (piece := grid[row][col].piece) is not None and piece.color == chess.BLACK
    ]
    if not white_rows or not black_rows:
        return Orientation.WHITE
    white_depth = sum(white_rows) / len(white_rows)
    black_depth = sum(black_rows) / len(black_rows)
    return Orientation.WHITE if white_depth >= black_depth else Orientation.BLACK


def _build_board(
    verdicts: dict[chess.Square, SquareVerdict],
    *,
    turn: chess.Color,
    castling: Castling,
) -> chess.Board:
    board = chess.Board(None)
    for square, verdict in verdicts.items():
        if verdict.piece is not None:
            board.set_piece_at(square, verdict.piece)
    board.turn = turn
    board.set_castling_fen(_castling_fen(board, castling))
    board.halfmove_clock = 0
    board.fullmove_number = 1
    return board


def _castling_fen(board: chess.Board, castling: Castling) -> str:
    match castling:
        case Castling.NONE:
            return "-"
        case Castling.AUTO:
            rights = "".join(
                flag
                for flag, king, rook in (
                    ("K", chess.E1, chess.H1),
                    ("Q", chess.E1, chess.A1),
                    ("k", chess.E8, chess.H8),
                    ("q", chess.E8, chess.A8),
                )
                if board.piece_at(king) == chess.Piece(chess.KING, flag.isupper())
                and board.piece_at(rook) == chess.Piece(chess.ROOK, flag.isupper())
            )
            return rights or "-"
        case _ as unreachable:
            assert_never(unreachable)
