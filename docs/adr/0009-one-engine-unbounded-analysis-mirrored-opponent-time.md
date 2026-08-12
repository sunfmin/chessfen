# One engine, unbounded Analysis, Mirrored Time for the opponent

The app asks the engine for three different things — advice on the position in front of
the player, the opponent's move, and a Review's uniform scores — and does all three
through a single `Stockfish::Engine` behind a serial Swift actor that stops the previous
search before starting the next. The three never overlap in time anyway: the engine is
not the opponent while it is advising the player.

Search is **unbounded** when advising: iterative deepening runs for as long as the player
leaves it, and the UI re-renders every `info` update, so the recommended move and score
visibly change as depth climbs. Reproducibility is explicitly given up.

Each colour has a **Controller** — the player's hands or the engine — switchable at any
point in a Game, so hand-moving both sides, playing one, swapping, and engine-versus-engine
all fall out of the same model. When the engine controls a colour it plays at **full
strength**, limited only by **Mirrored Time**: about as long as the player took over their
last move. No `UCI_LimitStrength`, no `UCI_Elo`, no `Skill Level` — there is no difficulty
setting in this app.

## Consequences

- Memory stays at one resident copy of the 67 MiB network plus one transposition table.
  A second instance would double the network and put a phone at risk of being killed.
- Tests cannot assert an exact best move, because multithreaded search is
  non-deterministic by design (`Skill::pick_best` even seeds its PRNG from the clock).
  They assert **convergence properties** instead: on a mate-in-2, once depth reaches 10
  the best move must be the mating one. A correct engine satisfies that without being
  deterministic.
- A Review needs one uniform Depth across every move to make Scores comparable; during a
  game the per-move scores are whatever depth happened to be reached, so they are drawn
  as provisional (hollow, depth-labelled) and never fed into the Review's curve.
- Mirrored Time is clamped to `[0.3s, 60s]` by default so a phone is not pinned at full
  load while the player is away from it; the ceiling is a setting and can be removed.
- With both Controllers set to the engine there is no human move to mirror, so the last
  mirrored duration carries over (3s until one exists).
- Search must stop when the app leaves the foreground, and the gate that enforces it sits in
  the engine rather than in the screens — a screen can forget, and one that did would leave a
  phone thinking in a pocket. What a search wanting to start while the app is away does depends
  on what it is for: an unbounded Analysis is refused, because it belongs to a screen someone
  is looking at and that screen asks again on the way back, while a bounded search is held and
  run when the app returns, because someone is waiting on its answer. Holding is what a Review
  in particular needs: stopping its searches one ply at a time and carrying on would score the
  rest of the game at whatever Depth each got to, and a Review that is not at one uniform Depth
  is not comparable with itself.
