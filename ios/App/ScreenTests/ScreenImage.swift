import SwiftUI
import UIKit

@testable import Chessfen

/// Draws a screen the way the app draws it, writes the picture, and hands back what the screen
/// says.
///
/// This is the glue and nothing else: a window on the simulator's own screen, the real view in it,
/// long enough for it to settle, one picture. Everything a screenshot needs to vary — the game,
/// the engine, which way up the board is — a test varies for itself and passes in, so the next
/// screenshot is a new `subject` and no new plumbing.
///
/// The words come back with the picture on purpose. A PNG is for a person to look at once; the
/// list of everything the screen said is what a test can hold the screen to for ever after.
@MainActor
enum ScreenImage {
    /// Where the pictures land: `ios/App/out`, beside the source rather than deep inside
    /// DerivedData, because the whole point of them is that someone opens them.
    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent()  // ScreenTests
        .deletingLastPathComponent()  // App
        .appending(path: "out", directoryHint: .isDirectory)

    /// One rendered screen: the file it was written to, and every word it drew.
    struct Rendered {
        let url: URL
        /// The accessibility tree, flattened. It is the only account SwiftUI will give of the text
        /// it drew — and it is the same account VoiceOver reads out, so a screen that says nothing
        /// here is a screen that says nothing to anybody.
        let words: [String]

        func says(_ text: String) -> Bool { words.contains { $0.contains(text) } }
        func count(of text: String) -> Int { words.count { $0.contains(text) } }
    }

    static func write(
        _ name: String,
        style: UIUserInterfaceStyle = .light,
        of subject: () -> some View
    ) async -> Rendered {
        let window = newWindow(style: style)
        let controller = UIHostingController(rootView: subject())
        controller.overrideUserInterfaceStyle = style
        // Clear rather than the hosting controller's default white, which would otherwise show
        // through the safe areas and light up the edges of a dark screen.
        controller.view.backgroundColor = .clear
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        await settle()

        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
        let url = directory.appending(path: "\(name).png")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try? image.pngData()?.write(to: url, options: .atomic)

        let rendered = Rendered(url: url, words: words(in: window))
        // The window is done with, and a key window left standing would still be the key one when
        // the next screenshot puts its own on screen.
        window.isHidden = true
        return rendered
    }

    // ----------------------------------------------------------------- plumbing

    /// A window the size of the device the test is running on, on the host app's own scene so
    /// that the safe areas are a real phone's rather than nothing at all.
    private static func newWindow(style: UIUserInterfaceStyle) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.lazy
            .compactMap { $0 as? UIWindowScene }
            .first
        let window =
            scene.map { UIWindow(windowScene: $0) }
            ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.overrideUserInterfaceStyle = style
        return window
    }

    /// Long enough for the screen to have been told everything it is going to be told.
    ///
    /// A screen asks for its Analysis in `onAppear`, and the answer arrives on the main actor a
    /// hop later and then animates into place. A picture taken before that is a picture of a
    /// screen nobody has said anything to yet, which is not the screen anyone wanted to see.
    private static func settle() async {
        for _ in 0..<14 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Everything on screen that has a word attached to it.
    private static func words(in view: UIView) -> [String] {
        var found: [String] = []
        var seen: Set<ObjectIdentifier> = []
        harvest(view, into: &found, seen: &seen)
        return found
    }

    /// Walks views and accessibility elements together, because SwiftUI draws its text into a
    /// handful of layers and hangs the words off elements that are not views at all.
    private static func harvest(
        _ node: Any, into found: inout [String], seen: inout Set<ObjectIdentifier>
    ) {
        guard let object = node as? NSObject,
            seen.insert(ObjectIdentifier(object)).inserted
        else { return }

        if let label = object.accessibilityLabel, !label.isEmpty { found.append(label) }
        if let value = object.accessibilityValue, !value.isEmpty { found.append(value) }

        if let elements = object.accessibilityElements {
            for element in elements { harvest(element, into: &found, seen: &seen) }
        } else {
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                for index in 0..<count {
                    guard let element = object.accessibilityElement(at: index) else { continue }
                    harvest(element, into: &found, seen: &seen)
                }
            }
        }

        if let view = object as? UIView {
            for subview in view.subviews { harvest(subview, into: &found, seen: &seen) }
        }
    }
}
