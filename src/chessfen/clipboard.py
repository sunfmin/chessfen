"""The clipboard, both ways: an image in, the resulting FEN back out.

Reading goes through PIL, which already owns the platform quirks. Writing shells out to
the platform's clipboard tool - a table of ~six commands, which is cheaper than taking a
dependency for it and lets the error message name what is actually missing.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from typing import Final

from PIL import Image, ImageGrab, UnidentifiedImageError

from .imaging import RgbImage, from_pil, load_rgb

#: Clipboard writers per ``sys.platform``, tried in order until one is installed.
_COPY_COMMANDS: Final = {
    "darwin": (("pbcopy",),),
    "win32": (("clip",),),
    "linux": (
        ("wl-copy",),
        ("xclip", "-selection", "clipboard"),
        ("xsel", "--clipboard", "--input"),
    ),
}


class ClipboardError(ValueError):
    """Base for anything that goes wrong talking to the clipboard."""


class ClipboardImageError(ClipboardError):
    """Raised when the clipboard holds no image this tool can read."""


class ClipboardWriteError(ClipboardError):
    """Raised when text cannot be put on the clipboard."""


def clipboard_image() -> RgbImage:
    """The clipboard's image as an RGB array.

    Clipboards hand back one of three things: an image (a screenshot, or a copy from a
    browser), a list of file paths (a copy from a file manager), or nothing at all.
    """
    try:
        grabbed = ImageGrab.grabclipboard()
    except OSError as error:  # no clipboard tool available, typically on Linux
        raise ClipboardImageError(
            f"cannot read the clipboard on this system ({error}); pass an image path"
        ) from error
    if grabbed is None:
        raise ClipboardImageError(
            "the clipboard holds no image - copy a board screenshot, or pass a path"
        )
    if isinstance(grabbed, Image.Image):
        return from_pil(grabbed)
    return _first_readable(grabbed)


def copy_text(text: str) -> None:
    """Put ``text`` on the clipboard, ready to paste."""
    candidates = _COPY_COMMANDS.get(sys.platform, ())
    for command in candidates:
        try:
            subprocess.run(command, input=text.encode(), check=True)
        except FileNotFoundError:
            continue  # tool not installed; try the next one
        except (OSError, subprocess.CalledProcessError) as error:
            raise ClipboardWriteError(f"{command[0]} failed: {error}") from error
        return
    wanted = " or ".join(command[0] for command in candidates) or "a clipboard tool"
    raise ClipboardWriteError(f"cannot write to the clipboard: install {wanted}")


def _first_readable(paths: list[str]) -> RgbImage:
    """Load the first clipboard entry that is actually an image file."""
    for name in paths:
        try:
            return load_rgb(Path(name))
        except (OSError, UnidentifiedImageError):
            continue
    listed = ", ".join(paths) if paths else "nothing"
    raise ClipboardImageError(f"no readable image on the clipboard (found: {listed})")
