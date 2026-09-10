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

**The deck never changes shape: the same five cards, in the same order, whatever the position.**
It was dealt from the position for one afternoon and that was a mistake — cards appearing and
disappearing as the eye moved between the latest Ply and a past one, so the fourth dot was a
different card every time you looked. A deck like that cannot be learnt. Five names that never
move can be. **A card that cannot answer here says so on its own face**, in the one sentence that
says which of the reasons it is: no 「刚走的那步」 on the latest position, no line anybody has paid for
yet, no uniform-depth pass.

**Every card carries a one-line subtitle under its name.** Some of these are named after ideas
somebody has to have been told about once, and a deck of bare titles is a deck you have to be
taught before you can use.

**五步计划 is the second half of 五步, not a card.** The engine's five on the board and five of
your own with one reason over them are one subject — looking five moves ahead — and the session
already keeps the two off each other's board: starting a plan ends the walk, and starting a walk
is refused over a draft. It was a card of its own until the deck was cut to five
(docs/adr/0021), and it went unreachable with them; anything a cutting of the deck takes off the
screen has to be re-housed or retired on purpose, because nothing about a view that stops being
referenced is red — the tests call the session, and the session was never the part that was
missing.

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
a change on disk. Turning a page is not an instruction to spend that. It is no longer a card at
all: a pass is a press in the ⋯ menu, and what it produces is the curve behind the record and a
Score on every Ply the eye can walk to.

Arriving is otherwise non-destructive: a walk or a scan already set up is left alone rather than
restarted, and an open plan is not thrown away to start another, or the deck would wipe the state
it was opened to show.

**And a card that is already at work does not get moved by news.** The mate that turns up takes
the eye — that is 「直接给予提示」 — but never out from under a plan being written, a question
being asked, or a square being scanned, and never off 五步 at all. 五步 is the card that spends
the Stint which finds the mate, and the Line it walks is the *same* search's answer, so jumping for
the news tore down the walk that had just paid for it — a feature that eats somebody's line is worse
than one that waits for a swipe. On that card the news lights 杀招's tab and waits, which is one
coloured pill away rather than nothing.

**Dealing the deck is an arrival**, with everything that means: the card that comes up acts, and
acts *while it is the card being read*. So the engine is attached before the deal, and a 要害 that
opens a game spends its Stint like any other arrival. The alternative was a first card that said
「滑到这张卡会算 10 秒」 while it was the card in front and the engine was already there — the deal
ran before `attach`, so the one card nobody had to swipe to was the one card that never asked.

**杀招 and 战术 speak about a past Ply too**, which is a straight amendment to docs/adr/0022's
「a past Ply is still a Drill, and the finder is silent there」. Both are cards of their own now,
one swipe from 练习 rather than printed on top of it, so going to look is a thing somebody does
on purpose — and a mate on a Ply you walked back to is the same fact about the same board. The
engine still only *plays* from the latest position; a probe at a past Ply costs one bounded
search and moves nothing.

## What a card looks like

The behaviour above was right and the thing on screen was not: ten identical dots, a window
about 180 points tall that cut 五步计划 and 考一遍 off mid-sentence, and ten bodies that had each
invented their own type hierarchy — chips here, bullets there, numbered circles, bare paragraphs.
It did not read as a card and it did not read as swipeable. Photographed one at a time, the ten
shots are the argument (`ios/App/out/deck-01…10.png`).

**The deck occupies the room under the record and no more.** Rounded top corners, a hairline, a
lift shadow — it is still a card, not the bottom of a scroll. A body longer than the window
scrolls inside it. It does not pull up over the board.

**Arriving at a card that reads a Line spends a Stint**, even during Practice: the swipe is the
asking, the board stays silent, and 五步 / 要害格 / 杀招 / 战术 walk what those ten seconds found
instead of waiting for a Review. 复盘 keeps a press of its own in the ⋯ menu — a pass re-scores a
whole game. A Guess still being held is the player answering, and no card speaks over that.

**Ten dots, then a grouped rail, and now one capsule of five names.** The ten used to sit in four
clusters with a gap between them — 现在 / 这一步 / 任何一格 / 这一局 — and the group you were in
named at the right end. The grouping was the answer to 「十个名字要先学会」; with five cards there
is nothing left to group, so the five sit in one centred capsule on the page under the card, in
the home-indicator band. Tapping a name and swiping the page are the same turn. The current tab is
a filled pill in its card's own tint, so 杀招 wears whose mate it is even from three cards away.

**Six primitives, and every body is built out of them.** A lede sentence, a row of move chips, a
numbered row (figure · move · what it is for · what it gives away), a figures row, a note, and an
action row. The numbered badges are the numbers on the board's arrows, so what a tap will do is
visible before it happens. Eighteen bordered system buttons became one chip idiom, and a control
says what the press *does* rather than what the card is called — 「找一记」/「不找了」, not a chip
labelled 战术 under a head that also says 战术.

## Consequences

- The six chips that used to sit under the board are gone; the cards are the affordance.
- A swipe can now cost a Stint, so paging across 杀招 / 战术 / 要害 / 五步 spends ten seconds of
  engine time on each card it lands on, even during Practice. That is the price of 「滑到就自动打开」
  and it is bounded by design. The board stays silent; the card is what the ten seconds are for.
  Dealing the deck is an arrival too, so opening a game on 要害 spends the first one — the card in
  front is the card that acts, and a card that could not answer while it was the one being looked
  at would be worse than the ten seconds.
- Two of docs/adr/0015's silences are narrower: the finder answers wherever the eye is, and a
  Drill's position can be asked about by leaving the question and swiping two cards along.
- A screenshot test has to name the card it photographs. A paged deck also keeps a neighbouring
  card alive in the accessibility tree, so a test is held to **its own card's** words and to the
  session — never to the absence of another card's words.
- One card at a time means one card's numbers at a time: a test that counted Scores across the
  whole stack now counts the strip's.
- 复盘 is a press in the ⋯ menu and no longer a card, which is what docs/adr/0015 wanted and had
  not finished paying for. The three worst moves are not a list on a card either: they are the
  questions 练习 walks.
- **A card cut from the deck takes its features with it, and nothing goes red.** 五步计划, the way
  to the next game in a collection, and the runners-up the engine was weighing all left the screen
  when ten cards became five: the session kept all three, the tests drove them through the session,
  and the phone had no way in. Two were re-housed (五步计划 under 五步, 上一局/下一局 in the ⋯
  menu); the third — the lines behind the one the bar is showing — was retired on purpose. Cutting
  a card is a UI change that has to be walked through feature by feature.
- Every card is photographed on its own (`ios/App/ScreenTests/DeckGalleryTests.swift`), in a state
  where it actually has something to say. A body that clips or a head that repeats itself is then
  a thing somebody can see rather than a thing somebody has to swipe to.
