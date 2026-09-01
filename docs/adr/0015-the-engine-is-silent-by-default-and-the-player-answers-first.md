# The engine is silent by default, and the player answers first

This app links a full-strength Stockfish into the binary and then, by default, shows
almost none of what it thinks: no Score, no arrow on the board, no Lines. **Practice** —
the switch that used to be the interesting departure from the default — *is* the default,
and the engine's opinion is what you turn on.

The reason is that the app's purpose is not to tell somebody how good their move was; it
is to make them better at chess, and those two want opposite things of a screen. What
teaches is committing to an answer and then finding out you were wrong. What prevents
teaching is the answer already being on screen — and that is not a matter of the player's
self-discipline, because attention does not decline a number in the corner. So the
sequence is fixed: **the player answers, and only then does the engine.**

## Consequences

- **One board, one switch.** There is no separate review screen. A Game, a Drill and a
  Review are the same screen with the engine's opinion switched off or on, and browsing back
  to a past Ply is what makes it a study rather than a game.

  The cost is recorded rather than designed around, because it is real and it is this ADR's
  own argument: a switch does put the answer one tap away, which is close to it being on
  screen. What carries the discipline instead is the switch's **default and its scope** — it
  starts off every time and it belongs to the Game in front of you, so the answer is never
  where you left it. Two screens for one board would have been two places to keep in step,
  and that price was judged the higher one.
- **The app does not point at the critical moments.** The engine could say "think here",
  and it deliberately does not: noticing that a position is critical is most of the
  distance between a beginner and a club player, so handing it over would be teaching
  around the lesson. An Intent can be declared at any moment by asking; nothing asks for
  one on the app's initiative during a Game.
- **There is no accuracy percentage, and no rating.** A Drill produces two verdicts that
  are never multiplied together — was the move sound, and was the stated Intent true —
  because "right move, wrong reason" and "wrong move, right reason" are different
  failures with different remedies, and one number throws away the distinction that makes
  this worth building. A rating would also be a fake number: no opponents, no pool, and
  it would compete with the rating the player actually has on lichess.
- **The material is the player's own Games and nothing else.** No bundled puzzle corpus,
  no downloaded tactics set — partly because it would contradict the app being a thing
  that works on a plane with no account (docs/adr/0010, 0012), and partly because a
  Review already finds a better set of problems than any corpus could: the moves this
  player actually got wrong.
- **A player's level is observed, never declared.** There is no beginner/club setting;
  time is still the only dial (docs/adr/0009). Levels are covered instead by what a
  Drill asks about, which is ranked rather than thresholded (docs/adr/0017), so the same
  code hands a beginner their giveaways and a club player their inaccuracies.
- **What the board draws about a move — which of your pieces are loose, which squares
  changed hands — belongs to a Drill and a Review, not to a Game in progress.** Drawn
  during play it would be the blunder-check performed on the player's behalf, which is
  the one thing they are here to learn to do.

  > Sharpened by [ADR 0020](0020-the-layer-names-a-few-squares-instead-of-reporting-them-all.md): during a Game
  > the layer now draws nothing at all on its own initiative, and answers a tap about one
  > square instead. After a Guess is committed it appears by itself — that is the moment the
  > engine is already speaking, so a second tap to reach the reading buys nothing.
