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

**Local Light**:
How bright the board's own light squares are beside one Cell. A piece body's brightness
says nothing on its own — the paper in a photograph runs from bright at the lit edge of
the page to dim at the other — so white is told from black by the ratio to this, never by
a fixed brightness.
_Avoid_: exposure, white balance, threshold, brightness

**Score / Margin**:
Score is a Silhouette's agreement (IoU) with its winning Template. Margin is the gap to
the runner-up piece type. Colour Margin is how far the body sat from the line between
white and black, as a fraction of the Local Light. All three are per-Square.
_Avoid_: confidence (reserved for the derived boolean), probability, accuracy

**Shaky Square**:
A Square whose Score, Margin or Colour Margin is below the accept threshold — the ones a
human should glance at. The recogniser is allowed to be wrong, never *quietly* wrong, and
that covers reading a piece as the wrong colour as much as reading it as the wrong shape.
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

**Piece Editor**:
Where a Position that came out of a Recognition wrong is put right — which piece stands
on which Square, plus the two Unknowable Fields nothing else shows (castling rights and
the en passant square). Only reachable while the Game has no moves, since replacing a
starting Position under played moves would invalidate them. 改棋子 on screen.
_Avoid_: confirm screen, gate, setup, board editor

**Ply**:
One move by one colour, as written into a Game: what was played, what it is called, and
what a Review made of it. A Game is an ordered list of these. Distinct from a move, which
is something the rules merely allow.
_Avoid_: move, turn, half-move, step

**Analysis**:
What the engine reports about a Position: a Score, a Depth, and one or more Lines. Runs
unbounded — it deepens for as long as it is left alone and its answer keeps changing, so
an Analysis is always a snapshot at a Depth, never a verdict. Left alone means in front of
the player: an Analysis belongs to a screen someone is looking at, and the engine does not
take one up while the app is away (docs/adr/0009). Never mutates a Game.
_Avoid_: evaluation (ambiguous with the engine's static eval), hint, suggestion

**Review**:
Re-scoring a whole finished Game at one uniform Depth, so that the Scores of different
moves are comparable and mistakes can be named. Distinct from Analysis, whose Depths
vary with how long each position happened to be looked at.
_Avoid_: post-mortem, curve, retrospective

**Line**:
A sequence of moves the engine expects, with the Score it leads to. `MultiPV` yields
several per Analysis. A Line is a hypothesis and nothing was played.
_Avoid_: PV, branch — and not Variation, which is the Game's word for moves that were
actually played

**Variation**:
A line that was played from some Ply and then left behind, kept hanging off that Ply
rather than discarded. Playing a different move from a rewound Game makes one; stepping
back into it makes the line it replaces a Variation in its turn. This is exactly what
PGN's brackets hold, which is why nothing is lost by taking a move back.
_Avoid_: branch, alternative, undo history, side line

**Best Move**:
The first move of the highest-ranked Line of a completed Analysis.
_Avoid_: suggestion, hint, recommendation

**Controller**:
Who moves for one colour — the player by hand, or the engine. Each colour has its own,
either can be changed at any point in a Game, and all four combinations are meaningful:
play a side, hand-move both to replay a book game, swap sides, or let the engine play
itself.
_Avoid_: opponent, mode, player type, difficulty

**Asked Move**:
One move played by the engine because somebody asked for it, for whichever colour is on
the clock — not a Controller, which stands until it is changed, and not advice left on
screen. It is asked for by holding a button, and the time it is held is the time the
engine gets: the same bargain as Mirrored Time, with a thumb in place of the clock. 让引擎走
on screen.
_Avoid_: hint, auto-move, assist, take over

**Thinking Time**:
How long the engine gets over a move it plays for a colour it controls. Mirrored Time, or
a named number of seconds every move. It is the only dial in the app — the engine is never
handicapped, so how long it is left alone is the whole of how well it plays — and it is
offered whenever the engine holds a Controller. Says nothing about the other two things
the engine does: advice is unbounded, and an Asked Move takes as long as the button is held.
_Avoid_: difficulty, level, skill, strength, Elo, time control, move time limit

**Mirrored Time**:
The Thinking Time that follows the player: about as long as they took over their own last
move, which is the courtesy a human opponent extends. The default against a person, and no
answer at all when the engine holds both Controllers — there is no last human move to
mirror, so a game the app plays against itself names a clock instead (three seconds a move).
_Avoid_: difficulty, level, skill, strength, Elo, time control

**Rules Query**:
A question about chess legality — the legal moves in a Game, whether it is over and how.
Answered by Stockfish's position code, not reimplemented.
_Avoid_: validation, move generation
