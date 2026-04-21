import Foundation
import CoreGraphics

struct GridImageItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let pixelSize: CGSize
    let thumbnail: CGImage?
    var isSelected: Bool

    var filename: String { url.lastPathComponent }

    var aspectRatio: CGFloat {
        guard pixelSize.height > 0 else { return 0 }
        return pixelSize.width / pixelSize.height
    }

    var is16x9: Bool {
        abs(aspectRatio - 16.0 / 9.0) < 0.02
    }

    static func == (lhs: GridImageItem, rhs: GridImageItem) -> Bool {
        lhs.id == rhs.id && lhs.isSelected == rhs.isSelected
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension GridImageItem: @unchecked Sendable {}
