import SwiftUI
import AppKit

struct ContentView: View {
    @State private var model = ImageGridModel()

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            toolbar(bindable: model)
            Divider()
            content
            Divider()
            statusBar
        }
        .frame(minWidth: 900, minHeight: 620)
        .overlay {
            if model.isExporting {
                ExportOverlay(
                    progress: model.exportProgress,
                    exported: model.exportedFrames,
                    total: model.totalFramesToExport
                )
            }
        }
    }

    private func toolbar(bindable model: ImageGridModel) -> some View {
        HStack(spacing: 10) {
            Button {
                model.pickFolder()
            } label: {
                Label("Choose Folder…", systemImage: "folder")
            }

            Divider().frame(height: 18)

            Button("Select All") { model.selectAll() }
                .disabled(model.eligibleItems.isEmpty)
                .keyboardShortcut("a", modifiers: [.command])

            Button("Deselect All") { model.deselectAll() }
                .disabled(!model.hasSelection)

            Spacer()

            Toggle("Show grid", isOn: $model.showGridOverlay)
                .toggleStyle(.checkbox)

            Button {
                model.exportSelected()
            } label: {
                Label("Export Selected…", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(!model.hasSelection || model.isExporting)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Loading images…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            emptyState
        } else {
            gridView
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("No folder selected")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Choose a folder of 16:9 grid images to get started.")
                .foregroundStyle(.secondary)
            Button("Choose Folder…") { model.pickFolder() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)],
                spacing: 14
            ) {
                ForEach(model.items) { item in
                    GridThumbnailView(
                        item: item,
                        showGrid: model.showGridOverlay
                    ) {
                        model.toggle(item)
                    }
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if let url = model.folderURL {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let msg = model.statusMessage {
                Text(msg)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if !model.items.isEmpty {
                Text("\(model.selectedCount) / \(model.eligibleItems.count) selected")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct GridThumbnailView: View {
    let item: GridImageItem
    let showGrid: Bool
    let onToggle: () -> Void

    private var borderColor: Color {
        if !item.is16x9 { return .secondary.opacity(0.4) }
        return item.isSelected ? Color.accentColor : Color.secondary.opacity(0.3)
    }

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    thumbnail
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            if showGrid && item.is16x9 {
                                GridOverlay()
                                    .stroke(.white.opacity(0.65), lineWidth: 1)
                                    .blendMode(.plusLighter)
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(borderColor, lineWidth: item.isSelected ? 3 : 1)
                        }

                    if item.is16x9 {
                        SelectionBadge(isSelected: item.isSelected)
                            .padding(8)
                    } else {
                        InvalidBadge()
                            .padding(8)
                    }
                }

                Text(item.filename)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(Int(item.pixelSize.width)) × \(Int(item.pixelSize.height))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .buttonStyle(.plain)
        .disabled(!item.is16x9)
        .opacity(item.is16x9 ? 1 : 0.55)
        .help(item.is16x9
              ? item.filename
              : "\(item.filename) — not 16:9, cannot export")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let cg = item.thumbnail {
            Image(decorative: cg, scale: 1.0)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

struct GridOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width / 3
        let h = rect.height / 3
        for i in 1...2 {
            path.move(to: CGPoint(x: rect.minX + w * CGFloat(i), y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + w * CGFloat(i), y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + h * CGFloat(i)))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * CGFloat(i)))
        }
        return path
    }
}

struct SelectionBadge: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.black.opacity(0.45))
                .frame(width: 26, height: 26)
            Image(systemName: isSelected ? "checkmark" : "circle")
                .font(.system(size: isSelected ? 13 : 11, weight: .bold))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.9))
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

struct InvalidBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("not 16:9")
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6), in: Capsule())
        .foregroundStyle(.white)
    }
}

struct ExportOverlay: View {
    let progress: Double
    let exported: Int
    let total: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Exporting frames…")
                    .font(.headline)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 280)
                Text("\(exported) / \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(radius: 16)
        }
    }
}

#Preview {
    ContentView()
}
