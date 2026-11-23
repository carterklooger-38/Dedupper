import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    let picker: any FolderPicking
    let quickLook: QuickLookCoordinator

    var body: some View {
        Group {
            switch model.phase {
            case .selectingFolders:
                folderSelection
            case .scanning:
                scanning
            case .reviewing:
                ParallelReviewView(model: model, quickLook: quickLook)
            case .verifying:
                if let plan = model.pendingPlan {
                    VerificationView(model: model, plan: plan)
                } else {
                    ContentUnavailableView("No Deletion Plan", systemImage: "exclamationmark.triangle")
                }
            case .executing:
                ProgressView("Moving verified files to Trash…")
            case .completed:
                if let report = model.executionReport {
                    CompletionReportView(model: model, report: report)
                } else {
                    ContentUnavailableView("No Completion Report", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .frame(minWidth: 1_000, minHeight: 650)
    }

    private var folderSelection: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("Compare Two Folders")
                    .font(.largeTitle.bold())
                Text("Dedupper finds byte-identical files locally and changes nothing until you verify a Trash action.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            folderChoice(title: "Original", url: model.originalURL) {
                model.originalURL = await picker.chooseFolder(title: "Choose Original Folder")
            }
            folderChoice(title: "Backup", url: model.backupURL) {
                model.backupURL = await picker.chooseFolder(title: "Choose Backup Folder")
            }
            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            Button("Scan for Exact Duplicates") {
                Task { await model.startScan() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.originalURL == nil || model.backupURL == nil)
        }
        .padding(48)
        .frame(maxWidth: 720)
    }

    private func folderChoice(
        title: String,
        url: URL?,
        choose: @escaping @MainActor () async -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(url?.path(percentEncoded: false) ?? "No folder selected")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Choose…") { Task { await choose() } }
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var scanning: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning and confirming exact matches…")
                .font(.headline)
            Text("Files are read locally. Nothing is being changed.")
                .foregroundStyle(.secondary)
            Button("Cancel") { model.cancelScan() }
        }
    }
}
