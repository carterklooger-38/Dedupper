import DedupperCore
import Foundation
import Observation

enum AppPhase: Equatable {
    case selectingFolders
    case scanning
    case reviewing
    case verifying
    case executing
    case completed
}

enum ResultSortOrder: Equatable {
    case size
    case path
}

@MainActor
@Observable
final class AppModel {
    var originalURL: URL?
    var backupURL: URL?
    private(set) var phase: AppPhase = .selectingFolders
    private(set) var groups: [DuplicateGroup] = []
    private(set) var scanSkips: [ScanSkip] = []
    var markedURLs: Set<URL> = []
    var searchText = ""
    var kindFilter: DuplicateKind?
    var sortOrder: ResultSortOrder = .size
    private(set) var errorMessage: String?
    private(set) var pendingPlan: DeletionPlan?
    private(set) var executionReport: ExecutionReport?

    private let validator: any FolderPairValidating
    private let enumerator: any FileEnumerating
    private let matcher: any ContentMatching
    private let planner: any ActionPlanning
    private let executor: any TrashExecuting
    private var scanTask: Task<(ScanInventory, [DuplicateGroup]), Error>?

    init(
        validator: any FolderPairValidating,
        enumerator: any FileEnumerating,
        matcher: any ContentMatching,
        planner: any ActionPlanning,
        executor: any TrashExecuting
    ) {
        self.validator = validator
        self.enumerator = enumerator
        self.matcher = matcher
        self.planner = planner
        self.executor = executor
    }

    static func live() -> AppModel {
        AppModel(
            validator: FolderPairValidator(),
            enumerator: FileEnumerator(),
            matcher: ContentMatcher(),
            planner: ActionPlanner(),
            executor: TrashExecutor()
        )
    }

    var visibleGroups: [DuplicateGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups
            .filter { group in
                guard kindFilter == nil || group.kind == kindFilter else { return false }
                guard !query.isEmpty else { return true }
                return group.files.contains { file in
                    file.url.lastPathComponent.localizedCaseInsensitiveContains(query)
                        || file.relativePath.localizedCaseInsensitiveContains(query)
                }
            }
            .sorted { left, right in
                switch sortOrder {
                case .size:
                    let leftSize = left.files.first?.byteSize ?? 0
                    let rightSize = right.files.first?.byteSize ?? 0
                    return leftSize == rightSize ? left.id < right.id : leftSize > rightSize
                case .path:
                    let leftPath = left.files.first?.relativePath ?? ""
                    let rightPath = right.files.first?.relativePath ?? ""
                    return leftPath.localizedStandardCompare(rightPath) == .orderedAscending
                }
            }
    }

    func startScan() async {
        errorMessage = nil
        pendingPlan = nil
        executionReport = nil
        guard let originalURL, let backupURL else {
            phase = .selectingFolders
            errorMessage = "Choose both an Original and a Backup folder."
            return
        }

        let pair: FolderPair
        do {
            pair = try validator.validate(original: originalURL, backup: backupURL)
        } catch let error as FolderPairValidationError {
            phase = .selectingFolders
            errorMessage = message(for: error)
            return
        } catch {
            phase = .selectingFolders
            errorMessage = error.localizedDescription
            return
        }

        phase = .scanning
        let enumerator = self.enumerator
        let matcher = self.matcher
        let task = Task {
            let inventory = try await enumerator.inventory(for: pair)
            let groups = try await matcher.groups(from: inventory.files)
            return (inventory, groups)
        }
        scanTask = task

        do {
            let (inventory, matchedGroups) = try await task.value
            guard !Task.isCancelled else { throw CancellationError() }
            groups = matchedGroups
            scanSkips = inventory.skips
            markedURLs = []
            phase = .reviewing
        } catch is CancellationError {
            phase = .selectingFolders
        } catch {
            phase = .selectingFolders
            errorMessage = error.localizedDescription
        }
        scanTask = nil
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func toggleMarked(_ url: URL) {
        if markedURLs.contains(url) {
            markedURLs.remove(url)
        } else {
            markedURLs.insert(url)
        }
    }

    func selectAllVisible() {
        markedURLs.formUnion(visibleGroups.flatMap { $0.files.map(\.url) })
    }

    func clearSelection() {
        markedURLs.removeAll()
    }

    func mark(groupIDs: Set<String>, side: FolderSide?) {
        markedURLs.formUnion(
            planner.markedURLs(in: groups, groupIDs: groupIDs, side: side)
        )
    }

    func keepAll(in groupIDs: Set<String>) {
        let urls = planner.markedURLs(in: groups, groupIDs: groupIDs, side: nil)
        markedURLs.subtract(urls)
    }

    @discardableResult
    func presentVerification() -> Bool {
        guard !markedURLs.isEmpty else { return false }
        do {
            pendingPlan = try planner.makePlan(groups: groups, markedURLs: markedURLs)
            phase = .verifying
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func cancelVerification() {
        pendingPlan = nil
        phase = .reviewing
    }

    func confirmDeletion() async {
        guard phase == .verifying, let plan = pendingPlan else { return }
        phase = .executing
        let report = await executor.execute(plan)

        var removedURLs: Set<URL> = []
        for outcome in report.outcomes {
            switch outcome {
            case let .trashed(original, _):
                removedURLs.insert(original)
            case let .skipped(url, _):
                if !FileManager.default.fileExists(atPath: url.path) {
                    removedURLs.insert(url)
                }
            case .failed:
                break
            }
        }

        groups = groups.compactMap { group in
            let remaining = group.files.filter { !removedURLs.contains($0.url) }
            guard remaining.count > 1 else { return nil }
            return DuplicateGroup(
                id: group.id,
                digest: group.digest,
                files: remaining
            )
        }
        markedURLs.subtract(plan.items.map { $0.file.url })
        pendingPlan = nil
        executionReport = report
        phase = .completed
    }

    func backToResults() {
        phase = .reviewing
    }

    func newScan() {
        scanTask?.cancel()
        scanTask = nil
        originalURL = nil
        backupURL = nil
        groups = []
        scanSkips = []
        markedURLs = []
        searchText = ""
        kindFilter = nil
        sortOrder = .size
        errorMessage = nil
        pendingPlan = nil
        executionReport = nil
        phase = .selectingFolders
    }

    private func message(for error: FolderPairValidationError) -> String {
        switch error {
        case .missingFolder(.original): "The Original folder is no longer available."
        case .missingFolder(.backup): "The Backup folder is no longer available."
        case .notDirectory(.original): "The Original selection is not a folder."
        case .notDirectory(.backup): "The Backup selection is not a folder."
        case .sameFolder: "Choose two different folders."
        case .overlappingFolders: "Choose folders that do not contain one another."
        }
    }
}
