import ChessfenKit
import Foundation
import Testing

/// A two-chapter study in the shape lichess exports: one PGN, `[ChapterName]` and `[StudyName]`
/// on every chapter. The second chapter has no `White`/`Black` — real chapters often do not,
/// and the name chain has to work without them.
private let twoChapterStudy = """
[Event "Wood Pecker 1-47"]
[Site "https://lichess.org/study/HgiqcIqW/0fg3fROm"]
[Date "2021.??.??"]
[Round "1"]
[White "Sunfmin"]
[Black "Stockfish 14"]
[Result "*"]
[ChapterName "1"]
[StudyName "Wood Pecker 1-47"]
[ChapterMode "normal"]

1. e4 e5 2. Nf3 *

[Event "Wood Pecker 1-47"]
[Site "https://lichess.org/study/HgiqcIqW/0fg3fROm"]
[Date "2021.??.??"]
[Round "2"]
[Result "*"]
[ChapterName "2"]
[StudyName "Wood Pecker 1-47"]
[ChapterMode "normal"]

1. d4 d5 2. c4 *
"""

/// One game's worth of tags, for building fixtures that need a known shape.
private func chapter(_ name: String, movetext: String = "1. e4 *") -> String {
    """
    [Event "Something"]
    [Site "Somewhere"]
    [Date "2026.08.12"]
    [Round "-"]
    [White "A"]
    [Black "B"]
    [Result "*"]
    [ChapterName "\(name)"]

    \(movetext)
    """
}

// ------------------------------------------------------------------- URLs

@Test("a lichess study page maps to itself and its study-level .pgn export")
func lichessStudyGetsAPGNVariant() {
    let candidates = PGNImport.candidateURLs(for: "lichess.org/study/HgiqcIqW")
    #expect(
        candidates?.map(\.absoluteString)
            == [
                "https://lichess.org/study/HgiqcIqW",
                "https://lichess.org/study/HgiqcIqW.pgn",
            ]
    )
}

@Test("a chapter page and a fragment still name the study, not the chapter")
func chapterURLsFallThroughToTheWholeStudy() {
    let candidates = PGNImport.candidateURLs(
        for: "https://lichess.org/study/HgiqcIqW/0fg3fROm#12"
    )
    #expect(
        candidates?.map(\.absoluteString)
            == [
                "https://lichess.org/study/HgiqcIqW/0fg3fROm#12",
                "https://lichess.org/study/HgiqcIqW.pgn",
            ]
    )
}

@Test("a URL that is already the export is tried as it stands")
func alreadyAPGNStaysOneCandidate() {
    #expect(
        PGNImport.candidateURLs(for: "https://lichess.org/study/HgiqcIqW.pgn")?.map(\.absoluteString)
            == ["https://lichess.org/study/HgiqcIqW.pgn"]
    )
}

@Test("a non-lichess PGN link is fetched as given")
func otherSitesPassThrough() {
    #expect(
        PGNImport.candidateURLs(for: "https://example.com/games/game.pgn")?.map(\.absoluteString)
            == ["https://example.com/games/game.pgn"]
    )
}

@Test("anything that is not a link is refused up front")
func notALinkIsNil() {
    #expect(PGNImport.candidateURLs(for: "") == nil)
    #expect(PGNImport.candidateURLs(for: "not a link") == nil)
    #expect(PGNImport.candidateURLs(for: "file:///etc/passwd") == nil)
}

// --------------------------------------------------------------- splitting

@Test("a multi-game PGN splits into one parseable block per chapter")
func studySplitsPerChapter() throws {
    let blocks = PGNImport.split(twoChapterStudy)
    #expect(blocks.count == 2)
    for block in blocks {
        let pgn = try PGN(parsing: block)
        #expect(pgn.tag("ChapterName") != nil)
    }
}

@Test("chapters are found without a blank line between them")
func splitsWithoutBlankLines() throws {
    let text = """
        [Event "A"]
        [ChapterName "1"]

        1. e4 *
        [Event "A"]
        [ChapterName "2"]

        1. d4 *
        """
    let blocks = PGNImport.split(text)
    #expect(blocks.count == 2)
    #expect(try PGN(parsing: blocks[0]).tag("ChapterName") == "1")
    #expect(try PGN(parsing: blocks[1]).tag("ChapterName") == "2")
}

@Test("a chapter with no moves is still its own game")
func emptyChapterStillSplits() throws {
    let text = """
        [Event "A"]
        [ChapterName "1"]

        [Event "A"]
        [ChapterName "2"]

        1. d4 *
        """
    let blocks = PGNImport.split(text)
    #expect(blocks.count == 2)
    let empty = try PGN(parsing: blocks[0])
    #expect(empty.game.plies.isEmpty)
    #expect(empty.tag("ChapterName") == "1")
    #expect(try PGN(parsing: blocks[1]).tag("ChapterName") == "2")
}

@Test("a bracket line inside a comment or a variation never starts a new game")
func commentBracketsDoNotSplit() throws {
    let text = """
        [Event "A"]

        1. e4 {a comment
        [that starts a line with a bracket]
        it ends} e5 2. Nf3 (2. Nc3
        [%cal Gb1c3]
        2... Nc6) 2... Nc6 *
        """
    let blocks = PGNImport.split(text)
    #expect(blocks.count == 1, "the [ lines sit at depth one; they are content, not tags")
    let pgn = try PGN(parsing: blocks[0])
    #expect(pgn.game.plies.map(\.san) == ["e4", "e5", "Nf3", "Nc6"])
}

@Test("trailing newlines and whitespace-only text split into nothing")
func blankTextSplitsIntoNothing() {
    #expect(PGNImport.split("") == [])
    #expect(PGNImport.split("\n\n  \n") == [])
}

// ---------------------------------------------------------------- reading

@Test("chapters parse with their names, and the study names the collection")
func chaptersReadNames() {
    let (chapters, unreadable) = PGNImport.chapters(in: twoChapterStudy)
    #expect(chapters.map(\.name) == ["1", "2"])
    #expect(chapters.map(\.id) == [1, 2])
    #expect(unreadable == 0)
    #expect(PGNImport.suggestedCollection(for: chapters[0].pgn) == "Wood Pecker 1-47")
}

@Test("a chapter that will not parse is counted, not fatal")
func unreadableChaptersAreCounted() throws {
    // The first chapter's first move is illegal — no piece can go to e5 from the start —
    // so it cannot parse; the second is a fine game and must come through anyway.
    let text = chapter("broken", movetext: "1. e5 *") + "\n" + chapter("fine")
    let (chapters, unreadable) = PGNImport.chapters(in: text)
    #expect(chapters.map(\.name) == ["fine"])
    #expect(unreadable == 1)
}

// ------------------------------------------------------------------ naming

@Test("the chapter name chain runs ChapterName, Event, players, Date, then position")
func nameFallbackChain() throws {
    func pgn(
        chapterName: String? = nil, event: String = "?", white: String = "?",
        black: String = "?", date: String? = nil
    ) -> PGN {
        var tags: [PGN.Tag] = [
            PGN.Tag("Event", event), PGN.Tag("White", white), PGN.Tag("Black", black)
        ]
        if let chapterName { tags.append(PGN.Tag("ChapterName", chapterName)) }
        if let date { tags.append(PGN.Tag("Date", date)) }
        return PGN(game: Game(startFEN: PGN.standardStartFEN)!, tags: tags)
    }

    #expect(
        PGNImport.name(for: pgn(chapterName: "第一题"), chapter: 7) == "第一题",
        "ChapterName is the name for exactly this game"
    )
    #expect(
        PGNImport.name(for: pgn(event: "Wood Pecker"), chapter: 7) == "Wood Pecker",
        "Event names the set the game belongs to"
    )
    #expect(
        PGNImport.name(for: pgn(white: "卡尔森", black: "丁立人"), chapter: 7)
            == "卡尔森 对 丁立人"
    )
    #expect(
        PGNImport.name(for: pgn(date: "2021.03.05"), chapter: 7) == "2021.03.05",
        "with no players named, the date is what the game is"
    )
    #expect(
        PGNImport.name(for: pgn(), chapter: 7) == "第 7 章",
        "and with nothing at all, its place in the study is the one true name"
    )
}

@Test("a whole study of unknown players falls to the date rather than one shared name")
func unknownPlayersAreNotAName() throws {
    let pgn = PGN(
        game: Game(startFEN: PGN.standardStartFEN)!,
        tags: [PGN.Tag("Event", "?"), PGN.Tag("Date", "2026.01.02")]
    )
    #expect(PGNImport.name(for: pgn, chapter: 1) == "2026.01.02")
}

// ------------------------------------------------------------------- dedup

@Test("chapters a game already stands in for are skipped, inside and against the plan")
func dedupSkipsByName() {
    func chapter(_ name: String) -> PGNImport.ImportChapter {
        PGNImport.ImportChapter(
            id: 0, name: name,
            pgn: PGN(game: Game(startFEN: PGN.standardStartFEN)!, tags: [PGN.Tag("ChapterName", name)])
        )
    }

    let (kept, skipped) = PGNImport.toWrite(
        [chapter("1"), chapter("2")], avoiding: ["1"]
    )
    #expect(kept.map(\.name) == ["2"])
    #expect(skipped == 1)

    // Two chapters with one name cannot become two files that read identically.
    let (deduped, skippedTwins) = PGNImport.toWrite(
        [chapter("1"), chapter("1"), chapter("2")], avoiding: []
    )
    #expect(deduped.map(\.name) == ["1", "2"])
    #expect(skippedTwins == 1)
}

// ----------------------------------------------------------------- session

@MainActor
@Test("candidates are tried in order, and an HTML page falls through to the .pgn")
func sessionWalksCandidatesInOrder() async {
    let fetcher = ScriptedFetcher([
        "https://lichess.org/study/HgiqcIqW": .success("<!DOCTYPE html><html>a page</html>"),
        "https://lichess.org/study/HgiqcIqW.pgn": .success(twoChapterStudy),
    ])
    let session = ImportSession(fetcher: fetcher)
    await session.run("lichess.org/study/HgiqcIqW")

    #expect(
        fetcher.askedURLs.map(\.absoluteString)
            == [
                "https://lichess.org/study/HgiqcIqW",
                "https://lichess.org/study/HgiqcIqW.pgn",
            ],
        "the page itself first, its export second"
    )
    guard case .ready(let plan) = session.phase else {
        Issue.record("expected a ready plan, got \(session.phase)")
        return
    }
    #expect(plan.chapters.count == 2)
    #expect(plan.suggestedCollection == "Wood Pecker 1-47")
}

@MainActor
@Test("a lichess 403 reads as the study not being public")
func privateStudyIsNamed() async {
    let fetcher = ScriptedFetcher([
        "https://lichess.org/study/3g1TDUO0": .failure(.privateStudy),
        "https://lichess.org/study/3g1TDUO0.pgn": .failure(.privateStudy),
    ])
    let session = ImportSession(fetcher: fetcher)
    await session.run("https://lichess.org/study/3g1TDUO0")

    #expect(session.phase == .failed(.privateStudy))
}

@MainActor
@Test("when every candidate fails the last failure is the one shown")
func lastFailureWins() async {
    let fetcher = ScriptedFetcher([
        "https://example.com/game.pgn": .failure(.network("离线了"))
    ])
    let session = ImportSession(fetcher: fetcher)
    await session.run("https://example.com/game.pgn")

    #expect(session.phase == .failed(.network("离线了")))
}

@MainActor
@Test("a PGN with no readable game is not an empty success")
func noReadableGamesIsAFailure() async {
    let fetcher = ScriptedFetcher([
        "https://example.com/game.pgn": .success(chapter("broken", movetext: "1. e5 *"))
    ])
    let session = ImportSession(fetcher: fetcher)
    await session.run("https://example.com/game.pgn")

    #expect(session.phase == .failed(.noReadableGames))
}

@MainActor
@Test("input that is not a link fails before anything is fetched")
func notALinkFailsFast() async {
    let fetcher = ScriptedFetcher()
    let session = ImportSession(fetcher: fetcher)
    await session.run("not a link")

    #expect(session.phase == .failed(.notALink))
    #expect(fetcher.askedURLs.isEmpty)
}

// ------------------------------------------------------------------ apply

@MainActor
@Test("applying a plan writes one tagged file per chapter into the collection")
func applyWritesTaggedFiles() async throws {
    let tempDir = URL(filePath: NSTemporaryDirectory())
        .appending(path: "chessfen-import-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let library = GameLibrary(folder: GameFolder(url: tempDir))
    let session = ImportSession(
        fetcher: ScriptedFetcher([
            "https://lichess.org/study/HgiqcIqW.pgn": .success(twoChapterStudy)
        ])
    )
    await session.run("https://lichess.org/study/HgiqcIqW.pgn")

    let outcome = try #require(session.apply(into: "Wood Pecker", library: library))
    #expect(outcome.imported == 2)
    #expect(outcome.skipped == 0)
    #expect(outcome.unreadable == 0)

    library.reload()
    #expect(library.entries.count == 2)
    #expect(Set(library.entries.compactMap(\.name)) == ["1", "2"])
    for entry in library.entries {
        #expect(entry.collection == "Wood Pecker")
        #expect(entry.origin == .imported)
    }
}

@MainActor
@Test("importing the same study again skips every chapter already standing there")
func reimportSkipsByName() async throws {
    let tempDir = URL(filePath: NSTemporaryDirectory())
        .appending(path: "chessfen-import-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let library = GameLibrary(folder: GameFolder(url: tempDir))
    let first = ImportSession(
        fetcher: ScriptedFetcher([
            "https://lichess.org/study/HgiqcIqW.pgn": .success(twoChapterStudy)
        ])
    )
    await first.run("https://lichess.org/study/HgiqcIqW.pgn")
    _ = try #require(first.apply(into: "Wood Pecker", library: library))

    // The same study, the same door, again — and the names are what identify the games.
    let again = ImportSession(
        fetcher: ScriptedFetcher([
            "https://lichess.org/study/HgiqcIqW.pgn": .success(twoChapterStudy)
        ])
    )
    await again.run("https://lichess.org/study/HgiqcIqW.pgn")
    let outcome = try #require(again.apply(into: "Wood Pecker", library: library))
    #expect(outcome.imported == 0)
    #expect(outcome.skipped == 2)

    library.reload()
    #expect(library.entries.count == 2, "no doubles, no files added")
}

// ------------------------------------------------------------ imported games

@Test("the imported origin round-trips through the Source tag")
func importedOriginReadsBack() throws {
    let entry = GameLibrary.Entry(
        url: URL(filePath: "/games/x.pgn"),
        pgn: PGN(
            game: Game(startFEN: PGN.standardStartFEN)!,
            tags: [PGN.Tag(GameOrigin.tagName, GameOrigin.imported.tagValue)]
        ),
        modified: Date()
    )
    #expect(entry.origin == .imported)
    #expect(entry.origin.chinese == "导入")
    #expect(entry.origin.symbol == "link")

    let untagged = GameLibrary.Entry(
        url: URL(filePath: "/games/y.pgn"),
        pgn: PGN(game: Game(startFEN: PGN.standardStartFEN)!),
        modified: Date()
    )
    #expect(untagged.origin == .fresh)
}

@MainActor
@Test("an imported game played on stays in its collection")
func importedGameKeepsItsCollection() throws {
    let entry = GameLibrary.Entry(
        url: URL(filePath: "/games/x.pgn"),
        pgn: PGN(
            game: Game(startFEN: PGN.standardStartFEN)!,
            tags: [
                PGN.Tag("Event", "Wood Pecker"),
                PGN.Tag(GameOrigin.tagName, GameOrigin.imported.tagValue),
            ]
        ),
        modified: Date()
    )
    let session = try #require(GameSession.opened(entry))
    #expect(session.origin == .imported)

    let move = try #require(session.viewed.state.legalMoves.first)
    session.play(move)
    #expect(session.pgn.tag("Event") == "Wood Pecker", "a played-on game must not leave its set")
    #expect(session.pgn.tag(GameOrigin.tagName) == "imported")
}
