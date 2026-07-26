"""FEN in, board image out.

This is the inverse of :mod:`chessfen.recognize` and doubles as the test rig: render a
FEN, recognise it back, demand the same string.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from pathlib import Path
from typing import Final, assert_never

import cairosvg
import chess
import chess.svg

#: python-chess reserves a coordinate margin; the board itself is 8 * SQUARE_SIZE.
_BOARD_UNITS: Final = 8 * chess.svg.SQUARE_SIZE


class HighlightStyle(StrEnum):
    """How a marked square is painted."""

    FLAT = "flat"
    """A solid tint, as used for the last move or a selected square."""
    GRADIENT = "gradient"
    """A radial halo, as used for a king in check."""


@dataclass(frozen=True, slots=True)
class Highlight:
    """A marked square, by name (``"c7"``)."""

    square: str
    style: HighlightStyle = HighlightStyle.FLAT


@dataclass(frozen=True, slots=True)
class RenderOptions:
    """Knobs that let tests cover boards that do not look like the default one."""

    size: int = 480
    coordinates: bool = False
    flipped: bool = False
    colors: dict[str, str] = field(default_factory=dict)
    highlight: Highlight | None = None


#: Shared default, so the frozen options object is not rebuilt per call.
DEFAULT_OPTIONS: Final = RenderOptions()


def render_svg(board: chess.Board, options: RenderOptions = DEFAULT_OPTIONS) -> str:
    """SVG for a position, sized so that the board occupies the whole viewport."""
    check: chess.Square | None = None
    lastmove: chess.Move | None = None
    if options.highlight is not None:
        square = chess.parse_square(options.highlight.square)
        match options.highlight.style:
            case HighlightStyle.GRADIENT:
                check = square
            case HighlightStyle.FLAT:
                lastmove = chess.Move(square, square)
            case _ as unreachable:
                assert_never(unreachable)
    margin = chess.svg.MARGIN if options.coordinates else 0
    scale = options.size / (_BOARD_UNITS + 2 * margin)
    return chess.svg.board(
        board,
        size=round((_BOARD_UNITS + 2 * margin) * scale),
        coordinates=options.coordinates,
        flipped=options.flipped,
        colors=options.colors,
        check=check,
        lastmove=lastmove,
    )


def render_png(
    board: chess.Board, path: Path, options: RenderOptions = DEFAULT_OPTIONS
) -> Path:
    """Write a PNG of the position and return its path."""
    cairosvg.svg2png(
        bytestring=render_svg(board, options).encode(),
        write_to=str(path),
        output_width=options.size,
        output_height=options.size,
    )
    return path


def render_png_bytes(
    board: chess.Board, options: RenderOptions = DEFAULT_OPTIONS
) -> bytes:
    """PNG bytes of the position, for callers that never touch the filesystem."""
    png: bytes = cairosvg.svg2png(
        bytestring=render_svg(board, options).encode(),
        output_width=options.size,
        output_height=options.size,
    )
    return png
