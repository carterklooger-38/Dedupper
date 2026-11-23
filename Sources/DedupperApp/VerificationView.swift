import DedupperCore
import SwiftUI

struct VerificationView: View {
    @Bindable var model: AppModel
    let plan: DeletionPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Verify Files Moving to Trash", systemImage: "trash")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.red)
                Text("Review every affected path. Nothing moves until you press the final red button.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                summary("Groups", value: "\(groupCount)")
                summary("Files", value: "\(plan.items.count)")
                summary("Original", value: "\(originalCount)")
                summary("Backup", value: "\(backupCount)")
                summary("Moved to Trash", value: formattedBytes(plan.totalBytes))
            }

            if !plan.groupsLosingAllCopies.isEmpty {
                Label(
                    "Every known copy will be removed for \(plan.groupsLosingAllCopies.count) duplicate \(plan.groupsLosingAllCopies.count == 1 ? "group" : "groups").",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.headline)
                .foregroundStyle(.red)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }

            List(plan.items, id: \.file.url) { item in
                HStack {
                    Image(systemName: item.file.side == .original ? "arrow.left.circle" : "arrow.right.circle")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.file.url.lastPathComponent)
                            .font(.body.weight(.medium))
                        Text(item.file.url.path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(item.file.side.rawValue.capitalized)
                        .font(.caption)
                    Text(formattedBytes(item.file.byteSize))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Cancel") { model.cancelVerification() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Verify and Move to Trash", role: .destructive) {
                    Task { await model.confirmDeletion() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(28)
    }

    private var groupCount: Int {
        Set(plan.items.map(\.groupID)).count
    }

    private var originalCount: Int {
        plan.items.count { $0.file.side == .original }
    }

    private var backupCount: Int {
        plan.items.count { $0.file.side == .backup }
    }

    private func summary(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct CompletionReportView: View {
    @Bindable var model: AppModel
    let report: ExecutionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Trash Operation Complete", systemImage: "checkmark.circle.fill")
                .font(.largeTitle.bold())
                .foregroundStyle(.green)
            Text("\(report.movedCount) files moved to Trash · \(formattedBytes(report.movedBytes))")
                .font(.headline)
            Text("Files continue to use storage until the macOS Trash is emptied.")
                .foregroundStyle(.secondary)

            List(Array(report.outcomes.enumerated()), id: \.offset) { _, outcome in
                outcomeRow(outcome)
            }

            HStack {
                Button("New Scan") { model.newScan() }
                Spacer()
                Button("Back to Results") { model.backToResults() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
    }

    @ViewBuilder
    private func outcomeRow(_ outcome: FileActionOutcome) -> some View {
        switch outcome {
        case let .trashed(original, _):
            Label {
                VStack(alignment: .leading) {
                    Text(original.lastPathComponent)
                    Text("Moved to Trash").font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case let .skipped(url, reason):
            Label {
                VStack(alignment: .leading) {
                    Text(url.lastPathComponent)
                    Text("Skipped: \(reason)").font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "forward.circle.fill").foregroundStyle(.orange)
            }
        case let .failed(url, message):
            Label {
                VStack(alignment: .leading) {
                    Text(url.lastPathComponent)
                    Text("Failed: \(message)").font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
    }

    private func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
