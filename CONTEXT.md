# chessfen

Reading a chess position out of a picture of a board, and — on iOS — playing the game
on from there with an engine's advice. Two implementations of one domain: a Python CLI
and an iOS app.

## Language

### The picture side

**Board Rect**:
The axis-aligned pixel square that the 8x8 grid occupies inside an image. Rows count
from the top of the picture, columns from the left.
_Avoid_: bounding box, crop, ROI

**Cell**:
One of the 64 pixel boxes of a Board Rect. A Cell is a region of an image; it becomes a
Square only once an Orientation is known.
_Avoid_: tile, block

**Ink**:
The pixels of a Cell that are far enough from that Cell's background colour to be part
of the drawn piece. A mask, not a colour.
_Avoid_: foreground, mask, blob

**Silhouette**:
Ink, hole-filled, cropped to its extent and letterboxed into a fixed square box. The
shape a Template is compared against.
_Avoid_: outline, glyph, shape

**Template**:
The Silhouette of one of the twelve pieces, rasterised from the canonical piece paths.
The thing a Silhouette is scored against.
_Avoid_: reference, sample,训练数据

**Piece Paths**:
The canonical vector artwork for the twelve pieces, as SVG path data. One table serves
both Templates and on-screen board drawing, so the two cannot disagree.
_Avoid_: assets, sprites, icons

**Score / Margin**:
Score is a Silhouette's agreement (IoU) with its winning Template. Margin is the gap to
the runner-up piece type. Both are per-Square.
_Avoid_: confidence (reserved for the derived boolean), probability, accuracy

**Shaky Square**:
A Square whose Score or Margin is below the accept threshold — the ones a human should
glance at. The recogniser is allowed to be wrong, never *quietly* wrong.
_Avoid_: uncertain, failed, error

**Orientation**:
Which colour sits at the bottom of the picture. Unknowable from the pixels in the
general case: flipping a board is a point reflection, so it preserves every rule of
chess.
_Avoid_: rotation, flip, perspective

**Recognition**:
The act of turning one image into a Position, plus the per-Square evidence behind it.
_Avoid_: detection, scan, OCR

### The chess side

**Position**:
Where every piece stands, plus side to move, castling rights, en passant square and the
two clocks. Exactly what a FEN encodes. Has no memory of how it was reached.
_Avoid_: board, state, snapshot

**Game**:
A starting Position plus the ordered moves played from it. The only mutable truth in the
app; a Position is derived from it. Repetition and the fifty-move rule are properties of
a Game, not of a Position.
_Avoid_: session, match, history

**Unknowable Field**:
A FEN field that no image can show: side to move, castling rights, en passant square,
and the clocks. Filled by declared default or by the user, never guessed silently.
_Avoid_: missing field, default, metadata

**Analysis**:
What the engine reports about a Position: a Score, a Depth, and one or more Lines. Runs
unbounded — it deepens for as long as it is left alone and its answer keeps changing, so
an Analysis is always a snapshot at a Depth, never a verdict. Never mutates a Game.
_Avoid_: evaluation (ambiguous with the engine's static eval), hint, suggestion

**Review**:
Re-scoring a whole finished Game at one uniform Depth, so that the Scores of different
moves are comparable and mistakes can be named. Distinct from Analysis, whose Depths
vary with how long each position happened to be looked at.
_Avoid_: post-mortem, curve, retrospective

**Line**:
One principal variation — a sequence of moves the engine expects, with the Score it
leads to. `MultiPV` yields several per Analysis.
_Avoid_: PV, variation, branch

**Best Move**:
The first move of the highest-ranked Line of a completed Analysis.
_Avoid_: suggestion, hint, recommendation

**Controller**:
Who moves for one colour — the player by hand, or the engine. Each colour has its own,
either can be changed at any point in a Game, and all four combinations are meaningful:
play a side, hand-move both to replay a book game, swap sides, or let the engine play
itself.
_Avoid_: opponent, mode, player type, difficulty

**Mirrored Time**:
How long the engine thinks before moving a colour it controls: about as long as the
player took over their own last move. The engine is never handicapped — it plays at full
strength, and the only thing that shapes how well it plays is how long it is left alone.
_Avoid_: difficulty, level, skill, strength, Elo, time control

**Rules Query**:
A question about chess legality — the legal moves in a Game, whether it is over and how.
Answered by Stockfish's position code, not reimplemented.
_Avoid_: validation, move generation
