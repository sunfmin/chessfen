# A Drill is derived from the PGN files, never a second store

Spaced repetition — the thing that would make a mistake come back at the right interval —
wants a mutable, cross-Game table: which question, how many times answered, when next.
That is a database, and this app has deliberately never had one: one PGN file per Game is
the whole storage model, and its value is that anything which reads PGN reads everything
the app has ever written (docs/adr/0010, 0012).

The decision is that **nothing about learning becomes a second source of truth.** A Drill
is computed on demand from the files: open a Game, rank its moves (docs/adr/0017), ask
about the worst three. A Failure Mode — the kind of error a player repeats — is a tally
over the files, recomputed, never stored. There is no queue, no scheduler and no progress
row anywhere.

What the files do gain is one new token, in the same braced-`[%…]` convention `[%eval]`
and `[%cal]` already use:

```
12. Nf3 {[%int def f7]} Nc6 {[%int ?]}
```

**`{[%int <verb> <square>]}` is a declared Intent** — what the player says the move was
for. A verb and a target Square, because that shape is the one that can both be drawn on
the board (an arrow and a ring) and be falsified by the rules code (did f7 actually gain a
defender?). `?` is 说不清, recorded rather than skipped: a Game with twenty-five of them
is itself the whole diagnosis, and it is a diagnosis no other chess app can obtain.

## Consequences

- Spacing is not in v1. If it is ever wanted, the way in is the same one: the answer log
  goes into the braces beside the Intent it belongs to, and the schedule stays *derived*.
  A separate store is the thing being refused, not the feature.
- The tally is recomputed by reading the library, which costs a pass over a few kilobytes
  per Game. Affordable, and it means a Game corrected or deleted in the Files app changes
  the diagnosis immediately, with nothing to reconcile.
- The verb vocabulary is fixed and small, and the rule that generated it is worth keeping:
  **a verb that cannot be wrong does not get a slot.** 将 was cut by it — whether a move
  gives check is something the app already knows, so declaring it is unfalsifiable and
  teaches nothing. 吃 survived because its claim is not "this is a capture" but "I win
  material here", which SEE can call false.
- Anything that reads PGN still reads all of it. An `{[%int]}` in a file opened elsewhere
  is a comment, which is what it is.
