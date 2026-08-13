import ChessfenKit
import SwiftUI

/// What this app is made of, and where to get it.
///
/// Stockfish is GPLv3 and this links against it, so the whole thing is GPLv3 (docs/adr/0001)
/// — which obliges anyone handing the binary to somebody else to hand over the licence and a
/// way to the source too. That is easiest to honour if the app carries both itself.
struct AboutScreen: View {
    @Environment(EngineHost.self) private var engine
    @Environment(GameLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    private static let source = URL(string: "https://github.com/sunfmin/chessfen")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("棋镜").font(.title2.bold())
                            Text("Chessfen").eyebrow()
                        }
                        Text("拍下棋盘，认出局面，接着下。识别和引擎都在这台设备上跑；对局存在你自己的 iCloud 里。只有你从链接导入棋谱的时候，才会去下载那个链接。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("版本") {
                    row("棋镜", Self.version)
                    row("引擎", "Stockfish 18")
                    switch engine.status {
                    case .ready: row("引擎状态", "已就绪")
                    case .starting: row("引擎状态", "启动中")
                    case .unavailable: row("引擎状态", engine.unavailableReason ?? "")
                    }
                }

                // Where the games are is worth saying out loud: it is the difference between a
                // game that is on every device and one that is on this one, and the only way to
                // tell from inside the app that iCloud is switched on.
                Section {
                    row("对局存放在", library.folder.isCloud ? "iCloud 云盘" : "本机")
                } header: {
                    Text("存储")
                } footer: {
                    Text(
                        library.folder.isCloud
                            ? "每一局都是一个 PGN 文件，存在 iCloud 云盘的「棋镜」文件夹里，在「文件」App 里可以直接打开、拷走或删掉。改动会同步到你登录同一个 Apple 账户的其他设备。"
                            : "每一局都是一个 PGN 文件，目前只存在这台设备上。打开「设置 → Apple 账户 → iCloud 云盘」之后，已有的对局会自动搬进 iCloud，并同步到你的其他设备。"
                    )
                }

                Section {
                    Link(destination: Self.source) {
                        Label("源代码", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("许可")
                } footer: {
                    Text(
                        """
                        本应用内置 Stockfish，按 GNU GPL v3 发布，因此本应用整体也按 GPL v3 发布：\
                        你可以自由使用、研究、修改和再分发它，条件是分发时一并给出源代码和同样的许可。\
                        完整许可文本见源代码仓库里的 LICENSE 文件。

                        棋子图形来自 python-chess 的 Cburnett 棋子集（CC BY-SA 3.0）。
                        """
                    )
                }
            }
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }
}
