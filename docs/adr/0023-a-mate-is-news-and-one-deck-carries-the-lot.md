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
there are, and a deck does. A mate's dot wears whose mate it is, and the deck opens on the news
when there is news, which is what 「直接给予提示」 amounts to here.

**The deck never changes shape: the same ten cards, in the same order, whatever the position.**
It was dealt from the position for one afternoon and that was a mistake — cards appearing and
disappearing as the eye moved between the latest Ply and a past one, so the fourth dot was a
different card every time you looked. A deck like that cannot be learnt. Ten dots that never move
can be. **A card that cannot answer here says so on its own face**, in the one sentence that says
which of the reasons it is: no 「刚走的那步」 on the latest position, no line anybody has paid for
yet, no uniform-depth pass. The last card still lists them all in one place, for somebody who
would rather read it once than swipe through ten.

**Every card carries a one-line subtitle under its name.** Four of these are named after ideas
somebody has to have been told about once, and a deck of bare titles is a deck you have to be
taught before you can use.

**复盘 and 最贵三步 are one card.** The three worst moves are that pass's own output and have no
existence without it; two cards implied two things to understand.

**The card you are on is the card that acts.** Arriving turns its layer on — the scan, the walk,
the squares, the mate's arrows, the finder — and leaving turns that layer off again, so the board
is only ever drawing the one card in front of you and never the leftovers of three you swiped
past. 「用户滑动了卡片，就只在棋盘上反应当前卡片。」

This replaces a narrower rule that stood for one afternoon — draw-only layers follow the card,
anything that spends a search keeps a press — and it is a deliberate widening: **a swipe onto 杀
or 战术 starts the finder's probe**, one bounded `depth 10` search, because 「只要用户滑到了那个
卡片就自动打开」 is how a person asks for it. Practice stays on around it: no Score, no candidate
Lines, just the shot and the mate. What the swipe turned on, leaving turns off; what a person
turned on with the switch is theirs and stays.

**The one card still behind a deliberate press is 复盘.** A pass re-scores an entire game at a
uniform depth and writes what it finds into the file (docs/adr/0016) — minutes of engine time and
a change on disk. Turning a page is not an instruction to spend that.

Arriving is otherwise non-destructive: a walk or a scan already set up is left alone rather than
restarted, and a committed plan's verdict is not thrown away to start another, or the deck would
wipe the state it was opened to show.

**杀 and 战术 speak about a past Ply too**, which is a straight amendment to docs/adr/0022's
「a past Ply is still a Drill, and the finder is silent there」. Both are cards of their own now,
one swipe from 考一遍 rather than printed on top of it, so going to look is a thing somebody does
on purpose — and a mate on a Ply you walked back to is the same fact about the same board. The
engine still only *plays* from the latest position; a probe at a past Ply costs one bounded
search and moves nothing.

## Consequences

- The six chips that used to sit under the board are gone; the cards are the affordance.
- A swipe can now cost a `depth 10` search, so paging back and forth across 杀 / 战术 probes each
  position it lands on. That is the price of 「滑到就自动打开」 and it is bounded by design.
- Two of docs/adr/0015's silences are narrower: the finder answers wherever the eye is, and a
  Drill's position can be asked about by leaving the question and swiping two cards along.
- A screenshot test has to name the card it photographs. A paged deck also keeps a neighbouring
  card alive in the accessibility tree, so a test is held to **its own card's** words and to the
  session — never to the absence of another card's words.
- One card at a time means one card's numbers at a time: a test that counted Scores across the
  whole stack now counts the strip's.
- 复盘 is a card and no longer a place to go to, which is what docs/adr/0015 wanted and had not
  finished paying for.
