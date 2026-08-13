import ChessfenKit
import SwiftUI

/// The sheet that turns a pasted PGN link into games in the library (docs/adr/0014).
///
/// One link downloads a whole multi-game PGN — a lichess study is the canonical case — and
/// every chapter becomes one game in a collection. Opened from the library, the collection
/// is asked for; opened from inside a collection it is pinned, which is the "add more games
/// to this collection" door. The downloading and reading is `ImportSession`'s; this is the
/// deck of controls around it, one state per phase.
struct ImportSheet: View {
    /// The collection the import is pinned to, when the sheet was opened from inside one.
    let targetCollection: String?
    let session: ImportSession

    @Environment(GameLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var input: String
    @State private var collectionDraft = ""

    init(
        targetCollection: String? = nil,
        session: ImportSession = ImportSession(),
        initialInput: String = ""
    ) {
        self.targetCollection = targetCollection
        self.session = session
        _input = State(initialValue: initialInput)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("贴一个 PGN 链接——比如一个 lichess 研究——每一章会变成作品集里的一局。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)

                    TextField("PGN 链接", text: $input)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).stroke(Palette.hairline, lineWidth: 0.5)
                        )

                    collection

                    switch session.phase {
                    case .idle:
                        primaryButton("获取棋谱", isEnabled: !trimmedInput.isEmpty, action: fetch)
                    case .fetching:
                        waiting("在下载棋谱…")
                    case .ready(let plan):
                        ready(plan)
                    case .importing:
                        waiting("在写入…")
                    case .done(let outcome):
                        done(outcome)
                    case .failed(let error):
                        failed(error)
                    }
                }
                .padding(16)
            }
            .background(Palette.parchment)
            .navigationTitle("从链接导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.parchment, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(Palette.analysis)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear(perform: prefill)
            .onChange(of: session.phase) { _, _ in prefill() }
        }
    }

    // ------------------------------------------------------------------ parts

    /// Which collection this lands in: asked for, or pinned by the door the sheet came in
    /// through.
    @ViewBuilder
    private var collection: some View {
        if let targetCollection {
            Text("导入到「\(targetCollection)」").eyebrow()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("导入到作品集").eyebrow()
                TextField("作品集名字", text: $collectionDraft)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12).stroke(Palette.hairline, lineWidth: 0.5)
                    )
            }
        }
    }

    /// What the download found, with the button that makes it real.
    private func ready(_ plan: PGNImport.ImportPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary(of: plan))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                // The first few names, so what is about to land can be checked against the
                // study it came from — all of them would scroll a sheet past its point.
                ForEach(plan.chapters.prefix(5)) { chapter in
                    Text(chapter.name)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                }
                if plan.chapters.count > 5 {
                    Text("还有 \(plan.chapters.count - 5) 章…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSoft)
                }
                if plan.unreadable > 0 {
                    Text("有 \(plan.unreadable) 章没能读出来，会跳过。")
                        .font(.footnote)
                        .foregroundStyle(Palette.alarm)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12))

            primaryButton("导入 \(plan.chapters.count) 局", isEnabled: canImport, action: importNow)
        }
    }

    private func summary(of plan: PGNImport.ImportPlan) -> String {
        guard let suggested = plan.suggestedCollection else { return "\(plan.chapters.count) 章" }
        return "「\(suggested)」· \(plan.chapters.count) 章"
    }

    private func done(_ outcome: PGNImport.ImportOutcome) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(outcome.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            HStack(spacing: 10) {
                Button {
                    session.reset()
                    input = ""
                    collectionDraft = ""
                } label: {
                    Text("再导入一个")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(Palette.chipRest, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                Button {
                    dismiss()
                } label: {
                    Text("完成")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.parchment)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// What went wrong, and the one thing there is to do about it. The wording comes with
    /// the error (`PGNImport.Error.alert`), so every door into an import says the same thing
    /// for the same failure.
    private func failed(_ error: PGNImport.Error) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let alert = error.alert
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.alarm)
                Text(alert.message)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSoft)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.alarm.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            primaryButton("重试", isEnabled: true, action: fetch)
        }
    }

    private func waiting(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).eyebrow()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    /// The one main button of whichever phase it serves, wearing the same ink fill the
    /// library's 拍棋盘 wears.
    private func primaryButton(
        _ label: String, isEnabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.parchment)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    // ------------------------------------------------------------------ doing

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether there is a collection to import into. Pinned sheets always have one; free
    /// ones need a typed name — the collection is the point of the import, not a nicety,
    /// and an empty name would file the games nowhere.
    private var canImport: Bool {
        targetCollection != nil
            || !collectionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The study names its collection; prefill it. Only into a draft nobody has typed
    /// into yet — a suggestion is not an override.
    private func prefill() {
        guard case .ready(let plan) = session.phase,
            let suggested = plan.suggestedCollection,
            collectionDraft.isEmpty
        else { return }
        collectionDraft = suggested
    }

    private func fetch() {
        guard !trimmedInput.isEmpty else { return }
        Task { await session.run(trimmedInput) }
    }

    private func importNow() {
        guard canImport, let name = targetCollection ?? Self.trimmed(collectionDraft) else { return }
        session.apply(into: name, library: library)
    }

    private static func trimmed(_ text: String) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
