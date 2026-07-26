"""Take the board image from the clipboard, for the screenshot-and-paste workflow."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageGrab, UnidentifiedImageError

from .imaging import RgbImage, from_pil, load_rgb


class ClipboardImageError(ValueError):
    """Raised when the clipboard holds no image this tool can read."""


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


def _first_readable(paths: list[str]) -> RgbImage:
    """Load the first clipboard entry that is actually an image file."""
    for name in paths:
        try:
            return load_rgb(Path(name))
        except (OSError, UnidentifiedImageError):
            continue
    listed = ", ".join(paths) if paths else "nothing"
    raise ClipboardImageError(f"no readable image on the clipboard (found: {listed})")
