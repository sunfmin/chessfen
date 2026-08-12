import ChessfenKit
import Foundation

// A desktop entry point for the same recogniser and the same engine the app runs, so a doubt
// can be settled with a shell command instead of a simulator — and so the Swift reading of a
// picture can be diffed against the Python one it was ported from.

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("chessfen-cli: \(message)\n".utf8))
    exit(1)
}

/// Where the NNUE weights are. They are 112 MiB and live in the repository, not in this
/// binary. A developer tool may reasonably know where the repository it was built from is;
/// anyone moving things about can say so.
let netsDirectory =
    ProcessInfo.processInfo.environment["CHESSFEN_NETS"].map { URL(filePath: $0) }
    ?? URL(filePath: #filePath)  // Sources/chessfen-cli/main.swift
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Resources/Nets")

switch arguments.first {
case "validate":
    guard arguments.count >= 2 else { fail("usage: chessfen-cli validate <fen>") }
    let verdict = Rules.validate(fen: arguments[1])
    if let issue = verdict.issue {
        let where_ = verdict.squares.map(\.description).joined(separator: " ")
        fail("\(issue)\(verdict.colour.map { " (\($0))" } ?? "")\(where_.isEmpty ? "" : " at \(where_)")")
    }
    print("ok")

case "perft":
    guard arguments.count >= 3, let depth = Int(arguments[2]) else {
        fail("usage: chessfen-cli perft <fen> <depth>")
    }
    print(Rules.perft(fen: arguments[1], depth: depth))

case "analyse":
    guard arguments.count >= 2 else {
        fail("usage: chessfen-cli analyse <fen> [depth]  (default 20)")
    }
    guard let game = Game(startFEN: arguments[1]) else { fail("not a position I can play from") }
    let depth = arguments.count >= 3 ? Int(arguments[2]) ?? 20 : 20

    // The weights are 112 MiB and live in the repository, not in this binary. A developer
    // tool may reasonably know where the repository it was built from is; anyone moving
    // things about can say so.
    let nets = ProcessInfo.processInfo.environment["CHESSFEN_NETS"].map { URL(filePath: $0) }
        ?? URL(filePath: #filePath)  // Sources/chessfen-cli/main.swift
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Resources/Nets")

    let service: EngineService
    do {
        service = try EngineService(
            bigNetURL: nets.appending(path: "nn-c288c895ea92.nnue"),
            smallNetURL: nets.appending(path: "nn-37f18f62d772.nnue")
        )
    } catch {
        fail("\(error) — looked in \(nets.path); set CHESSFEN_NETS to point elsewhere")
    }

    for await analysis in service.analyse(game, budget: .depth(depth)) {
        let speed = analysis.nodesPerSecond / 1000
        print("depth \(analysis.depth)/\(analysis.selectiveDepth)  \(speed)k nps", terminator: "")
        print("  \(analysis.nodes) nodes  \(analysis.timeMilliseconds) ms")
        for (index, line) in analysis.lines.enumerated() {
            print("  \(index + 1). \(line.score)  \(line.san.prefix(8).joined(separator: " "))")
        }
    }

case "icon":
    guard arguments.count >= 2 else {
        fail("usage: chessfen-cli icon <out.png> [side]  (default 1024)")
    }
    let side = arguments.count >= 3 ? Int(arguments[2]) ?? 1024 : 1024
    guard AppIconArt.write(to: URL(filePath: arguments[1]), side: side) else {
        fail("could not write \(arguments[1])")
    }
    print("wrote \(arguments[1]) at \(side)×\(side)")

default:
    fail("usage: chessfen-cli <validate|perft|analyse|icon> ...")
}
