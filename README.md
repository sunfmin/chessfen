# chessfen

Read a chess position out of a board image and print its FEN — and render a FEN back
into a board image. No model, no training data, no OpenCV: the geometry of a rendered
board is exact, so plain arithmetic on pixels is enough.

> **This Python implementation is frozen.** It works, it is still tested, and it is still
> the clearest description of the algorithm — but the living version is the Swift one in
> [`ios/`](ios/), which reads photographs as well as screenshots, plays the position out
> against Stockfish and runs on a phone. New behaviour goes there; this side gets
> correctness fixes only.
> See [ADR 0005](docs/adr/0005-swift-becomes-the-only-living-implementation.md) for why
> keeping two of everything was the worse trade.

```console
$ uv run chessfen recognize board.png
r3k3/2N5/8/8/8/8/8/8 w q - 0 1

$ uv run chessfen recognize          # no path: reads the image from the clipboard,
r3k3/2N5/8/8/8/8/8/8 w q - 0 1       # and copies the FEN back onto it

$ uv run chessfen render "r3k3/2N5/8/8/8/8/8/8 w q - 0 1" -o out.png --size 600
```

## Running it with uv

[uv](https://docs.astral.sh/uv/) is the only entry point — there is nothing to `pip
install`, no virtualenv to create and no activation step. `uv run` locks, syncs and then
executes, so the environment converges to `pyproject.toml` + `uv.lock` on every single
invocation.

**Prerequisites.** uv itself, plus the Cairo library that `cairosvg` binds to:

```bash
brew install uv cairo          # macOS; on Debian/Ubuntu: apt install libcairo2
```

**Try it without cloning.** Runs the CLI straight from GitHub:

```bash
uvx --from git+https://github.com/sunfmin/chessfen chessfen recognize board.png
```

**From a clone.** No install step — the first `uv run` builds the environment for you:

```bash
git clone https://github.com/sunfmin/chessfen && cd chessfen

uv run chessfen recognize board.png            # print just the FEN
uv run chessfen recognize                      # ... or read the clipboard image
uv run chessfen recognize board.png --no-copy  # do not copy the FEN back out
uv run chessfen recognize board.png --board    # FEN plus an ASCII position
uv run chessfen recognize board.png --json     # per-square score / margin / confidence
uv run chessfen recognize board.png --turn b --orientation black --castling none
uv run chessfen render "<fen>" -o out.png --size 600 --coordinates
```

Full option list: `uv run chessfen recognize --help`, `uv run chessfen render --help`.

**Screenshot straight to FEN, and the FEN straight back out.** Leave the image argument
off and the board is taken from the clipboard; on success the FEN is put *on* the
clipboard, ready to paste into a board editor or an engine. So the whole loop is `⌘⇧⌃4`
(screenshot to clipboard), then:

```bash
uv run chessfen recognize          # prints the FEN, and copies it
```

- The copy is announced on stderr, not done silently — it replaces what you had copied.
- `--no-copy` turns it off, e.g. in a pipeline. stdout is always just the FEN (or the
  JSON), so `$(uv run chessfen recognize)` is safe to interpolate either way.
- If the clipboard cannot be written (no `xclip`/`wl-copy` on Linux), that is a warning,
  not a failure: the FEN is already on stdout and the exit status stays 0.
- Copying image *files* in Finder works as input too — the first readable one is used.
  An empty clipboard is reported as such instead of crashing.

**As a library**, in a project of your own:

```bash
uv add git+https://github.com/sunfmin/chessfen
```

```python
from pathlib import Path

import chess

from chessfen import Castling, recognize

result = recognize(Path("board.png"), turn=chess.BLACK, castling=Castling.NONE)
print(result.fen)  # r3k3/2N5/8/8/8/8/8/8 b - - 0 1
print({sq: v.score for sq, v in result.shaky.items()})  # {} when nothing is doubtful
```

`recognize()` also takes an `(h, w, 3)` uint8 numpy array instead of a path, so an image
you already have in memory never has to touch the filesystem.

**Working on it.** Same story — every tool version comes out of `uv.lock`, so your
terminal, your editor and CI cannot disagree:

```bash
uv sync                       # optional; uv run self-heals anyway
uv run pytest                 # 57 tests
uv run ruff format && uv run ruff check
uv run ty check
```

## How it works

**1. Find the board.** What makes a chessboard a chessboard is that its 64 cell
brightnesses fall into two alternating groups. That is the objective: cut a candidate
rectangle into 64 cells, measure the separation between the two parity groups divided by
the spread within them. A grid off by a few pixels blends light and dark squares
together, so the measure peaks exactly at the true grid — borders, rounded corners, drop
shadows, page padding and coordinate margins are all absorbed by it.

The search is exhaustive over a window around a coarse "what isn't page background"
crop, not a hill climb, because the objective genuinely has local optima (a grid that
swallowed a coordinate margin scores respectably and no single-pixel move improves it).
Exhaustive is affordable because a summed-area table turns each of the 64 cell means
into four lookups, so cost is independent of image resolution.

**2. Segment each square.** The square's background is its *modal* colour — a square is
the largest flat-coloured region in the cell, so the mode survives both a piece covering
more than half the square and a highlight frame drawn inside the square edge. Pixels far
enough from that colour are ink. Then:

- the piece is the ink blob covering the **centre** of the square, which is why rank/file
  labels drawn inside the board, square borders and highlight frames need no special
  case — they simply are not in the middle;
- connectivity is decided on a *closed* copy of the mask, because a piece's internal
  detail lines pass through the background colour where they are anti-aliased against
  the fill, cutting a one-pixel gap through the silhouette;
- holes are filled, so a white piece on a nearly white square (where only its outline
  registers) still yields a silhouette rather than a ring.

**3. Colour.** Erode the outline away and take the median brightness of what is left.
Whether the artwork outlines white pieces in black or black pieces in white, the body
wins — and the answer does not depend on the square underneath, so dark themes work.

**4. Type.** The 12 templates are rasterised at import from python-chess's own SVG piece
set, so no PNG assets are checked in and the templates cannot drift from the renderer in
`chessfen.render`. Silhouettes are letterboxed into a 64×64 box (aspect ratio is what
separates a pawn from a king, so it must survive normalisation) and scored by IoU,
taking the better of the shape and its mirror. The winner's score and its margin over
the runner-up are reported per square.

**5. Assemble.** Grid → `chess.Board` → FEN.

## What an image cannot tell you

The tool is explicit about this rather than quietly making it up:

| Field | Default | Override |
|---|---|---|
| Side to move | white | `--turn b` |
| Castling rights | inferred: granted where a king and rook still sit on their home squares | `--castling none` |
| En passant square | always `-` | — |
| Orientation | guessed from where each army sits; ties go to white at the bottom | `--orientation white\|black` |

Orientation deserves a note: flipping a board is a point reflection, so it preserves
every rule of chess and **no legality check can tell the two readings apart**. The guess
is that armies advance from their own side, i.e. the colour sitting lower in the picture
is the one playing up the board. It is right for essentially every real diagram and
wrong for contrived ones (white promoting on the eighth rank), so pass
`--orientation` when you know.

## Confidence, and known limits

`--json` reports per-square `score` (silhouette IoU) and `margin` (gap to the runner-up
piece type); weak squares also go to stderr in plain mode. The design goal is that the
tool is never *quietly* wrong.

Verified working: any board size from ~200 px up, arbitrary square palettes (including
dark themes and near-zero contrast between the two square colours), coordinates inside
or outside the board, flat last-move/selection highlights with or without a frame, JPEG
recompression down to quality 30, and a board pasted off-centre on a page.

Known limits:

- **Squares below ~35 px** with unfamiliar piece artwork start to confuse similar
  silhouettes. Flagged as low confidence rather than silently swapped.
- **Radial-gradient highlights** (lichess's check halo) break the flat-background
  assumption for that one square. Also flagged, not hidden.
- The image must be **mostly the board**: padding, borders and margins are fine, a
  screenshot of a whole page with sidebars is not — crop it first.
- **3D board renderings** are out of scope; this is for 2D diagrams.

## Tests

The test suite is built on the reverse direction: render a FEN, recognise it back and
demand the same string, across positions, palettes, sizes, orientations and highlights —
plus a real screenshot (`tests/data/reference_board.png`, a different piece set from the
templates) for the end-to-end case, and degraded copies of it for robustness.
