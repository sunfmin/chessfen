"""Small numpy/PIL helpers shared by the geometry and mask stages."""

from __future__ import annotations

from pathlib import Path
from typing import Final

import numpy as np
import numpy.typing as npt
from PIL import Image

RgbImage = npt.NDArray[np.uint8]
LumaImage = npt.NDArray[np.float64]
Mask = npt.NDArray[np.bool_]

#: ITU-R BT.601 luma weights, the same ones PIL uses for "L".
_LUMA_WEIGHTS: Final = np.array([0.299, 0.587, 0.114])


def from_pil(image: Image.Image) -> RgbImage:
    """A PIL image as an ``(h, w, 3)`` uint8 array, flattening any alpha onto white."""
    if image.mode in {"RGBA", "LA", "P"}:
        rgba = image.convert("RGBA")
        canvas = Image.new("RGB", rgba.size, (255, 255, 255))
        canvas.paste(rgba, mask=rgba.split()[3])
        return np.asarray(canvas, dtype=np.uint8)
    return np.asarray(image.convert("RGB"), dtype=np.uint8)


def load_rgb(path: Path) -> RgbImage:
    """Read an image file as an ``(h, w, 3)`` uint8 array."""
    with Image.open(path) as handle:
        return from_pil(handle)


def luma(rgb: RgbImage) -> LumaImage:
    """Perceived brightness in 0..255 for every pixel."""
    return np.asarray(rgb, dtype=np.float64) @ _LUMA_WEIGHTS


def mad(values: npt.NDArray[np.float64]) -> float:
    """Median absolute deviation - a spread measure that ignores outliers."""
    if values.size == 0:
        return 0.0
    return float(np.median(np.abs(values - np.median(values))))


def erode(mask: Mask, radius: int) -> Mask:
    """Binary erosion with a square structuring element, zero-padded at the border."""
    if radius <= 0:
        return mask
    padded = np.pad(mask, radius, constant_values=False)
    out = mask.copy()
    height, width = mask.shape
    for dy in range(2 * radius + 1):
        for dx in range(2 * radius + 1):
            out &= padded[dy : dy + height, dx : dx + width]
    return out


def dilate(mask: Mask, radius: int) -> Mask:
    """Binary dilation with a square structuring element."""
    if radius <= 0:
        return mask
    out = mask.copy()
    height, width = mask.shape
    padded = np.pad(mask, radius, constant_values=False)
    for dy in range(2 * radius + 1):
        for dx in range(2 * radius + 1):
            out |= padded[dy : dy + height, dx : dx + width]
    return out


def close(mask: Mask, radius: int) -> Mask:
    """Bridge hairline gaps without growing the shape."""
    return erode(dilate(mask, radius), radius)


def components(mask: Mask, min_area: int) -> list[Mask]:
    """4-connected components of ``mask`` with at least ``min_area`` pixels.

    Hand-rolled flood fill: a square is ~100x100 px, so scipy would be a dependency
    bought for nothing.
    """
    remaining = mask.copy()
    found: list[Mask] = []
    height, width = mask.shape
    while True:
        seeds = np.argwhere(remaining)
        if seeds.size == 0:
            return found
        blob = np.zeros_like(mask)
        stack = [(int(seeds[0][0]), int(seeds[0][1]))]
        while stack:
            y, x = stack.pop()
            if not remaining[y, x]:
                continue
            remaining[y, x] = False
            blob[y, x] = True
            if y > 0:
                stack.append((y - 1, x))
            if y + 1 < height:
                stack.append((y + 1, x))
            if x > 0:
                stack.append((y, x - 1))
            if x + 1 < width:
                stack.append((y, x + 1))
        if int(blob.sum()) >= min_area:
            found.append(blob)


def fill_holes(mask: Mask) -> Mask:
    """Close interior holes, so a piece drawn as a hollow outline becomes a silhouette.

    Needed whenever a piece's fill happens to match its square (white piece on a white
    square): only the outline registers as ink, and an outline ring must not be matched
    against filled templates.
    """
    filled = mask.copy()
    height, width = mask.shape
    for blob in components(~mask, min_area=1):
        ys, xs = np.nonzero(blob)
        touches_border = (
            ys.min() == 0
            or xs.min() == 0
            or ys.max() == height - 1
            or xs.max() == width - 1
        )
        if not touches_border:
            filled |= blob
    return filled


def normalize_shape(mask: Mask, size: int) -> Mask:
    """Crop to the ink, scale to fit a ``size`` box keeping aspect ratio, centre it.

    Letterboxing rather than stretching is deliberate: aspect ratio is what separates
    a pawn from a king, so it has to survive normalisation.
    """
    ys, xs = np.nonzero(mask)
    if ys.size == 0:
        return np.zeros((size, size), dtype=np.bool_)
    cropped = mask[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
    height, width = cropped.shape
    scale = size / max(height, width)
    target = (max(1, round(width * scale)), max(1, round(height * scale)))
    resized = Image.fromarray(cropped.astype(np.uint8) * 255).resize(
        target, Image.Resampling.BILINEAR
    )
    canvas = np.zeros((size, size), dtype=np.bool_)
    patch = np.asarray(resized) > 127
    top = (size - patch.shape[0]) // 2
    left = (size - patch.shape[1]) // 2
    canvas[top : top + patch.shape[0], left : left + patch.shape[1]] = patch
    return canvas


def iou(left: Mask, right: Mask) -> float:
    """Intersection over union of two equally shaped masks."""
    union = int((left | right).sum())
    if union == 0:
        return 0.0
    return int((left & right).sum()) / union
