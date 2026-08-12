# Perspective correction is a pre-stage the checker score judges

The recogniser assumes an axis-aligned board, which rules out photographs. Rather than
generalising the pipeline to arbitrary quadrilaterals, a pre-stage rectifies the image
and hands the existing pipeline exactly what it already expects.

Two rules keep it honest:

1. **Axis-aligned first.** The existing exhaustive search runs on the original pixels; if
   its checker score clears the threshold — every screenshot will — the image is used as
   is. Warping resamples, and a pixel-perfect screenshot has nothing to gain and sharpness
   to lose.
2. **The checker score picks the winner.** Vision's `DetectRectanglesRequest` /
   `DetectDocumentSegmentationRequest` propose candidate quads; each is rectified with
   `CIPerspectiveCorrection`, run through the exhaustive search, and scored. The board is
   whichever candidate scores highest, so a detector that returned the page, the screen
   bezel or the phone in the photo is voted down rather than believed. A coordinate
   descent on the four corners then pushes the winner's score to its local maximum.

## Consequences

- Vision is a *proposal* mechanism, never an authority; the accept/reject gate stays the
  same measure the original algorithm used, which is what makes the extension safe.
- Photographs of physical boards remain out of scope: rectification fixes perspective,
  not three-dimensional pieces, their shadows, or the fact that a 3D knight's outline is
  not the 2D Template's.
- On-device only — Vision ships with the OS, so "fully local" survives.
- Cost is bounded: the exhaustive search runs once per candidate quad, and candidates are
  few.
