// swift-tools-version: 6.2
import PackageDescription

// The define set the Stockfish Makefile uses for ARCH=apple-silicon, minus dotprod:
// -DUSE_NEON_DOTPROD needs -march=armv8.2-a+dotprod, which SwiftPM only accepts as an
// unsafe flag. The baseline is proven first; see ios/README.md.
let stockfishDefines: [CXXSetting] = [
    .define("NDEBUG"),
    .define("IS_64BIT"),
    .define("USE_PREFETCH"),
    .define("USE_POPCNT"),
    .define("USE_PTHREADS"),
    .define("USE_NEON", to: "8"),
    // The NNUE networks ship as bundle resources and are loaded by path, so incbin's
    // assembly embedding never has to work under Xcode.
    .define("NNUE_EMBEDDING_OFF"),
]

let package = Package(
    name: "chessfen",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "ChessfenKit", targets: ["ChessfenKit"]),
        .executable(name: "chessfen-cli", targets: ["chessfen-cli"]),
    ],
    targets: [
        .target(
            name: "CStockfish",
            exclude: [
                "stockfish/VENDORED.txt",
                "stockfish/incbin/UNLICENCE",
            ],
            publicHeadersPath: "include",
            cxxSettings: stockfishDefines
        ),
        .target(name: "ChessfenKit", dependencies: ["CStockfish"]),
        .executableTarget(name: "chessfen-cli", dependencies: ["ChessfenKit"]),
        .testTarget(
            name: "ChessfenKitTests",
            dependencies: ["ChessfenKit"],
            // A real screenshot of a real board: a different piece set, inline
            // coordinates, a highlighted square. Nothing rendered here can stand in
            // for it.
            resources: [.copy("Resources/reference_board.png")]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
