# The plan is handed over and the reason is asked for

五步计划 shipped as a blank canvas: tap it, and the app waited for you to walk five moves
onto the board and then say what they were for. The complaint that produced this ADR is the
whole argument:

> 点五步计划的时候，要人直接去设置，我觉得比较难。

It is difficult in the wrong direction. The player who can already write down a five-move
line did not need the feature; everyone else got an empty box and closed it. Worse, the box
asked for the *easy* half. Producing a plausible line is what an engine at depth 14 does in
a few hundred milliseconds. Saying what a line is *for* — and being told when you are wrong
about it — is the part no engine does for you and the part a club player has never once been
made to practise.

**So the engine writes the moves and the player owes the reason.** One tap fills the plan in
from the engine's own best line, capped at five plies; the board draws all five as numbered
arrows, yours in your colour and the replies in the other; and every step gets a row saying
what that move is for and what it gives away. What is still asked for, and still marked, is
one Intent over the whole line, in the same seven verbs a single move's reason is declared
in, checked move by move by the same checker (docs/adr/0018).

**This is the one place on the study screen where the engine speaks first.** That is a real
exception to docs/adr/0015 and it is narrower than it looks. The rule there is that the
engine must not answer the question the player is being asked — 你会走哪一步 — before they
have answered it, because a Best Move arrival on arrival is a hint button and the blunder
check performed on their behalf. 五步计划 asks a different question. It is not "what would
you play here": that question is the Drill, it is on the same screen, and it still gets no
engine at all until a Guess is committed. A plan starts from a line already on the table and
asks what it accomplishes. Handing over the line does not answer that; it is the premise of
it. The scanner is the test of whether this holds: it stayed exactly as it was — you point,
you hear your own move's worth in your own terms, and the engine's opinion comes last and
only on a tap (docs/adr/0020).

**A line the app cannot say anything about each step of is a line it should not hand over.**
The rows are not decoration on the arrows. Five moves of engine notation is what every chess
app on a phone already gives away for free, and what it teaches is that the engine knows
things. Each row runs through the reader the scanner's trial and the engine's own move
already run through — the verb it answers to, the square, the count — so the plan is read in
the same words the player will have to use to make their claim about it. The opponent's
replies are read from the opponent's seat, which is what makes them threats rather than
filler: a plan whose answers are left blank is a plan nobody checked.

**护 stops naming pieces nobody is attacking.** Reading five moves at once made a fault
visible that reading one had hidden. 护 was the verb of last resort: it held whenever any
piece of yours gained a defender, and nearly every developing move does that, so
1.e4 e5 2.Bc4 read as 「护 a2」 — true, and not a reason. A verb that is true of almost every
move says nothing about any of them, which is the same objection docs/adr/0018 raises against
a verb that cannot be wrong. The reader now offers 护 only for a piece that was hanging, or
failing that one the opponent is at least looking at, and Bc4 reads 「占 d5」 instead. The line
is worth drawing exactly there: O-O gains f2 a defender and a bishop on c5 is pointed straight
at f2, so O-O still reads 「护 f2」, which is why people castle. Nothing has ever looked at a2.
The *checker* is unchanged: a player who declares 护 on a quiet square is still told plainly
whether the count went up, because that is what they claimed. Only the candidate ranking moved.

## Consequences

The engine is asked for one bounded search at the study Depth when the plan opens, which is
the same Depth everything else in a study reports at, so a plan and a Reveal are never two
different numbers deep. Nothing arriving is not a failure: the draft stays open and the board
still writes the line, which is what this was before.

A search that comes back to find moves already on the board leaves them alone. Adding to the
line and taking moves back off it both survive, so disagreeing with the engine is one tap of
退一步 away — the line is a seed and not a cage.

The board now carries three kinds of arrow: the engine's Best Move, the player's own offered
move, and the plan. The plan draws under both of the others and thinner than either, because
those two are one move each and this is a shape.

A plan still branches from a past Ply and still goes into the PGN as a Variation with its
Intent and its span on the first ply, exactly as docs/adr/0017 asked. Nothing about the
storage changed; what changed is who writes the moves.

> docs/adr/0015 — the engine is silent by default, and the player answers first. This ADR
> takes one exception to it and says why the Drill and the scanner keep it.

> docs/adr/0018 — a verb that cannot be wrong does not get a slot. The 护 change here is that
> rule applied to a verb that could be wrong but almost never was.
