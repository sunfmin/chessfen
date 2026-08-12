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

        var title: String {
            guard let pgn else { return url.deletingPathExtension().lastPathComponent }
            let white = pgn.tag("White") ?? "白方"
            let black = pgn.tag("Black") ?? "黑方"
            return "\(white) — \(black)"
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
}
