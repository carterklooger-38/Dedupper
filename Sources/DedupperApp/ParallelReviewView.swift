import DedupperCore
import SwiftUI

struct ParallelReviewView: View {
    @Bindable var model: AppModel
    let quickLook: QuickLookCoordinator
    @FocusState private var focusedFileURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.visibleGroups.isEmpty {
                ContentUnavailableView(
                    "No Duplicate Groups",
                    systemImage: "doc.on.doc",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.visibleGroups) { group in
                    groupRow(group)
                }
                .listStyle(.inset)
            }
        }
        .focusable()
        .onKeyPress(.space) {
            showQuickLook()
        }
        .toolbar { toolbarContent }
    }

    private var header: some View {
        HStack(spacing: 16) {
            folderHeader("Original", url: model.originalURL, alignment: .leading)
            Spacer(minLength: 120)
            folderHeader("Backup", url: model.backupURL, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func folderHeader(
        _ title: String,
        url: URL?,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title).font(.headline)
            Text(url?.path(percentEncoded: false) ?? "Not selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func groupRow(_ group: DuplicateGroup) -> some View {
        VStack(spacing: 10) {
            HStack {
                Label(group.kind.rawValue, systemImage: group.kind.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(group.kind.tint)
                    .accessibilityLabel("Duplicate type: \(group.kind.rawValue)")
                Text("\(group.files.count) copies · \(formattedBytes(group.files.first?.byteSize ?? 0)) each")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                groupActions(group)
            }

            HStack(alignment: .top, spacing: 18) {
                fileColumn(group.files.filter { $0.side == .original }, emptyLabel: "No matching copy in Original")
                Divider()
                fileColumn(group.files.filter { $0.side == .backup }, emptyLabel: "No matching copy in Backup")
            }
        }
        .padding(.vertical, 8)
    }

    private func fileColumn(_ files: [ScannedFile], emptyLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if files.isEmpty {
                Text(emptyLabel)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            } else {
                ForEach(files) { file in
                    fileRow(file)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func fileRow(_ file: ScannedFile) -> some View {
        let marked = model.markedURLs.contains(file.url)
        return HStack(alignment: .top, spacing: 9) {
            Button {
                model.toggleMarked(file.url)
                focusedFileURL = file.url
            } label: {
                Image(systemName: marked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(marked ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(marked ? "Keep \(file.url.lastPathComponent)" : "Mark \(file.url.lastPathComponent) for Trash")

            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(file.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(formattedBytes(file.byteSize)) · \(file.modificationDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(focusedFileURL == file.url ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .focusable()
        .focused($focusedFileURL, equals: file.url)
        .onTapGesture { focusedFileURL = file.url }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.url.lastPathComponent), \(file.side.rawValue), \(marked ? "marked for Trash" : "kept")")
    }

    private func groupActions(_ group: DuplicateGroup) -> some View {
        Menu("Group Actions") {
            Button("Delete Original Side", role: .destructive) {
                model.mark(groupIDs: [group.id], side: .original)
            }
            Button("Delete Backup Side", role: .destructive) {
                model.mark(groupIDs: [group.id], side: .backup)
            }
            Button("Delete All Copies", role: .destructive) {
                model.mark(groupIDs: [group.id], side: nil)
            }
            Divider()
            Button("Keep All") { model.keepAll(in: [group.id]) }
        }
        .menuStyle(.borderlessButton)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            TextField("Filter by name or path", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
            Picker("Type", selection: $model.kindFilter) {
                Text("All Types").tag(nil as DuplicateKind?)
                ForEach(DuplicateKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind as DuplicateKind?)
                }
            }
            .frame(width: 160)
            Picker("Sort", selection: $model.sortOrder) {
                Text("Largest First").tag(ResultSortOrder.size)
                Text("Path").tag(ResultSortOrder.path)
            }
            .frame(width: 130)
            Button("Select All Visible") { model.selectAllVisible() }
            Menu("Batch Presets") {
                Button("Keep Original · Delete Backup", role: .destructive) {
                    model.mark(
                        groupIDs: Set(model.visibleGroups.map(\.id)),
                        side: .backup
                    )
                }
                Button("Keep Backup · Delete Original", role: .destructive) {
                    model.mark(
                        groupIDs: Set(model.visibleGroups.map(\.id)),
                        side: .original
                    )
                }
                Button("Delete Both Sides", role: .destructive) {
                    model.mark(
                        groupIDs: Set(model.visibleGroups.map(\.id)),
                        side: nil
                    )
                }
            }
            Button("Clear") { model.clearSelection() }
                .disabled(model.markedURLs.isEmpty)
            Button("Review Delete", role: .destructive) {
                model.presentVerification()
            }
            .tint(.red)
            .disabled(model.markedURLs.isEmpty)
        }
    }

    private var emptyDescription: String {
        model.groups.isEmpty
            ? "The selected folders contain no exact duplicate files."
            : "No duplicate groups match the current filter."
    }

    private func showQuickLook() -> KeyPress.Result {
        guard let focusedFileURL,
              let group = model.groups.first(where: { $0.files.contains { $0.url == focusedFileURL } }) else {
            return .ignored
        }
        quickLook.show(urls: group.files.map(\.url), selectedURL: focusedFileURL)
        return .handled
    }

    private func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

extension DuplicateKind {
    var symbolName: String {
        switch self {
        case .withinOriginal, .withinBackup: "square.stack.3d.up"
        case .acrossFolders: "arrow.left.arrow.right"
        case .acrossAndWithin: "square.stack.3d.up.fill"
        }
    }

    var tint: Color {
        switch self {
        case .withinOriginal: .orange
        case .withinBackup: .yellow
        case .acrossFolders: .blue
        case .acrossAndWithin: .purple
        }
    }
}
