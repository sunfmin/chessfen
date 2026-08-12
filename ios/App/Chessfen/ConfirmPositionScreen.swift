import ChessfenKit
import SwiftUI
import UIKit

/// A position on its way to the editor.
struct PositionProposal: Identifiable, Hashable {
    let id = UUID()
    var draft: PositionDraft
    /// The Shaky Squares — where the classifier was not confident.
    var shaky: Set<Square> = []
    var orientation: Orientation = .whiteAtBottom
    /// The picture it was read from, so the player can check it against the board.
    var picture: RGBImage?
    var origin: GameOrigin = .recognised
    var controllers: [PieceColour: Controller] = [.white: .hand, .black: .hand]
    /// The game this came out of, when it came out of one. A correction goes back into that same
    /// game if nothing has been played in it yet.
    var reopening: GameSession?

    init(reopening session: GameSession) {
        draft = PositionDraft(fen: session.game.startFEN) ?? PositionDraft(pieces: [:])
        shaky = session.shaky
        orientation = session.orientation
        picture = session.picture
        origin = session.origin
        controllers = [
            .white: session.controller(for: .white), .black: session.controller(for: .black),
        ]
        reopening = session
    }

    init(
        draft: PositionDraft,
        shaky: Set<Square> = [],
        orientation: Orientation = .whiteAtBottom,
        picture: RGBImage? = nil,
        origin: GameOrigin = .recognised,
        controllers: [PieceColour: Controller] = [.white: .hand, .black: .hand]
    ) {
        self.draft = draft
        self.shaky = shaky
        self.orientation = orientation
        self.picture = picture
        self.origin = origin
        self.controllers = controllers
    }

    // Identity, not contents: the draft is edited here and the navigation stack must not treat
    // an edited proposal as a different destination.
    static func == (left: PositionProposal, right: PositionProposal) -> Bool {
        left.id == right.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The piece editor: put the pieces where they actually are.
///
/// This used to be a gate every recognised board had to pass through. It is now the place you go
/// when something is wrong (docs/adr/0011), and it does one thing. Whose move it is, which way up
/// the board is and who plays each side are all on the game screen, permanently — so they are not
/// here. What is left is a board, a box of pieces, and a way back.
struct ConfirmPositionScreen: View {
    let proposal: PositionProposal
    @Binding var path: [Step]

    @Environment(EngineHost.self) private var engine
    @Environment(GameLibrary.self) private var library

    @State private var draft: PositionDraft
    /// The piece taps place. Nil means taps do nothing, which is where this starts: a board that
    /// changed under a stray finger would undo the point of the screen.
    @State private var brush: Brush?
    @State private var isPictureShowing = false
    @State private var isAdvancedShowing = false

    enum Brush: Hashable {
        case piece(Piece)
        case eraser
    }

    private static let kinds: [PieceKind] = [.king, .queen, .rook, .bishop, .knight, .pawn]

    init(proposal: PositionProposal, path: Binding<[Step]>) {
        self.proposal = proposal
        _path = path
        _draft = State(initialValue: proposal.draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            instruction
            board
            palette
            Spacer(minLength: 0)
            if isAdvancedShowing { advanced }
            done
        }
        .background(Palette.parchment)
        .navigationTitle("改棋子")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.parchment, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(Palette.analysis)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if proposal.picture != nil {
                        Button {
                            isPictureShowing = true
                        } label: {
                            Label("看照片", systemImage: "photo")
                        }
                    }
                    Button {
                        isAdvancedShowing.toggle()
                    } label: {
                        Label(
                            isAdvancedShowing ? "收起易位和吃过路兵" : "易位和吃过路兵",
                            systemImage: "slider.horizontal.3"
                        )
                    }
                    Button {
                        UIPasteboard.general.string = draft.fen
                    } label: {
                        Label("复制 FEN", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button {
                        draft.reset()
                    } label: {
                        Label("摆成开局", systemImage: "arrow.counterclockwise")
                    }
                    Button(role: .destructive) {
                        draft.clear()
                    } label: {
                        Label("清空棋盘", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isPictureShowing) {
            if let picture = proposal.picture, let image = Image(rgb: picture) {
                NavigationStack {
                    image
                        .resizable()
                        .scaledToFit()
                        .navigationTitle("照片")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    // ------------------------------------------------------------------ parts

    private var instruction: some View {
        HStack(spacing: 8) {
            if !proposal.shaky.isEmpty {
                Image(systemName: "questionmark.circle").foregroundStyle(Palette.alarm)
                Text("橙框那 \(proposal.shaky.count) 个格子拿不太准")
                    .font(.footnote)
                    .foregroundStyle(Palette.alarm)
            } else {
                Text(brush == nil ? "先选一个棋子，再点格子" : "点格子放下，点同一格拿走")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .padding(.horizontal, 16)
    }

    private var board: some View {
        BoardView(
            pieces: draft.pieces,
            // The board's orientation is the game's, and it is set there. Turning it here would
            // be a second place to change one thing.
            orientation: proposal.orientation,
            suspects: proposal.shaky,
            coordinates: true,
            onTap: paint
        )
        .padding(.horizontal, 16)
    }

    /// The box of pieces: white above, black below, all twelve visible at once. A scroller put
    /// the piece you wanted off the side of the screen about half the time.
    private var palette: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 6) {
                ForEach([PieceColour.white, .black], id: \.self) { colour in
                    HStack(spacing: 6) {
                        ForEach(Self.kinds, id: \.self) { kind in
                            let piece = Piece(colour: colour, kind: kind)
                            Button {
                                brush = brush == .piece(piece) ? nil : .piece(piece)
                            } label: {
                                PieceGlyphView(piece: piece)
                                    .padding(4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8).fill(
                                            brush == .piece(piece)
                                                ? Palette.analysis.opacity(0.22)
                                                : Palette.chipRest
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8).stroke(
                                            brush == .piece(piece)
                                                ? Palette.analysis : .clear,
                                            lineWidth: 1.5
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button {
                brush = brush == .eraser ? nil : .eraser
            } label: {
                Image(systemName: "eraser")
                    .font(.title3)
                    .foregroundStyle(brush == .eraser ? Palette.analysis : Palette.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(
                            brush == .eraser ? Palette.analysis.opacity(0.22) : Palette.chipRest
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(
                            brush == .eraser ? Palette.analysis : .clear, lineWidth: 1.5
                        )
                    )
            }
            .buttonStyle(.plain)
            .frame(width: 44)
        }
        .frame(height: 108)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    /// The two fields no picture can show and no glance can check. Off by default: they are
    /// inferred from where the pieces stand, and that inference is right except in positions a
    /// player would know to come looking for these.
    private var advanced: some View {
        VStack(spacing: 10) {
            if !draft.possibleCastling.isEmpty {
                HStack(spacing: 8) {
                    Text("易位权").eyebrow()
                    Spacer(minLength: 0)
                    ForEach(castlingRights, id: \.right) { entry in
                        Button {
                            if draft.castling.contains(entry.right) {
                                draft.castling.remove(entry.right)
                            } else {
                                draft.castling.insert(entry.right)
                            }
                        } label: {
                            Chip(label: entry.label, isOn: draft.castling.contains(entry.right))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !draft.possibleEnPassantSquares.isEmpty {
                HStack {
                    Text("吃过路兵").eyebrow()
                    Spacer()
                    Menu {
                        Button("无") { draft.enPassant = nil }
                        ForEach(draft.possibleEnPassantSquares, id: \.self) { square in
                            Button(square.description) { draft.enPassant = square }
                        }
                    } label: {
                        Chip(label: draft.enPassant?.description ?? "无", isOn: draft.enPassant != nil)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var done: some View {
        VStack(spacing: 8) {
            if let issue = draft.verdict.issue {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption)
                    Text(issue.chinese).font(.footnote)
                }
                .foregroundStyle(Palette.alarm)
            }
            Button {
                finish()
            } label: {
                Text(isCorrection ? "用这个局面" : "开始新对局")
                    .font(.headline)
                    .foregroundStyle(Palette.parchment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        draft.isPlayable ? Palette.ink : Palette.inkSoft,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!draft.isPlayable)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // ------------------------------------------------------------------ doing

    /// Whether this goes back into the game it came from. It does when nothing has been played
    /// there yet, which is when the answer to "the camera got a piece wrong" should be that the
    /// piece is now right — not a second game in the list.
    private var isCorrection: Bool {
        proposal.reopening?.game.plies.isEmpty ?? false
    }

    private func paint(_ square: Square) {
        switch brush {
        case .none: return
        case .eraser: draft.setPiece(nil, at: square)
        case .piece(let piece):
            // Tapping the same piece onto the square it already occupies takes it off, which is
            // what a finger expects and saves a trip to the eraser.
            draft.setPiece(draft.piece(at: square) == piece ? nil : piece, at: square)
        }
    }

    private func finish() {
        guard let game = draft.game else { return }

        if let session = proposal.reopening, session.replaceStart(with: game) {
            path.removeLast()
            return
        }

        let session = GameSession(
            game: game,
            controllers: proposal.controllers,
            orientation: proposal.orientation,
            origin: proposal.origin,
            picture: proposal.picture
        )
        session.attach(engine: engine.service, library: library)
        // Replaces the stack rather than adding to it: going back from a game in progress belongs
        // in the library, not in the editor of a position already being played.
        path = [.game(session)]
    }

    private var castlingRights: [(right: Character, label: String)] {
        [("K", "白 O-O"), ("Q", "白 O-O-O"), ("k", "黑 O-O"), ("q", "黑 O-O-O")]
            .filter { draft.possibleCastling.contains($0.0) }
            .map { (right: $0.0, label: $0.1) }
    }
}
