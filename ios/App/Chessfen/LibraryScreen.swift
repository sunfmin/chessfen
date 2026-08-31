import ChessfenKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Where the app goes next. A game is pushed by identity, because the session it shows is a live
/// object rather than a value that can be recreated.
///
/// There is no review here. A Review is not a place: it is what the engine's opinion switched on
/// looks like, on the same board the game is played on (docs/adr/0015).
enum Step: Hashable {
    /// One collection, addressed by its name — which is also all a collection is.
    case collection(String)
    case confirm(PositionProposal)
    case game(GameSession)
    /// The tally over the library. It carries nothing, because it is counted when it is opened
    /// and stored nowhere (docs/adr/0018).
    case habits
}

/// A typed name, or nil for one that was only spaces — which is how a name is taken back off.
private func trimmed(_ text: String) -> String? {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? nil : clean
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
    @State private var failure: (title: String, message: String)?
    /// The import sheet being shown, and the collection it is pinned to — nil when opened
    /// from the library, where the collection is asked for instead.
    @State private var importTarget: ImportTarget?

    private struct ImportTarget: Identifiable {
        let collection: String?
        var id: String { collection ?? "library" }
    }
    /// The collection being renamed, and the name being typed for it.
    @State private var renamingCollection: String?
    @State private var collectionDraft = ""

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    masthead
                    if let reason = engine.unavailableReason {
                        note(reason, symbol: "exclamationmark.triangle.fill")
                    }
                    entries
                    if !library.entries.isEmpty { habitsCard }
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
            .sheet(item: $importTarget) { target in
                ImportSheet(targetCollection: target.collection)
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .collection(let name):
                    CollectionScreen(name: name, path: $path)
                case .confirm(let proposal):
                    ConfirmPositionScreen(proposal: proposal, path: $path)
                case .game(let session):
                    GameScreen(session: session, path: $path)
                case .habits:
                    HabitsScreen(path: $path)
                }
            }
            .overlay {
                if isRecognising { recognising }
            }
        }
        .fullScreenCover(isPresented: $isCameraOpen) {
            BoardCameraScreen { picked in
                guard let image = BoardImageLoader.image(from: picked) else {
                    failure = BoardIntake.Intake.unreadableAlert
                    return
                }
                // The camera's is the only copy of this picture; the other ways in have
                // their original elsewhere already.
                recognise(.image(image), keepingPhotograph: true)
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $isPhotoPickerOpen, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    failure = BoardIntake.Intake.unreadableAlert
                    return
                }
                recognise(.data(data))
            }
        }
        .fileImporter(
            isPresented: $isFileImporterOpen,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    failure = BoardIntake.Intake.unreadableAlert
                    return
                }
                recognise(.file(url))
            case .failure(let error):
                failure = ("没能拿到图片", error.localizedDescription)
            }
        }
        .alert(failure?.title ?? "", isPresented: .constant(failure != nil)) {
            Button("好") { failure = nil }
        } message: {
            Text(failure?.message ?? "")
        }
        .alert("重命名作品集", isPresented: .constant(renamingCollection != nil)) {
            TextField("作品集名字", text: $collectionDraft)
            Button("好") {
                if let old = renamingCollection, let name = trimmed(collectionDraft) {
                    library.renameCollection(old, to: name)
                }
                renamingCollection = nil
            }
            Button("取消", role: .cancel) { renamingCollection = nil }
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

            Button {
                importTarget = ImportTarget(collection: nil)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                    Text("导入棋局").font(.subheadline.weight(.medium))
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

    /// The library: the collections as cards, then the games nobody has filed.
    ///
    /// A collection stays shut. It is a thing you go into — fifty positions spilled out here would
    /// bury the ways in, and the unfiled games under them. Unfiled games are not a collection and do
    /// not become one, so they stay exactly as they were: a list.
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

            ForEach(library.collections) { collection in
                if let name = collection.name {
                    collectionCard(name, count: collection.entries.count)
                }
            }

            if let unfiled = library.collections.first(where: { $0.name == nil }) {
                // A heading only once there is something else above it to tell these apart from.
                if library.collections.count > 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "tray").font(.caption2).foregroundStyle(Palette.inkSoft)
                        Text("未归类")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 6)
                    .padding(.horizontal, 2)
                }
                GameList(entries: unfiled.entries) { open($0) }
            }
        }
    }

    /// The way to 老毛病. Not a score and not a badge: the card says nothing about how the player
    /// is doing, because whether there is anything to say is only known once the games have been
    /// read, and reading them is what the screen behind this does.
    private var habitsCard: some View {
        Button {
            path.append(.habits)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "repeat")
                    .font(.footnote)
                    .foregroundStyle(Palette.parchment)
                    .frame(width: 30, height: 30)
                    .background(Palette.alarm, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("老毛病")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Text("你反复犯的那几个错，从对局里数出来")
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
    }

    /// A collection, shut: its name, how many games are in it, and the way in.
    private func collectionCard(_ name: String, count: Int) -> some View {
        Button {
            path.append(.collection(name))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.parchment)
                    .frame(width: 30, height: 30)
                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Text("\(count) 局")
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
            Button {
                collectionDraft = name
                renamingCollection = name
            } label: {
                Label("重命名作品集", systemImage: "pencil")
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
            failure = ("剪贴板里没有图片", "截个图再回来试试。")
            return
        }
        recognise(.image(image))
    }

    /// Reads the picture and goes straight to the game (docs/adr/0011). The squares recognition
    /// was unsure of stay ringed on the board there, and 改棋子 is one tap away — so the common
    /// case costs no taps at all and the rare one costs one.
    private func recognise(_ source: BoardIntake.Source, keepingPhotograph: Bool = false) {
        isRecognising = true
        Task {
            let intake: BoardIntake.Intake
            if keepingPhotograph {
                intake = await BoardIntake.read(source, keepingPhotograph: { image in
                    library.keepPhotograph(image)
                })
            } else {
                intake = await BoardIntake.read(source)
            }
            isRecognising = false

            switch intake {
            case .played(let game, let shaky, let orientation, let picture):
                let session = GameSession.recognised(
                    game,
                    orientation: orientation,
                    picture: picture,
                    shaky: shaky,
                    engine: engine.service,
                    library: library
                )
                path.append(.game(session))
            case .needsEditing(let draft, let shaky, let orientation, let picture):
                path.append(
                    .confirm(
                        PositionProposal(
                            draft: draft,
                            shaky: shaky,
                            orientation: orientation,
                            picture: picture
                        )
                    )
                )
            case .noBoard, .unreadable:
                failure = intake.alert
            }
        }
    }

    private func start(_ game: Game?) {
        guard let game else { return }
        let session = GameSession.fresh(game, engine: engine.service, library: library)
        path.append(.game(session))
    }

    private func open(_ entry: GameLibrary.Entry) {
        guard let session = GameSession.opened(entry, engine: engine.service, library: library) else {
            return
        }
        path.append(.game(session))
    }
}

/// A list of games, and everything that can be done to one: open it, name it, file it, delete it.
///
/// One definition shared by the library's unfiled pile and by a collection's own screen. The row and
/// its menu were the same thing in both places, and so were the dialogs behind them — which is the
/// kind of sameness that drifts apart a version at a time.
struct GameList: View {
    let entries: [GameLibrary.Entry]
    let open: (GameLibrary.Entry) -> Void

    @Environment(GameLibrary.self) private var library

    @State private var renaming: GameLibrary.Entry?
    @State private var nameDraft = ""
    @State private var filing: Filing?
    @State private var collectionDraft = ""

    /// A game on its way into a collection. The collection is nil while it is still being named,
    /// which is the only difference between filing into one that exists and making a new one.
    private struct Filing: Identifiable {
        let entry: GameLibrary.Entry
        let collection: String?
        var id: URL { entry.url }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entries) { entry in
                row(entry)
            }
        }
        .alert("给这一局起个名字", isPresented: .constant(renaming != nil)) {
            TextField("名字", text: $nameDraft)
            Button("好") {
                if let entry = renaming { library.rename(entry, to: trimmed(nameDraft)) }
                renaming = nil
            }
            Button("取消", role: .cancel) { renaming = nil }
        } message: {
            Text("作品集里按名字排，所以「第 002 题」这样的名字会排在你想的地方。留空就用存下来的时间。")
        }
        // Filing asks for the name in the same breath, because in a collection the name *is* the
        // order: a game put into one without being named sits wherever its timestamp falls, which is
        // never where it belongs in a set someone is working through.
        .alert(filingTitle, isPresented: .constant(filing != nil)) {
            if filing?.collection == nil {
                TextField("作品集名字", text: $collectionDraft)
            }
            TextField("这一局叫什么", text: $nameDraft)
            Button("好") { commitFiling() }
            Button("取消", role: .cancel) { filing = nil }
        } message: {
            Text("名字决定它在作品集里排第几，也决定练习时上一局下一局的顺序。")
        }
    }

    private var filingTitle: String {
        guard let filing else { return "" }
        guard let collection = filing.collection else { return "新建作品集" }
        return "归到「\(collection)」"
    }

    private func commitFiling() {
        defer { filing = nil }
        guard let filing else { return }
        let collection = filing.collection ?? trimmed(collectionDraft)
        guard let collection else { return }
        // Both tags in one write. Two calls each read the entry's own copy of the PGN, so the second
        // would carry the first one's change away with it — the name would land and the collection
        // would silently revert.
        var changes: [(name: String, value: String?)] = [("Event", collection)]
        // The name is only touched when something was typed, so backing out of naming does not wipe
        // a name the game already had.
        if let name = trimmed(nameDraft) {
            changes.append((GameLibrary.nameTag, name))
        }
        library.setTags(changes, on: filing.entry)
    }

    private func beginFiling(_ entry: GameLibrary.Entry, into collection: String?) {
        nameDraft = entry.name ?? ""
        collectionDraft = ""
        filing = Filing(entry: entry, collection: collection)
    }

    private func row(_ entry: GameLibrary.Entry) -> some View {
        Button {
            open(entry)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.origin.symbol)
                    .font(.footnote)
                    .foregroundStyle(entry.origin == .recognised ? Palette.parchment : Palette.ink)
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
            Button {
                nameDraft = entry.name ?? ""
                renaming = entry
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Menu {
                // The collections that exist, with a tick against the one this game is already in,
                // so the menu doubles as the answer to "where is this filed".
                ForEach(library.collectionNames, id: \.self) { name in
                    Button {
                        beginFiling(entry, into: name)
                    } label: {
                        Label(name, systemImage: entry.collection == name ? "checkmark" : "folder")
                    }
                }
                Button {
                    beginFiling(entry, into: nil)
                } label: {
                    Label("新建作品集…", systemImage: "folder.badge.plus")
                }
                if entry.collection != nil {
                    Button {
                        library.file(entry, under: nil)
                    } label: {
                        Label("移出作品集", systemImage: "tray.and.arrow.up")
                    }
                }
            } label: {
                Label("归到作品集", systemImage: "folder")
            }
            Divider()
            Button(role: .destructive) {
                library.delete(entry)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

/// One collection, open: the games in it, in the order 上一局 and 下一局 walk.
struct CollectionScreen: View {
    let name: String
    @Binding var path: [Step]

    @Environment(EngineHost.self) private var engine
    @Environment(GameLibrary.self) private var library

    @State private var isRenaming = false
    @State private var draft = ""
    @State private var isImporting = false

    private var entries: [GameLibrary.Entry] {
        library.collections.first { $0.name == name }?.entries ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(entries.count) 局 · 按名字排")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
                    .padding(.bottom, 2)

                if entries.isEmpty {
                    // Reachable: the last game can be moved out or deleted from this very screen. A
                    // collection is only the games claiming it, so at that moment it stops existing.
                    Text("这个作品集空了。把棋局归进来，它就回到列表里。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.vertical, 10)
                }

                GameList(entries: entries) { entry in
                    guard let session = GameSession.opened(entry, engine: engine.service, library: library) else {
                        return
                    }
                    path.append(.game(session))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Palette.parchment)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.parchment, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(Palette.analysis)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isImporting = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("导入棋局")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draft = name
                    isRenaming = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $isImporting) {
            // Pinned to this collection: the whole point of the door is that more games
            // land in here, not in a new collection (docs/adr/0014).
            ImportSheet(targetCollection: name)
        }
        .alert("重命名作品集", isPresented: $isRenaming) {
            TextField("作品集名字", text: $draft)
            Button("好") {
                let fresh = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !fresh.isEmpty, fresh != name else { return }
                library.renameCollection(name, to: fresh)
                // This screen is addressed by the name, so the path element has to be re-addressed
                // with it — otherwise renaming leaves you looking at a collection that no longer
                // exists, which reads as having lost fifty games.
                path[path.count - 1] = .collection(fresh)
            }
            Button("取消", role: .cancel) {}
        }
    }
}
