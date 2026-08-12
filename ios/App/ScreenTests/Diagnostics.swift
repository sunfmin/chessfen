import Darwin
import SwiftUI
import Testing
import UIKit

@testable import Chessfen

@MainActor private var report: [String] = []
@MainActor private func print(_ line: String) { report.append(line) }

@MainActor
@Test("diagnostics: what does a hosted SwiftUI screen expose")
func diagnostics() async throws {
    defer {
        try? report.joined(separator: "\n")
            .write(to: ScreenImage.directory.appending(path: "diagnostics.txt"), atomically: true, encoding: .utf8)
    }
    for name in [
        "_AXSSetAutomationEnabled", "AXSSetAutomationEnabled", "_AXSAutomationEnabled",
        "_AXSApplicationAccessibilityEnabled", "_AXSSetApplicationAccessibilityEnabled",
    ] {
        print("SYMBOL \(name): \(dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) != nil)")
    }

    let handle = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW)
    print("HANDLE libAccessibility: \(handle != nil)")

    if let handle, let symbol = dlsym(handle, "_AXSSetAutomationEnabled") {
        typealias Switch = @convention(c) (Bool) -> Void
        unsafeBitCast(symbol, to: Switch.self)(true)
        print("AUTOMATION enabled")
    }

    let scene = UIApplication.shared.connectedScenes.lazy
        .compactMap { $0 as? UIWindowScene }.first
    print("SCENE: \(scene != nil), bounds \(scene?.screen.bounds ?? .zero)")

    let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
    let controller = UIHostingController(
        rootView: VStack {
            Text("你好世界")
            Button("按一下") {}
        }
    )
    window.rootViewController = controller
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    for _ in 0..<6 { try? await Task.sleep(for: .milliseconds(50)) }
    print("WINDOW frame \(window.frame) safeArea \(window.safeAreaInsets)")

    dump(window, depth: 0)
    window.isHidden = true
}

@MainActor
private func dump(_ view: UIView, depth: Int) {
    let pad = String(repeating: "  ", count: depth)
    let elements = view.accessibilityElements?.count ?? -1
    print(
        "\(pad)\(type(of: view)) frame=\(view.frame) isAX=\(view.isAccessibilityElement) "
            + "label=\(view.accessibilityLabel ?? "nil") elements=\(elements) "
            + "count=\(view.accessibilityElementCount())"
    )
    if let elements = view.accessibilityElements {
        for element in elements {
            guard let object = element as? NSObject else { continue }
            print(
                "\(pad)  · \(type(of: object)) label=\(object.accessibilityLabel ?? "nil") "
                    + "value=\(object.accessibilityValue ?? "nil") "
                    + "children=\(object.accessibilityElementCount())"
            )
        }
    }
    for subview in view.subviews { dump(subview, depth: depth + 1) }
}
