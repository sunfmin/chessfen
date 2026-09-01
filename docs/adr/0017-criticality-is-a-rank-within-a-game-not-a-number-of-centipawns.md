# Criticality is a rank within a Game, not a number of centipawns

`MoveQuality` names a move by an absolute loss — 300 centipawns is a 漏着, 150 a 失误, 50 an
不精确. Those names are fine and they stay. What changes is that **they no longer decide
what a player is asked about.** Which moves come back as a Drill is the **worst three of
that Game, by rank**, whatever their absolute size.

The reason is that this app has to serve a beginner, an amateur and a club player without
growing a level setting. Time is the only dial (docs/adr/0009), and a
beginner/amateur/club picker would break that line for a fact the app can simply observe.
Absolute thresholds cannot serve all three: for somebody losing games to 900-centipawn
giveaways, a 50-centipawn inaccuracy is noise, and for a club player 50 centipawns is
precisely the interesting band. A rank within the game solves it with no statistics, no
configuration and no arithmetic about the player: a beginner's worst three moves *are*
their giveaways, and a club player's worst three *are* their subtleties. Same code, and it
follows the player up as they improve without being told that they have.

## Consequences

- Every Game yields questions, including one played well. Three moves is what a Drill is
  made of, not "the moves that crossed a line" — and a Game with no bad move in it still
  has a worst three, which is the right thing for a club player and harmless for a
  beginner.
- The absolute labels keep their job, which is naming: a ranked move is still called a
  漏着 or an 不精确 when it is one, and called nothing when it is not.
- Ranking requires the evaluations to be comparable with each other, which is exactly what
  docs/adr/0016 is for. A ranked Drill on a mixed-provenance array would be a list of
  invented mistakes.
- A club player's unit of study is a plan over several moves rather than one move, and that
  is covered by letting an Intent attach to a Variation they play out — the same Variation
  machinery a rewound Game already has. Still no level setting: a beginner never opens that
  door and a club player lives behind it.

  > Built by [ADR 0020](0020-the-layer-names-a-few-squares-instead-of-reporting-them-all.md), which caps that
  > Variation at five Ply and gives it a layer that marks the plan's gains and costs along
  > the way. That ADR also borrows this one's central move — rank within the position,
  > never a threshold — to decide which squares are worth drawing at all.
