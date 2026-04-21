import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class ImageGridModel {
    var folderURL: URL?
    var items: [GridImageItem] = []
    var isLoading = false
    var isExporting = false
    var exportProgress: Double = 0
    var exportedFrames = 0
    var totalFramesToExport = 0
    var statusMessage: String?
    var showGridOverlay = true

    var eligibleItems: [GridImageItem] { items.filter { $0.is16x9 } }
    var selectedCount: Int { items.reduce(0) { $0 + ($1.isSelected ? 1 : 0) } }
    var hasSelection: Bool { selectedCount > 0 }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder of 16:9 grid images"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await load(from: url) }
    }

    func load(from folderURL: URL) async {
        self.folderURL = folderURL
        self.items = []
        self.isLoading = true
        self.statusMessage = nil

        let loaded = await GridImageLoader.loadFolder(folderURL)
        self.items = loaded
        self.isLoading = false

        let valid = loaded.filter { $0.is16x9 }.count
        let skipped = loaded.count - valid
        if loaded.isEmpty {
            self.statusMessage = "No supported images found in that folder."
        } else if skipped > 0 {
            self.statusMessage = "Loaded \(valid) × 16:9 image(s). Skipped \(skipped) non-16:9 file(s)."
        } else {
            self.statusMessage = "Loaded \(valid) image(s)."
        }
    }

    func toggle(_ item: GridImageItem) {
        guard item.is16x9,
              let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isSelected.toggle()
    }

    func selectAll() {
        for i in items.indices where items[i].is16x9 {
            items[i].isSelected = true
        }
    }

    func deselectAll() {
        for i in items.indices {
            items[i].isSelected = false
        }
    }

    func exportSelected() {
        let selected = items.filter { $0.isSelected && $0.is16x9 }
        guard !selected.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose an output folder for exported frames"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        isExporting = true
        exportProgress = 0
        exportedFrames = 0
        totalFramesToExport = selected.count * 9
        statusMessage = nil

        let jobs = selected.map { (url: $0.url, id: $0.id) }

        Task {
            let (totalFrames, errors) = await runExport(jobs: jobs, outputURL: outputURL)
            isExporting = false

            if errors.isEmpty {
                statusMessage = "Exported \(totalFrames) frame(s) to \(outputURL.lastPathComponent)."
            } else {
                statusMessage = "Exported \(totalFrames) frame(s). \(errors.count) file(s) failed."
            }
        }
    }

    private func runExport(
        jobs: [(url: URL, id: UUID)],
        outputURL: URL
    ) async -> (Int, [String]) {
        await withTaskGroup(of: GridExportResult.self) { group in
            for job in jobs {
                group.addTask {
                    GridExporter.export(sourceURL: job.url, itemID: job.id, to: outputURL)
                }
            }

            var totalFrames = 0
            var errors: [String] = []
            for await result in group {
                totalFrames += result.framesWritten
                if let err = result.error { errors.append(err) }
                exportedFrames = totalFrames
                exportProgress = Double(totalFrames) / Double(max(totalFramesToExport, 1))
            }
            return (totalFrames, errors)
        }
    }
}
