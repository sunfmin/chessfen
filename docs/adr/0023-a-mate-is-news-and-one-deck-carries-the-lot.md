# A mate is news, and one deck carries the lot

Two decisions, taken together because the second is what made the first affordable.

## A mate is news

docs/adr/0015 keeps the engine quiet: no Score, no arrow, nothing whispering a move until the
player has answered first. docs/adr/0022 opened that by exactly one crack — a Tactic, on the
latest position, behind a switch. **A mate walks through the same crack, and does it on the
strength of being a different kind of statement.** A Score is a judgement and can be argued
with. 「你三步之后不在了」 is a fact, and a fact withheld is not teaching, it is a trick.

**步杀消息 announces itself. It never starts a search.** It reads whichever search has already
run: the standing Analysis when the engine's opinion is on, or 战术发现器's bounded probe when
it is not (`depth 10`, docs/adr/0022). Practice with the finder off has searched nothing, so it
says nothing — the quiet default of docs/adr/0015 is intact, and there is one engine still
(docs/adr/0009).

**Whose mate it is comes out of the sign of one number.** A Score is White-relative, so
`.mate(in: +2)` is White mating and `.mate(in: -2)` is White being mated; which Controllers a
person holds decides the voice — 你有 2 步杀 / 对方 2 步杀 / 白方 2 步杀 when nobody is at the
board. 「不管是对方的还是我方的」 is therefore not a second feature and not a second code path.

Every clause of the sentence is counted, not asserted: the line is replayed and the rules asked
how many of the answers were the only legal move, and whether the line actually ends in mate. A
mate Score whose line stops short is still news and says so. Like every other sentence in the
layer (docs/adr/0020), it can be told it was wrong.

The line draws as numbered arrows in the same violet-and-red as 五步计划, capped at six plies.
五步计划 stops at five for what can be **checked** (docs/adr/0018); this stops at six for what
can be **seen**. Past that the board is a scribble and the SAN rows are the transport.

## One deck carries the lot

The eleven stacked sections under the board earned the name 「这么多一连串的功能」, and the test
of that stack was not that it was long: it was that the person who commissioned every one of
those features could not say what 要害, 走马灯, 复盘 or 最贵三步 were for.

**The board keeps the whole screen. Under it is one card at a time, paged sideways, with a row
of dots.** The dots are as much the point as the paging — a scroll never says how many things
there are, and a deck does. A mate's dot wears whose mate it is before anybody has swiped to it,
which is the whole of what 「直接给予提示」 amounts to here.

**The cards are dealt from the position, not from a fixed list.** 这步的要害, 走马灯, 考一遍 need
a past Ply; 复盘 and 最贵三步 need a uniform-depth pass (docs/adr/0016); 步杀 and 战术 need the
latest position. A card that has nothing to say is not dealt, and **the last card says what is
missing and why** — the dependency chain is a fact about the app that the app should be able to
state.

**Every card carries a one-line subtitle under its name.** Four of these are named after ideas
somebody has to have been told about once, and a deck of bare titles is a deck you have to be
taught before you can use.

**复盘 and 最贵三步 are one card.** The three worst moves are that pass's own output and have no
existence without it; two cards implied two things to understand.

**The affordance rule: a layer that only *draws* follows the card it is named on; anything that
spends a *search* keeps a press of its own.** Arriving at 走马灯 starts the walk, arriving at
这步的要害 turns the layer on, arriving at 步杀 draws the arrows — drawing is free and putting it
back is exact, and somebody who swiped to 「对方 2 步杀」 has already asked the question a button
would have asked. 战术, 复盘 and the engine's opinion keep their buttons, so no amount of swiping
can quietly start a search.

Arriving is also non-destructive: a walk or a scan already set up is left alone rather than
restarted, or the deck would wipe the state it was opened to show.

## Consequences

- The six chips that used to sit under the board are gone; the cards are the affordance.
- A screenshot test has to name the card it photographs. A paged deck also keeps a neighbouring
  card alive in the accessibility tree, so a test is held to **its own card's** words and to the
  session — never to the absence of another card's words.
- One card at a time means one card's numbers at a time: a test that counted Scores across the
  whole stack now counts the strip's.
- 复盘 is a card and no longer a place to go to, which is what docs/adr/0015 wanted and had not
  finished paying for.
