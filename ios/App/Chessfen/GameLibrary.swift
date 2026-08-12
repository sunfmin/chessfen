import ChessfenKit
import Foundation

/// The games on disk, which is to say a folder of PGN files (docs/adr/0010).
///
/// There is no database and no model layer: a Game is its PGN text, the library is the
/// directory listing, and anything that can read a PGN can read everything this app has
/// ever saved. The cost is re-parsing on launch, which for text files of a few kilobytes
/// is not a cost.
@Observable final class GameLibrary {
    struct Entry: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
        /// Nil when the file is there but will not parse — listed rather than hidden,
        /// because a file the app cannot read is exactly what a person needs to be told.
        var pgn: PGN?
        var modified: Date

        /// Whether this game came off a picture. Written into the PGN when it was saved, so
        /// it survives a relaunch and reads correctly in the list.
        var origin: GameOrigin {
            GameOrigin(rawValue: pgn?.tag(GameOrigin.tagName) ?? "") ?? .fresh
        }

        /// What this game is called, if anybody has said. Its own tag rather than `Event`, which
        /// names the collection: PGN has no tag for the name of a single game, and the precedent
        /// for adding one is `Source` — a reader that does not know it ignores it.
        var name: String? {
            pgn?.tag(GameLibrary.nameTag).flatMap { $0.isEmpty ? nil : $0 }
        }

        /// The collection this game is filed under, or nil for one that is not filed.
        ///
        /// `Event` is where PGN already puts "which set of games this belongs to", so a collection
        /// made here is a collection anywhere else the file is opened. Every game the app has ever
        /// written has `Event "Chessfen"`, which is the app's name and not a collection's, so that
        /// value reads as unfiled — along with the two ways PGN says it does not know. This is what
        /// makes existing games need no migration.
        var collection: String? {
            guard let event = pgn?.tag("Event"), !GameLibrary.unfiledEvents.contains(event) else {
                return nil
            }
            return event
        }

        /// The name to show, which is the given one or one made from when the game was saved. Never
        /// a shared placeholder: rows that all read "未命名" cannot be told apart or sorted.
        var title: String {
            if let name { return name }
            return GameLibrary.fallbackName(for: url)
        }

        var detail: String {
            guard let pgn else { return "无法读取" }
            let date = pgn.tag("Date") ?? ""
            let result = pgn.game.resultToken
            let moves = (pgn.game.plies.count + 1) / 2
            var parts = ["\(origin.chinese)", date, "\(moves) 回合"]
            parts.append(result == "*" ? "未结束" : result)
            let branches = pgn.game.plies.reduce(0) { $0 + $1.variations.count }
            if branches > 0 { parts.append("\(branches) 条分叉") }
            return parts.joined(separator: " · ")
        }
    }

    private(set) var entries: [Entry] = []

    /// The tag a game's own name lives in.
    static let nameTag = "Name"

    /// `Event` values that mean "not in a collection": the app's own name, which is what it wrote
    /// into every game before collections existed, and PGN's two ways of saying it does not know.
    static let unfiledEvents: Set<String> = ["Chessfen", "?", ""]

    /// One collection and the games in it, in the order they should be read and drilled.
    struct Collection: Identifiable {
        /// Nil for the games nobody has filed.
        let name: String?
        let entries: [Entry]
        var id: String { name ?? "" }
    }

    /// The library as collections, named ones first and 未归类 last.
    ///
    /// Within a collection the order is by name, compared the way a person reads numbers, so 第 2 题
    /// comes before 第 10 题 rather than after it. That order is the one 上一局 and 下一局 follow, so
    /// naming the games is how the drilling order is set.
    var collections: [Collection] {
        let grouped = Dictionary(grouping: entries) { $0.collection }
        let named = grouped.keys.compactMap { $0 }.sorted { Self.reads($0, before: $1) }
        var out = named.map { name in
            Collection(name: name, entries: sortedByName(grouped[name] ?? []))
        }
        if let unfiled = grouped[nil], !unfiled.isEmpty {
            // Left in the order the flat list had — most recently touched first. Nobody has said
            // anything about how these relate to each other, so the useful order is "what I was
            // just doing", not an alphabetical one over names nobody chose.
            out.append(Collection(name: nil, entries: unfiled))
        }
        return out
    }

    /// The names of the collections that exist, for anywhere one has to be chosen.
    var collectionNames: [String] {
        collections.compactMap(\.name)
    }

    func sortedByName(_ list: [Entry]) -> [Entry] {
        list.sorted { Self.reads($0.title, before: $1.title) }
    }

    /// Numeric-aware, locale-aware, and case-insensitive — `localizedStandardCompare` is the same
    /// comparison the Files app sorts by, which is the one a person expects to see.
    static func reads(_ left: String, before right: String) -> Bool {
        left.localizedStandardCompare(right) == .orderedAscending
    }

    /// A name for a game nobody has named: when it was saved, read out of its own file name. Unique
    /// per game and sorts chronologically, which is what the flat list used to give for free.
    static func fallbackName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let stamp = stem.hasPrefix("chessfen-") ? String(stem.dropFirst("chessfen-".count)) : stem
        guard let date = stampFormatter.date(from: stamp) else { return stem }
        return readableFormatter.string(from: date)
    }

    // ------------------------------------------------------------------ naming

    /// Renames a game, or takes its name away again with nil.
    @discardableResult
    func rename(_ entry: Entry, to name: String?) -> Bool {
        write(tag: Self.nameTag, value: name, on: entry)
    }

    /// Files a game under a collection, or takes it out of one with nil.
    @discardableResult
    func file(_ entry: Entry, under collection: String?) -> Bool {
        // Unfiled is written as the app's own name rather than removed, because `Event` is a tag
        // every PGN reader expects to find and this is the value everything else here already has.
        write(tag: "Event", value: collection ?? "Chessfen", on: entry)
    }

    /// Renames a whole collection, which is renaming the tag on every game in it. There is no
    /// record of a collection apart from the games that claim it, so an empty one cannot exist and
    /// renaming cannot half-happen in a way that leaves one behind.
    func renameCollection(_ name: String, to fresh: String) {
        for entry in entries where entry.collection == name {
            file(entry, under: fresh)
        }
    }

    /// Rewrites one tag of a game on disk.
    ///
    /// Through the PGN rather than around it: the file is the game (docs/adr/0010), so renaming is
    /// re-writing the file with one tag changed, and there is no second place a name could disagree
    /// with. A game with no readable PGN cannot be renamed, which is the honest answer — there is
    /// nothing there to put a name in.
    private func write(tag: String, value: String?, on entry: Entry) -> Bool {
        guard var pgn = entry.pgn else { return false }
        pgn.setTag(tag, to: value)
        return write(pgn, to: entry.url)
    }

    static let directory: URL = {
        let documents = URL.documentsDirectory.appending(path: "Games", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents
    }()

    init() {
        reload()
    }

    func reload() {
        let manager = FileManager.default
        let urls =
            (try? manager.contentsOfDirectory(
                at: Self.directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

        entries = urls
            .filter { $0.pathExtension.lowercased() == "pgn" }
            .map { url in
                let text = try? String(contentsOf: url, encoding: .utf8)
                let modified =
                    (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? .distantPast
                return Entry(
                    url: url,
                    pgn: text.flatMap { try? PGN(parsing: $0) },
                    modified: modified
                )
            }
            .sorted { $0.modified > $1.modified }
    }

    /// A file name that reads as what it is in any file browser, and sorts by when it was
    /// played.
    func newURL(now: Date = Date()) -> URL {
        let stamp = Self.stampFormatter.string(from: now)
        var url = Self.directory.appending(path: "chessfen-\(stamp).pgn")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = Self.directory.appending(path: "chessfen-\(stamp)-\(suffix).pgn")
            suffix += 1
        }
        return url
    }

    @discardableResult
    func write(_ pgn: PGN, to url: URL) -> Bool {
        guard let data = pgn.text.data(using: .utf8) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            refreshEntry(at: url, with: pgn)
            return true
        } catch {
            return false
        }
    }

    func delete(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
        try? FileManager.default.removeItem(at: Self.pictureURL(for: entry.url))
        entries.removeAll { $0.url == entry.url }
    }

    // ---------------------------------------------------------------- pictures

    /// The photograph a recognised game was read from, stored beside its PGN under the same
    /// name. A sidecar rather than something embedded: the PGN stays a PGN that any other
    /// program can read, and a game that loses its picture still opens.
    static func pictureURL(for game: URL) -> URL {
        game.deletingPathExtension().appendingPathExtension("png")
    }

    func writePicture(_ image: RGBImage, for game: URL) {
        guard let data = image.pngData else { return }
        try? data.write(to: Self.pictureURL(for: game), options: .atomic)
    }

    func picture(for game: URL) -> RGBImage? {
        RGBImage(contentsOf: Self.pictureURL(for: game))
    }

    /// Updates one row in place rather than re-reading the folder, so that autosaving after
    /// every move does not turn into a directory scan after every move.
    private func refreshEntry(at url: URL, with pgn: PGN) {
        let entry = Entry(url: url, pgn: pgn, modified: Date())
        if let index = entries.firstIndex(where: { $0.url == url }) {
            entries[index] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        entries.sort { $0.modified > $1.modified }
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    /// The same instant as something to read in a list.
    private static let readableFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}
