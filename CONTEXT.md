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
What the engine reports about a Position: a Score, a Depth, and one or more Lines. Deepens
while it runs and its answer keeps changing, so an Analysis is always a snapshot at a
Depth, never a verdict. It belongs to a screen someone is looking at: the engine does not
take one up while the app is away (docs/adr/0009), and it runs in Stints rather than for
as long as it is left alone (docs/adr/0019). Never mutates a Game.
_Avoid_: evaluation (ambiguous with the engine's static eval), hint, suggestion

**Stint**:
Ten seconds of advice, after which the engine stops and the strip under the board offers
another. The unit an Analysis is bought in — a clock the session keeps rather than a
budget handed to the engine, so a search that belongs to a screen is still refused while
the app is away (docs/adr/0019). What ends one is the clock; what ends the *silence* after
it is a person pressing 再算 10 秒. Says nothing about the engine's own move, which is
bounded by Thinking Time, or about a Review, which is bounded by Depth.
_Avoid_: timeout, budget, session, throttle, interval

**Review**:
Re-scoring a whole Game at one uniform Depth, so that the Scores of different moves are
comparable and mistakes can be named. The engine's report on a game, never the player's
examination — being asked to find the move yourself is a Drill. Both happen on the one
board, told apart by whether the engine's opinion is switched on (docs/adr/0015). A Ply's
evaluation is a Review's field and nothing else writes it (docs/adr/0016). Distinct from Analysis, whose Depths vary with how long each
position happened to be looked at.
_Avoid_: post-mortem, curve, retrospective, drill

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

### The learning side

**Practice**:
Whether the engine keeps its opinion to itself: no Score, no arrow, no Lines, nothing
whispering a move. The default state of the app, because an answer on screen is an answer
the eye cannot decline to read (docs/adr/0015). Says nothing about whether the engine
*plays* — it can hold a Controller and still not talk. 自己练 on screen.
_Avoid_: hint off, silent mode, blindfold, difficulty, training mode

**Drill**:
One question made out of a Game the app already holds: the position comes back with the
engine silent, and a move — with an Intent, when one is asked for — has to be committed
before anything is revealed. The player's examination, as against a Review, which is the
engine's report. Neither a screen of its own nor a mode: it is what the one board is when
the engine's opinion is off and the Ply being looked at is a past one (docs/adr/0015).
考一遍 on screen.
_Avoid_: puzzle, quiz, test, exercise, training — and not Review

**Guess**:
A move offered at a past Ply and not yet committed — on the board, visible, and still yours to
take back. The middle of a Drill: a move already played is an answer already marked, and there
has to be a moment between the two or the honest first attempt never gets made. Kept nowhere;
a Guess that turns out to be worth having is kept as a Variation instead.
_Avoid_: attempt, try, answer, candidate, move

**Reveal**:
What committing a Guess shows: your move, the engine's, and the one actually played, each with
a Score, all three at one Depth. Three facts side by side and never a combined number — finding
the engine's move, finding a move as good as it, and finding what you played last time are
different pieces of news.
_Avoid_: result, score, grade, feedback, verdict

**Control Change**:
What one move did to the map of who holds which squares, split by which way each square went
for the side that played it: the squares it took a grip on and the squares it let go of. Two
sets and not one — a move's gains and its costs are opposite facts. Not what the board draws:
it is the **candidate pool** a 要害格 is chosen out of, because ten squares in two colours is
a diff and a player cannot act on a diff (docs/adr/0020). Only ever computed for a past
position, and always about that position's last Ply, which is the Guess when there is one.
_Avoid_: influence, coverage, heat map, territory, diff

**要害格**:
A square the board judged worth drawing: one a rules net proposed — beside the mover's own
king, a hole no pawn of theirs can attack again, a square an enemy piece can reach and hold,
a square one of their own pieces wants and cannot safely take — and the engine's Line then
confirmed mattered. At most three per move and usually one, each with a sentence saying what
it costs or buys. Ranked within the position, never against a threshold, for the same reason
Criticality is (docs/adr/0017). Distinct from a Control Change, which is every square that
changed hands and makes no claim about any of them. 这步的要害 on screen.
_Avoid_: key square, weak square, hotspot, important square, highlight

**走马灯**:
Playing a Line out on the main board a Ply at a time, with the 要害格 layer following each
step and one cumulative sentence saying where the whole line arrived. Ephemeral by
definition: no Variation is made, nothing reaches the PGN, and leaving it restores the
position exactly — a Line is a hypothesis and nothing was played. The concrete form of
"seeing five moves ahead", as against being told that one should.
_Avoid_: playback, animation, preview, autoplay, simulation

**五步计划**:
A Variation of the player's own, at most five Ply, carrying one Intent judged over the whole
line instead of over its first move. The unbuilt consequence of docs/adr/0017, finally built.
The cap is about what can be checked rather than about how far people see: past about five
Ply the opponent has had enough replies that no claim about the position is falsifiable, and
an Intent that cannot be told false is not one (docs/adr/0018).
_Avoid_: plan, strategy, sequence, combination, opening prep

**Intent**:
What the player says a move was *for*: one verb and one target Square, declared by whoever
played the Ply. That shape is the whole point — a verb with a target can be drawn on the
board as an arrow and a ring, and can be told false by the rules code, which freeform words
can be neither. A verb that cannot be wrong does not get one of the eight slots. 为什么
on screen.
_Avoid_: annotation, comment, note, reason, plan, purpose

**说不清**:
The Intent that declares no claim — the player had no reason for the move. Recorded, never
skipped: a Game with twenty-five of them is itself the whole diagnosis, and it is one no
engine could have produced.
_Avoid_: unknown, none, skip, unsure

**Criticality**:
How much a Ply mattered, as a **rank within its own Game** rather than a number of
centipawns. What a Drill asks about is that Game's worst few moves, whatever their absolute
size, which is how one mechanism serves a beginner and a club player without the app ever
being told which it is talking to (docs/adr/0017). Distinct from MoveQuality, which is the
absolute label — 漏着, 失误, 不精确 — and only ever names a move, never chooses it.
_Avoid_: importance, severity, weight, difficulty

**Failure Mode**:
The kind of error a player repeats, counted over their Games from Intents and Reviews —
giving a piece away, missing the opponent's reply, declaring an Intent that was not true,
having no reason at all, or only ever attacking while being attacked. Derived on demand and
never stored (docs/adr/0018). The app's one statement about how somebody is doing; there is
deliberately no rating and no accuracy percentage. 老毛病 on screen.
_Avoid_: weakness, skill gap, rating, accuracy, score

**Occurrence**:
One time a Failure Mode happened: the Game's file, the Ply, and one sentence about what the
board said. The unit a count is made of, and the way back — a Failure Mode that could not
name the moves it was counted from would be a grade with extra steps.
_Avoid_: instance, hit, event, record, entry
