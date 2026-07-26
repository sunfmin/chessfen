"""Recognise a chess position from a board image, and render one back."""

from __future__ import annotations

from importlib.metadata import version

from .clipboard import ClipboardImageError, clipboard_image
from .geometry import BoardNotFoundError, BoardRect, find_board
from .recognize import Castling, Orientation, Recognition, recognize
from .render import (
    Highlight,
    HighlightStyle,
    RenderOptions,
    render_png,
    render_png_bytes,
    render_svg,
)

__version__ = version("chessfen")

__all__ = [
    "BoardNotFoundError",
    "BoardRect",
    "Castling",
    "ClipboardImageError",
    "Highlight",
    "HighlightStyle",
    "Orientation",
    "Recognition",
    "RenderOptions",
    "__version__",
    "clipboard_image",
    "find_board",
    "recognize",
    "render_png",
    "render_png_bytes",
    "render_svg",
]
