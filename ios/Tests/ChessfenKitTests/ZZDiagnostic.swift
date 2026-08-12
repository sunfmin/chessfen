@testable import ChessfenKit
import Foundation
import Testing

@Test("diagnostic: per-cell body luma")
func diagnosticBodyLuma() throws {
    let url = URL(filePath: ProcessInfo.processInfo.environment["DIAG_IMAGE"] ?? "")
    guard let source = RGBImage(contentsOf: url) else { return }
    let image = source.scaled(toLongestSide: Recognizer.workingResolution)
    let rect = try BoardGeometry.findBoard(in: image)
    print("rect \(rect.left),\(rect.top) size \(rect.size)")
    for row in 0..<8 {
        var line: [String] = []
        for column in 0..<8 {
            let cell = rect.crop(image, row: row, column: column)
            let reading = SquareReader.read(cell)
            let verdict = SquareClassifier.classify(reading)
            let glyph = verdict.piece.map { String($0.glyph) } ?? "."
            let luma = reading.bodyLuma.map { String(format: "%5.1f", $0) } ?? "    -"
            let bg = 0.299 * reading.background.red + 0.587 * reading.background.green
                + 0.114 * reading.background.blue
            line.append("\(glyph)\(luma)/\(String(format: "%5.1f", bg))")
        }
        print("row \(row): " + line.joined(separator: " "))
    }
}
