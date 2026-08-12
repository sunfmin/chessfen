import ChessfenKit
import Foundation

// A desktop entry point for the same engine and (later) the same recogniser the app runs,
// so a doubt can be settled with a shell command instead of a simulator. Grows in step
// with the package; today it can vet a FEN and count moves.

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("chessfen-cli: \(message)\n".utf8))
    exit(1)
}

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

default:
    fail("usage: chessfen-cli <validate|perft> ...")
}
