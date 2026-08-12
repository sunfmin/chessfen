import ChessfenKit
import Foundation

/// The app's one engine, and how it came to be there or not.
///
/// There is exactly one for the whole app (docs/adr/0009), so this is the thing screens
/// share rather than something they each build. Starting it means reading 112 MiB of
/// weights and building a thread pool, which is why the library is on screen first and the
/// engine arrives a moment later.
@Observable final class EngineHost {
    enum Status: Equatable {
        case starting
        case ready
        /// Something is wrong with the weights, which is the only way this fails. The app
        /// still recognises boards and still lets two hands play; it just cannot advise.
        case unavailable(String)
    }

    private(set) var status: Status = .starting
    private(set) var service: EngineService?

    /// Whether the app is in front of the user. The engine searches only while it is, and this
    /// is the one place that decides so — screens observe it rather than reading the scene
    /// phase for themselves, because two definitions of "in front of the user" would sooner or
    /// later disagree about whether to be thinking.
    private(set) var isActive = true

    var isReady: Bool { service != nil }

    func start() async {
        guard service == nil, status == .starting else { return }
        let outcome = await Task.detached(priority: .userInitiated) { Self.build() }.value
        switch outcome {
        case .success(let service):
            // The app can perfectly well have left while 112 MiB of weights were being read,
            // and an engine that arrives to an empty screen should arrive paused.
            if !isActive { service.pause() }
            self.service = service
            status = .ready
        case .failure(let failure):
            status = .unavailable(Self.explain(failure))
        }
    }

    /// The app came to the front, or left it.
    ///
    /// An unbounded Analysis left running while nobody is looking is a phone getting warm in a
    /// pocket over a position nobody is reading. Pausing stops the running search and holds a
    /// Review where it stands; resuming lets the Review carry on at the same Depth, and lets
    /// the screens start the Analysis they want again.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            service?.resume()
        } else {
            service?.pause()
        }
    }

    // The build happens off the main thread, so everything it touches is nonisolated.

    private nonisolated static func build()
        -> Result<EngineService, EngineService.StartupFailure>
    {
        guard let big = net("nn-c288c895ea92"), let small = net("nn-37f18f62d772") else {
            return .failure(.networkMissing)
        }
        do {
            // Two cores are left to the UI by default. The hash is smaller than the
            // desktop default because iOS will kill an app that treats a phone like a
            // workstation, and 128 MiB is plenty for the depths a game reaches.
            return .success(
                try EngineService(
                    bigNetURL: big,
                    smallNetURL: small,
                    configuration: .init(hashMegabytes: 128, multiPV: 3)
                )
            )
        } catch let failure as EngineService.StartupFailure {
            return .failure(failure)
        } catch {
            return .failure(.unknown)
        }
    }

    private nonisolated static func net(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "nnue", subdirectory: "Nets")
    }

    private nonisolated static func explain(
        _ failure: EngineService.StartupFailure
    ) -> String {
        switch failure {
        case .networkMissing: "找不到神经网络权重文件，引擎无法启动。"
        case .networkTooSmall: "权重文件不完整，引擎无法启动。"
        case .allocationFailed: "内存不足，引擎无法启动。"
        case .unknown: "引擎启动失败。"
        }
    }
}
