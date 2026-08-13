import Foundation

/// The one way a PGN link becomes games in the library, whichever door it came in
/// through (docs/adr/0014).
///
/// A link — a lichess study page is the canonical case — is downloaded, the multi-game
/// PGN split into one block per chapter, and each chapter becomes one file in the
/// library, tagged into a collection. The pure reading lives here as a caseless enum
/// and the one thing with state — where the download has got to — is `ImportSession`,
/// the same split `BoardIntake` and `GameSession` use.
public enum PGNImport {
    // ---------------------------------------------------------------- errors

    /// What went wrong, one case per way an import can die. The wording of a failure
    /// follows from the case rather than from the call site, so every door shows the
    /// same message for the same failure (`BoardIntake.Intake.alert` convention).
    public enum Error: Swift.Error, Hashable, Sendable {
        /// The input is not a link at all.
        case notALink
        /// The server says this study is not public. Private and unlisted studies
        /// answer 403 to anyone who is not a member, and v1 only imports public ones.
        case privateStudy
        /// The link downloaded, but what came down is not a PGN.
        case notPGN
        /// It is a PGN, but not one game in it parses.
        case noReadableGames
        /// The server answered with an HTTP status that means no.
        case http(Int)
        /// The network itself failed.
        case network(String)

        public var alert: (title: String, message: String) {
            switch self {
            case .notALink:
                ("不是链接", "这里要的是一个网址,比如一个公开的 lichess 研究链接。")
            case .privateStudy:
                ("这个棋谱不公开", "它没有对外公开,所以下载不下来。目前只能导入公开的棋谱。")
            case .notPGN:
                ("不是棋谱", "这个链接下载下来的内容不是 PGN 棋谱。")
            case .noReadableGames:
                ("没有能读出来的棋局", "下载下来的棋谱里,没有一局能读出来。")
            case .http(let code):
                ("下载失败", "服务器回了一个 HTTP \(code)。")
            case .network(let detail):
                ("网络不通", "下载的时候网络出错了:\(detail)")
            }
        }
    }

    // ------------------------------------------------------------- fetching

    /// One game downloaded and read, written under its chapter's name.
    public struct ImportChapter: Hashable, Sendable, Identifiable {
        /// Position in the study, one-based — the last-resort name falls back on it.
        public let id: Int
        public let name: String
        public let pgn: PGN

        public init(id: Int, name: String, pgn: PGN) {
            self.id = id
            self.name = name
            self.pgn = pgn
        }
    }

    /// Everything the download found, ready to be applied.
    public struct ImportPlan: Hashable, Sendable {
        /// The collection the games suggest for themselves: the lichess `StudyName`,
        /// or the `Event` a single-game PGN names itself after.
        public let suggestedCollection: String?
        public let chapters: [ImportChapter]
        /// Chapters that were there but would not parse. Counted rather than fatal —
        /// one broken chapter must not take the whole study down, and the count is
        /// the report (`GameLibrary.Entry` lists unreadable files for the same reason).
        public let unreadable: Int

        public init(suggestedCollection: String?, chapters: [ImportChapter], unreadable: Int) {
            self.suggestedCollection = suggestedCollection
            self.chapters = chapters
            self.unreadable = unreadable
        }
    }

    /// What applying a plan did, once it is a matter of record.
    public struct ImportOutcome: Hashable, Sendable {
        public let collection: String
        public let imported: Int
        /// Chapters skipped because a game of that name was already in the collection.
        public let skipped: Int
        public let unreadable: Int

        public init(collection: String, imported: Int, skipped: Int, unreadable: Int) {
            self.collection = collection
            self.imported = imported
            self.skipped = skipped
            self.unreadable = unreadable
        }

        /// The one sentence the screen shows. Each clause only when it happened — a
        /// clean import should say one thing and stop.
        public var message: String {
            var parts = ["导入 \(imported) 局到「\(collection)」"]
            if skipped > 0 { parts.append("跳过 \(skipped) 局已有的") }
            if unreadable > 0 { parts.append("另有 \(unreadable) 局没能读出来") }
            return parts.joined(separator: ",") + "。"
        }
    }

    // ------------------------------------------------------------ candidates

    /// The URLs to try, in order, for a pasted link.
    ///
    /// Nil for input that is not a link at all. A lichess study page exports its whole
    /// study one suffix away — the site URL plus `.pgn` is the documented endpoint —
    /// so a study URL that is not already the export gets two candidates: itself
    /// (which works when it is already a PGN wearing a study's URL, e.g. a chapter
    /// export) and the study-level `.pgn`, which is what actually holds every chapter.
    /// A chapter *page* URL falls through its HTML to the study export, which is what
    /// pasting a chapter link out of a browser should do: import the whole study.
    ///
    /// The scheme is added when a paste drops it, because "lichess.org/study/x" is
    /// what a person copies and it is not this function's business to make them type
    /// `https://`.
    public static func candidateURLs(for input: String) -> [URL]? {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "https://" + raw }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme), url.host != nil
        else { return nil }
        guard let studyID = lichessStudyID(from: url) else { return [url] }
        return [url, URL(string: "https://lichess.org/study/\(studyID).pgn")!]
    }

    /// The study a lichess URL names, nil for anything else or for a URL that is
    /// already an export. The study id is the first path component after `/study/`;
    /// anything after it is a chapter, and anything before the study id is a
    /// different page.
    private static func lichessStudyID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
            host == "lichess.org" || host.hasSuffix(".lichess.org")
        else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 3, parts[1] == "study", !parts[2].isEmpty else { return nil }
        let studyID = parts[2]
        guard !studyID.hasSuffix(".pgn") else { return nil }
        return studyID
    }

    // -------------------------------------------------------------- splitting

    /// One block per game in a multi-game PGN, each kept byte-for-byte so the
    /// single-game parser can have it whole.
    ///
    /// The split point is a tag line — a line starting `[` — that comes after the
    /// current game's tags have ended. Two things end them: movetext, which is every
    /// non-tag line, and a blank line following the tags (a chapter with no moves is
    /// just tags, then the next chapter's tags). A `[` inside a comment or a
    /// variation must never split: `{[%cal …]}` keeps its brackets, so the `()` and
    /// `{}` depths are tracked and only a `[` at depth zero can start a game.
    /// Blank lines are kept — they are the whitespace the parser already skips — but
    /// blocks that end up empty are dropped.
    public static func split(_ text: String) -> [String] {
        var blocks: [String] = []
        var current: [String] = []
        var seenTag = false
        var tagsClosed = false
        var hasMovetext = false
        var parens = 0
        var braces = 0

        func closeBlock() {
            let block = current.joined(separator: "\n")
            if !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(block)
            }
            current = []
            seenTag = false
            tagsClosed = false
            hasMovetext = false
            parens = 0
            braces = 0
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                if seenTag { tagsClosed = true }
                current.append(String(rawLine))
                continue
            }
            if line.first == "[", parens == 0, braces == 0, hasMovetext || tagsClosed {
                closeBlock()
            }
            // Depth first or after the split test? Before: the `(` of this line is
            // this game's, and a `[` deeper into the line is this game's too.
            let effects = bracketEffects(in: line)
            parens += effects.parens
            braces += effects.braces
            if line.first == "[" {
                seenTag = true
            } else {
                hasMovetext = true
            }
            current.append(String(rawLine))
        }
        closeBlock()
        return blocks
    }

    /// How a line changes the `()` and `{}` depths, which is all the splitter needs
    /// to know about it.
    ///
    /// Quote- and comment-aware, because both happily contain the brackets that would
    /// fool it: a tag value like `[White "De La Bourdonnais (1834)"]` must not open a
    /// variation, and a comment is where lichess puts arrows — `{[%cal Gd2d4]}` — so
    /// everything inside `{…}` is dead to the counters except the closing brace.
    private static func bracketEffects(in line: String) -> (parens: Int, braces: Int) {
        var parens = 0
        var braces = 0
        var inQuotes = false
        var previous: Character?
        for character in line {
            if braces > 0 {
                if character == "}" { braces -= 1 }
            } else if inQuotes {
                if character == "\"", previous != "\\" { inQuotes = false }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case "(":
                    parens += 1
                case ")":
                    parens -= 1
                case "{":
                    braces += 1
                case "}":
                    braces -= 1
                default:
                    break
                }
            }
            previous = character
        }
        return (parens, braces)
    }

    // --------------------------------------------------------------- reading

    /// Every game in a multi-game PGN, parsed, with the chapters that would not
    /// parse counted alongside (`ImportPlan.unreadable`).
    public static func chapters(in text: String) -> (chapters: [ImportChapter], unreadable: Int) {
        var chapters: [ImportChapter] = []
        var unreadable = 0
        for (index, block) in split(text).enumerated() {
            guard let pgn = try? PGN(parsing: block) else {
                unreadable += 1
                continue
            }
            chapters.append(
                ImportChapter(id: index + 1, name: name(for: pgn, chapter: index + 1), pgn: pgn)
            )
        }
        return (chapters, unreadable)
    }

    /// The name one chapter is written under — what the list shows and what dedup
    /// runs on. Never empty and never a shared placeholder: rows that all read the
    /// same cannot be told apart, and a dedup that cannot tell them apart skips
    /// chapters that are not duplicates.
    ///
    /// Each step only when it says something: `ChapterName` is the lichess name for
    /// exactly this; `Event` names the study the chapter belongs to; the players are
    /// only a name when at least one of them is known (a whole study of `? 对 ?`
    /// would dedup into one game); `Date` skips PGN's `????.??.??`. Whatever is
    /// left, the chapter's position in the study is its name — "第 N 章" is true
    /// even when nothing else is.
    public static func name(for pgn: PGN, chapter ordinal: Int) -> String {
        if let chapterName = pgn.tag("ChapterName"), !chapterName.isEmpty { return chapterName }
        if let event = pgn.tag("Event"), !event.isEmpty,
            !GameLibrary.unfiledEvents.contains(event)
        {
            return event
        }
        let white = pgn.tag("White") ?? "?"
        let black = pgn.tag("Black") ?? "?"
        if white != "?" || black != "?" { return "\(white) 对 \(black)" }
        if let date = pgn.tag("Date"), !date.isEmpty, date != "????.??.??" { return date }
        return "第 \(ordinal) 章"
    }

    /// The collection a plan suggests for itself: the lichess `StudyName`, or the
    /// `Event` a standalone PGN already names itself after. Nil when neither is a
    /// name worth keeping, and the person says.
    public static func suggestedCollection(for pgn: PGN) -> String? {
        if let studyName = pgn.tag("StudyName"), !studyName.isEmpty { return studyName }
        if let event = pgn.tag("Event"), !event.isEmpty,
            !GameLibrary.unfiledEvents.contains(event)
        {
            return event
        }
        return nil
    }

    // -------------------------------------------------------------- applying

    /// The chapters to write, minus any a game of that name is already standing in
    /// for in the target collection.
    ///
    /// The name is the identity: importing the same study again must not double it,
    /// and a chapter twice over inside one study — lichess lets chapters share a
    /// name — cannot produce two files that read identically. Skipped rather than
    /// renamed, because two chapters with one name have to be told apart by the
    /// person who owns them, and the report says how many were skipped.
    public static func toWrite(
        _ chapters: [ImportChapter], avoiding existing: Set<String>
    ) -> (chapters: [ImportChapter], skipped: Int) {
        var taken = existing
        var kept: [ImportChapter] = []
        var skipped = 0
        for chapter in chapters {
            guard taken.insert(chapter.name).inserted else {
                skipped += 1
                continue
            }
            kept.append(chapter)
        }
        return (kept, skipped)
    }
}

// ------------------------------------------------------------------ fetching

/// Downloads one URL into its text. A protocol rather than a straight call because
/// it is the one thing in an import that cannot be asked twice for the same answer —
/// the network is out there, and tests need a scripted one (`ScriptedEngine`
/// convention).
public protocol PGNFetching: Sendable {
    func fetch(_ url: URL) async throws -> String
}

/// The real fetcher. A `URLSession` call, no state, safe from anywhere.
///
/// The failures are translated into `PGNImport.Error` cases here rather than at each
/// call site: a 403 from lichess *is* the private-study story, and a download that
/// will not decode as UTF-8 was never a PGN.
public struct URLSessionPGNFetcher: PGNFetching, Sendable {
    public init() {}

    public func fetch(_ url: URL) async throws -> String {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            throw PGNImport.Error.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PGNImport.Error.network("不是 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 403, url.host?.lowercased().hasSuffix("lichess.org") == true {
                throw PGNImport.Error.privateStudy
            }
            throw PGNImport.Error.http(http.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw PGNImport.Error.notPGN
        }
        return text
    }
}

// ------------------------------------------------------------------ session

/// One import, from a pasted link to games on disk. The state is the phase; the
/// reading happens off the main thread and comes back as a `PGNImport.ImportPlan`,
/// which is when it stops being about the network and starts being about the library.
@Observable @MainActor public final class ImportSession {
    public enum Phase: Equatable, Sendable {
        case idle
        case fetching
        case ready(PGNImport.ImportPlan)
        case importing
        case done(PGNImport.ImportOutcome)
        case failed(PGNImport.Error)
    }

    public private(set) var phase: Phase = .idle

    private let fetcher: any PGNFetching

    public init(fetcher: any PGNFetching = URLSessionPGNFetcher()) {
        self.fetcher = fetcher
    }

    /// Downloads the link and reads what comes down.
    ///
    /// The candidates are tried in order — the study's `.pgn` variant is what a page
    /// link falls through to — and a candidate that downloads but yields no readable
    /// game fails the way a fetch does: an HTML page is not the wrong answer to stop
    /// at when the same URL plus `.pgn` is the right one. The last failure is the
    /// one shown, because it is the one that would have succeeded.
    public func run(_ input: String) async {
        guard let candidates = PGNImport.candidateURLs(for: input) else {
            phase = .failed(.notALink)
            return
        }
        phase = .fetching
        let fetching = fetcher
        phase = await Task.detached(priority: .userInitiated) { () -> Phase in
            var lastError: PGNImport.Error = .notPGN
            for candidate in candidates {
                let text: String
                do {
                    text = try await fetching.fetch(candidate)
                } catch let failure as PGNImport.Error {
                    lastError = failure
                    continue
                } catch {
                    lastError = .network(error.localizedDescription)
                    continue
                }
                let (chapters, unreadable) = PGNImport.chapters(in: text)
                guard let first = chapters.first else {
                    lastError = unreadable > 0 ? .noReadableGames : .notPGN
                    continue
                }
                return .ready(
                    PGNImport.ImportPlan(
                        suggestedCollection: PGNImport.suggestedCollection(for: first.pgn),
                        chapters: chapters,
                        unreadable: unreadable
                    )
                )
            }
            return .failed(lastError)
        }.value
    }

    /// Writes the plan's chapters into the library, one file per game, under the
    /// given collection — the same write path a game played by hand takes
    /// (`GameLibrary.write`), so an imported game is a game like any other.
    ///
    /// Synchronous because it is file writes, which are fast and belong where the
    /// library already is; the download was the part worth taking off the main
    /// thread.
    @discardableResult
    public func apply(into collection: String, library: GameLibrary) -> PGNImport.ImportOutcome? {
        guard case let .ready(plan) = phase else { return nil }
        phase = .importing
        let existing = Set(
            library.entries.compactMap { entry in
                entry.collection == collection ? entry.name : nil
            }
        )
        let (chapters, skipped) = PGNImport.toWrite(plan.chapters, avoiding: existing)
        var imported = 0
        for chapter in chapters {
            var pgn = chapter.pgn
            pgn.setTag("Event", to: collection)
            pgn.setTag(GameLibrary.nameTag, to: chapter.name)
            pgn.setTag(GameOrigin.tagName, to: GameOrigin.imported.tagValue)
            // A fresh name per chapter, asked right before the write so two chapters
            // landing in one second cannot collide (`GameLibrary.newURL` logic).
            let url = library.newURL()
            if library.write(pgn, to: url) { imported += 1 }
        }
        let outcome = PGNImport.ImportOutcome(
            collection: collection, imported: imported, skipped: skipped,
            unreadable: plan.unreadable
        )
        phase = .done(outcome)
        return outcome
    }

    /// Back to a blank slate, for the "再导入一个" that follows a done import.
    public func reset() {
        phase = .idle
    }
}
