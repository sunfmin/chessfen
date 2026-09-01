# The layer names a few squares instead of reporting them all

这步改了什么 draws every square whose holder the last move changed: the squares it took a
grip on in one colour, the squares it let go of in another, a legend counting both, and a
line about the ones beside the mover's own king. It is an accurate report and it teaches
nothing. The complaint that produced this ADR is the whole argument:

> 我管住了这些格，然后呢？怎么了？我学到什么呢？哪些格子重要？它为什么重要呢？

Nine squares in two colours is a diff. A player cannot act on a diff, because the layer has
declined to do the only part that is hard: deciding which of the nine mattered. **The layer
stops reporting and starts judging.** At most three squares are drawn, usually one, and each
one carries a sentence saying what it costs or buys.

**Which squares get drawn is decided by two nets, not one.** The rules propose and the
engine disposes. A rules net says which squares *can* matter — a square beside the mover's
own king, a square no pawn of theirs can ever attack again, a square an enemy piece can
actually reach and hold, a square one of their own pieces wants and cannot safely take. The
engine's own Line then says which of those *did*: a square nothing in the next several moves
goes near did not matter, whatever the rules thought of it. Rules alone would mark textbook
squares that are irrelevant in this position; the engine alone would rank a set of squares
with nothing to say about why any of them is on the list. Neither net is enough and the
order matters — the rules produce candidates cheaply, and the engine is asked only to sort
a handful.

**Importance is a rank inside this position, never a threshold.** The same decision as
docs/adr/0017 and made for the same reason: one mechanism has to serve a beginner and a club
player without the app ever being told which it is talking to. "The most important square
here" is a question that has an answer in every position. "Squares worth more than N" needs
to know who is asking.

**The engine still answers second.** docs/adr/0015 is untouched. Before a Guess is committed
the layer draws nothing on its own — a king-ring warning painted unprompted is the blunder
check performed on the player's behalf, which is the one thing they are here to learn to do.
What they get before committing is a **scanner**: point at a square and it answers about that
square. After the commit the engine is already talking — that is what a Reveal is — and the
reading appears by itself, because hiding it behind another tap at the one moment it is
allowed to speak is a tap that buys nothing.

**The consequences are paid for by the Review, not by the Stint.** A Review already re-scores
every Ply at one uniform Depth (docs/adr/0016), and to produce each Score the engine already
produces the Line this ADR needs. It kept the Score and dropped the Line. Now it keeps both,
written into the Ply's PGN braces beside the evaluation. No new search is started, so the ten
seconds an Analysis is bought in (docs/adr/0019) are untouched, and a phone stays cool.

## Consequences

- **Control Change becomes the candidate pool rather than the drawing.** It is still every
  square that changed hands and it is still computed the same way; what changed is that the
  screen consumes it instead of printing it. The two-colour wash and the counted legend go.
- **A layer that judges can be wrong, and that is the point.** Every sentence it prints comes
  from a fixed template over facts the rules code can check — which piece, which square, how
  many moves, can it be thrown out — in the style an Intent is already judged in
  (docs/adr/0018). Nothing is printed that the app could not also be told is false. Freeform
  prose about the position is exactly what is not being built here.
- **The engine's recommendation is translated into the seven Intent verbs.** An engine gives a
  number and a Line and never a reason; the Line read through 吃 / 换 / 攻 / 护 / 躲 / 挡 / 占
  is a reason, and it is one the same checker can be pointed at. It also puts the player's
  stated reason and the engine's into the same eight words, so 「我说的是护 f7，引擎说的是占 d5」
  is a comparison rather than a translation exercise. A Line that reads honestly as nothing
  gets 说不清, exactly as a player's move does. Note which way 占 points while doing it: it is
  about **control** and not occupation (docs/adr/0018), and a piece does not attack the square
  it stands on — so the rook that takes the fifth rank 占 d5 and the knight that goes and
  stands on d5 does not. A move whose whole point is to occupy a square is named by the layer,
  as a 据点, and by no verb.
- **A Line the engine expects is played on the main board, and never written to the Game.**
  Watching the squares change hands step by step is what "看到五步之后" means concretely, and a
  cumulative sentence at the end says where the whole line arrived. It is ephemeral: no
  Variation, no PGN, and leaving it restores the position exactly. Only moves somebody
  actually played become Variations.
- **The unbuilt consequence of docs/adr/0017 finally gets built.** An Intent attaches to a
  Variation of the player's own, capped at five Ply — a plan longer than that cannot be
  judged honestly, because the opponent has had enough replies that no claim about the
  position is falsifiable any more. Five is a cap on what can be checked, not a guess at how
  far people see.
- **The board draws less and says more, which is the trade being made deliberately.** A player
  who wants the full diff no longer has it. That is accepted: the full diff was available for
  months and produced the question this ADR answers.
