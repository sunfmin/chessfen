import ChessfenKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Where the app goes next. A game and a review are pushed by identity, because the session they
/// show is a live object rather than a value that can be recreated.
enum Step: Hashable {
    case confirm(PositionProposal)
    case game(GameSession)
    case review(GameSession)
}

struct LibraryScreen: View {
    @Environment(EngineHost.self) private var engine
    @Environment(GameLibrary.self) private var library

    @State private var path: [Step] = []
    @State private var isCameraOpen = false
    @State private var isPhotoPickerOpen = false
    @State private var isFileImporterOpen = false
    @State private var isAboutShowing = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isRecognising = false
    @State private var failure: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    masthead
                    if case .unavailable(let reason) = engine.status {
                        note(reason, symbol: "exclamationmark.triangle.fill")
                    }
                    entries
                    games
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Palette.parchment)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.parchment, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(Palette.analysis)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if case .starting = engine.status {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("引擎启动中").eyebrow()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAboutShowing = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $isAboutShowing) { AboutScreen() }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .confirm(let proposal):
                    ConfirmPositionScreen(proposal: proposal, path: $path)
                case .game(let session):
                    GameScreen(session: session, path: $path)
                case .review(let session):
                    ReviewScreen(session: session)
                }
            }
            .overlay {
                if isRecognising { recognising }
            }
        }
        .fullScreenCover(isPresented: $isCameraOpen) {
            CameraPicker { picked in
                if let image = BoardImageLoader.image(from: picked) {
                    recognise(image)
                } else {
                    failure = "这张照片打不开。"
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $isPhotoPickerOpen, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                    let image = BoardImageLoader.image(from: data)
                else {
                    failure = "这张图片打不开。"
                    return
                }
                recognise(image)
            }
        }
        .fileImporter(
            isPresented: $isFileImporterOpen,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first, let image = BoardImageLoader.image(fromFileAt: url)
                else {
                    failure = "这个文件打不开。"
                    return
                }
                recognise(image)
            case .failure(let error):
                failure = error.localizedDescription
            }
        }
        .alert("没认出棋盘", isPresented: .constant(failure != nil)) {
            Button("好") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    // ------------------------------------------------------------------ parts

    /// The name, set rather than accepted. 镜 does two jobs here — a lens, and a mirror: the app
    /// puts the board in front of you onto the phone, unchanged.
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("棋镜")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(6)
                    .foregroundStyle(Palette.ink)
                Text("CHESSFEN")
                    .font(.caption2.weight(.medium))
                    .tracking(3)
                    .foregroundStyle(Palette.inkSoft)
            }
            Text("对着棋盘拍一张，接着往下下。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    /// The two ways in. Photographing a board is the one this app is for, so it is the one that
    /// looks like a button — the other three ways to hand it a picture are behind the chevron.
    private var entries: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                Button {
                    isCameraOpen = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.fill").font(.title3)
                        Text("拍棋盘").font(.headline)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Palette.parchment)
                    .padding(.leading, 18)
                    .padding(.vertical, 16)
                    // The dark fill belongs to the row, not to this label, so the label has to
                    // claim its half of the row as a tap target or only the glyph would answer.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        isPhotoPickerOpen = true
                    } label: {
                        Label("从相册选", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        paste()
                    } label: {
                        Label("粘贴截图", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        isFileImporterOpen = true
                    } label: {
                        Label("从文件选", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.parchment)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                        .contentShape(Rectangle())
                }
                .overlay(alignment: .leading) {
                    Rectangle().fill(Palette.parchment.opacity(0.25)).frame(width: 0.5)
                }
            }
            .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14))

            Button {
                start(Game(startFEN: PGN.standardStartFEN))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                    Text("从开局摆起").font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(Palette.chipRest, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private var games: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("对局记录").eyebrow().padding(.top, 6)

            if library.entries.isEmpty {
                Text("走出第一步，这局就会记在这里。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }

            ForEach(library.entries) { entry in
                Button {
                    open(entry)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: entry.origin.symbol)
                            .font(.footnote)
                            .foregroundStyle(
                                entry.origin == .recognised ? Palette.parchment : Palette.ink
                            )
                            .frame(width: 30, height: 30)
                            .background(
                                entry.origin == .recognised ? Palette.analysis : Palette.chipRest,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.ink)
                            Text(entry.detail)
                                .font(.caption)
                                .foregroundStyle(Palette.inkSoft)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .padding(12)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        library.delete(entry)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func note(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.footnote)
            Text(text).font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.alarm)
        .padding(12)
        .background(Palette.alarm.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private var recognising: some View {
        ZStack {
            Palette.ink.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(Palette.analysis)
                Text("在认棋盘").eyebrow()
            }
            .padding(28)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // ------------------------------------------------------------------ doing

    private func paste() {
        guard let image = BoardImageLoader.fromClipboard() else {
            failure = "剪贴板里没有图片。截个图再回来试试。"
            return
        }
        recognise(image)
    }

    /// Reads the picture and goes straight to the game (docs/adr/0011). The squares recognition
    /// was unsure of stay ringed on the board there, and 改棋子 is one tap away — so the common
    /// case costs no taps at all and the rare one costs one.
    private func recognise(_ image: RGBImage) {
        isRecognising = true
        Task {
            let recognition = await Task.detached(priority: .userInitiated) {
                try? await Recognizer.recognise(photograph: image)
            }.value
            isRecognising = false

            // No board in the picture at all — the only thing this message is true about.
            guard let recognition, let draft = PositionDraft(fen: recognition.fen) else {
                failure = "这张图里没找到棋盘。把棋盘拍满一点，或者换个正面的角度。"
                return
            }
            let shaky = Set(recognition.shaky.map(\.square))
            // The board, cut out of the picture and nothing else. Kept this way rather than as the
            // whole frame because it is the form the editor can lay under the board square for
            // square, and because it needs no rect carried alongside it to be usable — the crop is
            // the alignment, so it survives being written to disk and read back after a relaunch.
            let picture = recognition.boardPicture

            // A legal reading opens as a game, which is the whole point of 0011. An illegal one
            // is *not* a failed recognition: the board was found and read with a mistake in it,
            // most often a king read as something else, and one square is all that stands between
            // it and a playable position. That is what the editor and the ringed Shaky Squares
            // are for, so it opens there — rather than being thrown away behind a message
            // blaming the photograph, which is what it used to do.
            guard let game = Game(startFEN: recognition.fen) else {
                path.append(
                    .confirm(
                        PositionProposal(
                            draft: draft,
                            shaky: shaky,
                            orientation: recognition.orientation,
                            picture: picture
                        )
                    )
                )
                return
            }

            let session = GameSession(
                game: game,
                orientation: recognition.orientation,
                origin: .recognised,
                picture: picture,
                shaky: shaky
            )
            session.attach(engine: engine.service, library: library)
            path.append(.game(session))
        }
    }

    private func start(_ game: Game?) {
        guard let game else { return }
        let session = GameSession(game: game, origin: .fresh)
        session.attach(engine: engine.service, library: library)
        path.append(.game(session))
    }

    private func open(_ entry: GameLibrary.Entry) {
        let session = GameSession(entry: entry, library: library)
        session.attach(engine: engine.service, library: library)
        path.append(.game(session))
    }
}
