import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum GridImageLoader {
    nonisolated static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tif", "tiff", "heic", "heif", "bmp", "webp"
    ]

    nonisolated static func loadFolder(_ folderURL: URL) async -> [GridImageItem] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let imageURLs = contents
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        return await withTaskGroup(of: (Int, GridImageItem?).self) { group in
            for (idx, url) in imageURLs.enumerated() {
                group.addTask { (idx, loadItem(from: url)) }
            }
            var pairs: [(Int, GridImageItem)] = []
            for await (idx, maybeItem) in group {
                if let item = maybeItem { pairs.append((idx, item)) }
            }
            return pairs.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    nonisolated static func loadItem(from url: URL) -> GridImageItem? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return nil }

        let width = (props[kCGImagePropertyPixelWidth] as? Double) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? Double) ?? 0
        guard width > 0, height > 0 else { return nil }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 800,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary)

        return GridImageItem(
            id: UUID(),
            url: url,
            pixelSize: CGSize(width: width, height: height),
            thumbnail: thumb,
            isSelected: false
        )
    }
}

struct GridExportResult: Sendable {
    let itemID: UUID
    let framesWritten: Int
    let error: String?
}

enum GridExporter {
    nonisolated static func export(
        sourceURL: URL,
        itemID: UUID,
        to outputFolder: URL,
        quality: CGFloat = 0.92
    ) -> GridExportResult {
        guard let src = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let fullImage = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else {
            return GridExportResult(itemID: itemID, framesWritten: 0,
                                    error: "Unable to read \(sourceURL.lastPathComponent)")
        }

        let w = fullImage.width
        let h = fullImage.height
        guard w >= 3, h >= 3 else {
            return GridExportResult(itemID: itemID, framesWritten: 0,
                                    error: "Image too small to split: \(sourceURL.lastPathComponent)")
        }

        let cellW = w / 3
        let cellH = h / 3
        let code = randomHexCode()
        var written = 0
        var frameIdx = 1

        for row in 0..<3 {
            for col in 0..<3 {
                let rect = CGRect(x: col * cellW,
                                  y: row * cellH,
                                  width: cellW,
                                  height: cellH)
                if let cropped = fullImage.cropping(to: rect) {
                    let filename = String(format: "frame-%@-%02d.jpg", code, frameIdx)
                    let outURL = outputFolder.appendingPathComponent(filename)
                    if writeJPG(cropped, to: outURL, quality: quality) {
                        written += 1
                    }
                }
                frameIdx += 1
            }
        }

        return GridExportResult(itemID: itemID, framesWritten: written, error: nil)
    }

    nonisolated private static func writeJPG(_ image: CGImage, to url: URL, quality: CGFloat) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return false }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    nonisolated private static func randomHexCode(length: Int = 6) -> String {
        let chars: [Character] = Array("0123456789ABCDEF")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}
