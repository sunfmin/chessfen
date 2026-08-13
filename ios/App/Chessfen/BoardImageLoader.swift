import ChessfenKit
import ImageIO
import PhotosUI
import SwiftUI
import UIKit

/// Getting a picture of a board into the shape the recogniser wants, from any of the four
/// places one can come from: the camera, the photo library, the clipboard, a file.
///
/// Everything is scaled down on the way in. A recent iPhone hands over a 48-megapixel
/// photograph, which as a `RGBImage` is 144 MB of bytes for a board the recogniser reads at
/// 1200 pixels; decoding straight to a thumbnail avoids ever holding the full thing.
enum BoardImageLoader {
    /// A little above the recogniser's own working resolution, so that straightening a
    /// photograph has some detail to work with before it downsamples again.
    static let longestSide = 1600

    static func image(from data: Data) -> RGBImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return image(from: source)
    }

    static func image(fromFileAt url: URL) -> RGBImage? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return image(from: source)
    }

    /// The camera hands over a `UIImage` whose orientation lives in metadata; drawing it
    /// once settles that as well as bounding its size.
    static func image(from uiImage: UIImage) -> RGBImage? {
        let longest = max(uiImage.size.width, uiImage.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, CGFloat(longestSide) / longest)
        let target = CGSize(
            width: (uiImage.size.width * scale).rounded(),
            height: (uiImage.size.height * scale).rounded()
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let flattened = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            uiImage.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let cgImage = flattened.cgImage else { return nil }
        return RGBImage(cgImage: cgImage)
    }

    static func fromClipboard() -> RGBImage? {
        guard let image = UIPasteboard.general.image else { return nil }
        return self.image(from: image)
    }

    static var clipboardHasImage: Bool { UIPasteboard.general.hasImages }

    private static func image(from source: CGImageSource) -> RGBImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
            // Photographs carry their rotation in EXIF. Without this a board shot in
            // portrait arrives on its side, and every square is in the wrong place.
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard
            let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source, 0, options as CFDictionary
            )
        else { return nil }
        return RGBImage(cgImage: cgImage)
    }
}

/// An `RGBImage` as something SwiftUI can show.
extension Image {
    init?(rgb: RGBImage) {
        guard let cgImage = rgb.cgImage else { return nil }
        self.init(decorative: cgImage, scale: 1, orientation: .up)
    }
}
