# PGN links import whole studies, one chapter per game

Pasting a PGN link — a lichess study URL being the canonical case — downloads the whole
multi-game PGN and files every chapter as one game into a collection. The library's 从链接
导入 row opens a sheet that asks for the link and the collection; a collection's own `+`
opens the same sheet pinned to that collection, which is the "add more games here" door.
This is the app's first networking, and the first importer of games it did not itself
record.

A lichess study is one PGN with one chapter per game, tagged `[StudyName]` on every
chapter and `[ChapterName]` per chapter. The whole thing is reachable by appending `.pgn`
to the study URL, anonymously for public studies and with a 403 for private ones. So the
whole import is: download one text, split it at tag boundaries, and write one file per
chapter through the same path a recognised game takes (`GameLibrary.write`), with
`StudyName → Event` (the collection), `ChapterName → Name` (the game's name in the set's
order), and `Source → imported` — a third `GameOrigin` alongside 手摆 and 识别. The split
respects comment and variation depth, so a `[%cal]` line inside a variation is content,
not the start of the next chapter, and the existing `PGN(parsing:)` stays single-game.
Chapters that will not parse are counted and skipped, not fatal — the Entry philosophy
that a game the app cannot read is "无法读取", never a lost file. A game already in the
target collection under the same name is skipped, so the same study imported twice adds
nothing.

## Consequences

- **ChessfenKit touches the network for the first time.** Everything below the fetch is
  the existing offline machine, and the fetch itself is the one new seam: a
  `PGNFetching` protocol with a URLSession implementation, exercised in tests by a
  scripted one — the `ScriptedEngine` convention. Fetching runs off the main actor and
  against https only, so no App Transport Security change. A lichess study page URL is
  tried first and its `.pgn` export second, because the export is the thing that works;
  an HTML page that parses to zero chapters falls through to the next candidate.
- **Private studies are an honest error, not a token prompt.** v1 imports only what is
  public: lichess's 403 on a private study reads as 这个棋谱不公开, with the message that
  it can't be downloaded. Authentication stays future work — the download seam already
  hides where the text came from, so a token only changes the fetcher. The 403 reading
  is tied to the lichess domain, knowingly: other sites return a plain HTTP error.
- **A chapter becomes one file, never a merged one.** One game per file is the storage
  model (ADR-0010/0012) and everything downstream — the library, the Files app, iCloud
  sync — assumes it. A single file holding forty-seven chapters would be a PGN the
  existing screens cannot open and the library cannot name. Chapter-level variations
  were rejected the same way: the parser drops variations that branch after a white
  move, which is pre-existing behaviour and out of scope; what imports is each
  chapter's main line, intact.
- **The name chain is ChapterName → Event → 白 对 黑 → Date → 第 N 章.** Real chapters
  often lack `[White]`/`[Black]` or any naming at all, and an import must still produce
  a name — a game needs one to sit in a collection's order and to be deduplicated
  against. A whole study of unnamed chapters falls to the date, not to one shared name
  that would make every chapter a duplicate of itself.
- **Dedup is by name within the target collection.** A game renamed after import
  re-imports under the chapter's name — accepted: the name is the only handle a
  chapter has, and re-importing is an explicit act.
- **A third origin needs no migration.** `Entry.origin` reads the `Source` tag, so old
  files simply have no such tag and stay what they were. The imported chip is 导入 with
  a link glyph.
- **The About screen no longer says the app never connects.** It now says the one
  thing that is true: the only download is the link an import is told to fetch.
- **Importing is the one write that is not per-move.** Recognition saves at the end of
  a session; an import writes N files at once, each through the same `GameLibrary.write`
  and each with a fresh `newURL()` so same-named chapters can't collide.
