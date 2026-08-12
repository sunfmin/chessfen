import ChessfenKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Where the app goes next. A game and a review are pushed by identity, because the session
/// they show is a live object rather than a value that can be recreated.
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
    @State private var photoItem: PhotosPickerItem?
    @State private var isRecognising = false
    @State private var failure: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if case .unavailable(let reason) = engine.status {
                    Section {
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("识别和手动对局仍然可用，只是没有引擎建议。")
                    }
                }

                Section("开局") {
                    Button {
                        start(from: Game(startFEN: PGN.standardStartFEN), origin: .fresh)
                    } label: {
                        Label("新对局", systemImage: "plus.circle")
                    }

                    // Tapping the row goes straight to the camera, because that is what this
                    // is for nine times out of ten. The other three ways in live under the
                    // chevron rather than in front of it.
                    HStack {
                        Button {
                            isCameraOpen = true
                        } label: {
                            Label("拍照识别棋盘", systemImage: "camera")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
                            Image(systemName: "chevron.down.circle")
                                .padding(.leading, 8)
                        }
                    }
                }

                Section("对局记录") {
                    if library.entries.isEmpty {
                        Text("还没有保存的对局。走第一步之后就会记在这里。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.entries) { entry in
                        Button {
                            open(entry)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: entry.origin.symbol)
                                    .foregroundStyle(
                                        entry.origin == .recognised ? Color.accentColor : .secondary
                                    )
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                    Text(entry.detail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { library.delete(library.entries[index]) }
                    }
                }
            }
            .navigationTitle("Chessfen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if case .starting = engine.status {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("引擎启动中").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
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
                if isRecognising {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("识别中…").font(.footnote)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
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
                guard let url = urls.first,
                    let image = BoardImageLoader.image(fromFileAt: url)
                else {
                    failure = "这个文件打不开。"
                    return
                }
                recognise(image)
            case .failure(let error):
                failure = error.localizedDescription
            }
        }
        .alert("识别失败", isPresented: .constant(failure != nil)) {
            Button("好") { failure = nil }
        } message: {
            Text(failure ?? "")
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

    /// Recognition is CPU-bound and takes long enough on a warped photograph to be worth
    /// getting off the main thread, so it runs detached and the screen shows a spinner.
    private func recognise(_ image: RGBImage) {
        isRecognising = true
        Task {
            let recognition = await Task.detached(priority: .userInitiated) {
                try? await Recognizer.recognise(photograph: image)
            }.value
            isRecognising = false

            guard let recognition, let draft = PositionDraft(fen: recognition.fen) else {
                failure = "这张图里没找到棋盘。把棋盘拍满一点，或者试试正面拍。"
                return
            }
            // Straight to the gate, never straight to a game (docs/adr/0008).
            path.append(
                .confirm(
                    PositionProposal(
                        draft: draft,
                        shaky: Set(recognition.shaky.map(\.square)),
                        orientation: recognition.orientation,
                        picture: recognition.image
                    )
                )
            )
        }
    }

    private func start(from game: Game?, origin: GameOrigin) {
        guard let game else { return }
        let session = GameSession(game: game, origin: origin)
        session.attach(engine: engine.service, library: library)
        path.append(.game(session))
    }

    private func open(_ entry: GameLibrary.Entry) {
        let session = GameSession(entry: entry, library: library)
        session.attach(engine: engine.service, library: library)
        path.append(.game(session))
    }
}
