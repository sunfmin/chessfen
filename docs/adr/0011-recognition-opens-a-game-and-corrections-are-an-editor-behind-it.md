# Recognition opens a Game, and corrections are an editor behind it

Recognition now goes straight to the Game. The recognised Position opens as a playable
board, and the screen that ADR-0008 made mandatory has become the Piece Editor — one tap
away from the Game, entered only when something in the picture came out wrong. Revises
ADR-0008, whose reasoning about *what can go wrong* stands entirely; what changed is
where in the flow the screen sits.

Three things moved since 0008 was written, and together they take the gate's job away
from it:

- **The Game screen already resolves the knowable unknowables.** 视角 flips the
  Orientation, 先走 sets the side to move, and each colour's Controller is a chip — all
  of them changeable at any point in a Game, because that is what those concepts are
  (see **Controller** in `CONTEXT.md`). The gate was asking for the same four answers one
  screen earlier, and then the Game screen had to offer them anyway.
- **Shaky Squares survive the trip.** They are ringed on the played board for as long as
  no move has been played, and the source photograph is still one tap away. The promise
  0008 was defending — the recogniser may be wrong, never *quietly* wrong — is kept by
  showing the doubt where the user is actually looking, rather than by holding a screen
  in front of them first.
- **A mirrored Orientation is most visible on a board you are about to play.** It is
  still the failure that stays perfectly legal, and it is still the reason to look. But
  the tell is your own pieces sitting at the far side, and that reads faster on a live
  board than on a confirmation screen.

## Consequences

- A good recognition costs zero taps and a bad one costs one. That is the trade: the
  common case is free and the rare case is no longer free. It is knowingly a risk — a
  player can start moving on a mirrored or misread board — and the mitigations are the
  ringed squares, the thumbnail, and how cheap the fix is.
- The validator is untouched and still the safety mechanism 0008 describes: Stockfish 18's
  `Position::set` validates nothing, so an arbitrary arrangement must be refused before
  the engine sees it. It now runs on the way *out of* the editor instead of on the way
  *into* the Game, which is the same code guarding the same door. Recognition's own FEN
  goes through it too, before a session is built.
- The editor keeps only what the Game screen cannot express: which piece stands on which
  Square, plus castling rights and the en passant Square behind an advanced toggle. It
  gained nothing and lost 先走, 视角 and the Controllers — anything operable on the Game
  screen is not duplicated there.
- Editing is allowed only while the Game has no moves. Replacing the starting Position
  under moves already played would invalidate them, so `replaceStart` refuses, the
  editor's entry point disappears after the first move, and the way to fix a position
  noticed late is a fresh Recognition.
- Correcting a Position keeps the same Game rather than starting a second one, so a
  recognition that needed a fix leaves one entry in the library, not two.
