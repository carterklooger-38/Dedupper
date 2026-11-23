import Foundation

public protocol Trashing: Sendable {
    func trash(_ url: URL) throws -> URL?
}

public struct FileManagerTrash: Trashing {
    public init() {}

    public func trash(_ url: URL) throws -> URL? {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }
}

public protocol TrashExecuting: Sendable {
    func execute(_ plan: DeletionPlan) async -> ExecutionReport
}

public struct TrashExecutor: TrashExecuting {
    private let validator: any SafetyValidating
    private let trashService: any Trashing

    public init(
        validator: any SafetyValidating = SafetyValidator(),
        trash: any Trashing = FileManagerTrash()
    ) {
        self.validator = validator
        trashService = trash
    }

    public func execute(_ plan: DeletionPlan) async -> ExecutionReport {
        await Task.detached(priority: .userInitiated) {
            executeSynchronously(plan)
        }.value
    }

    private func executeSynchronously(_ plan: DeletionPlan) -> ExecutionReport {
        var outcomes: [FileActionOutcome] = []
        var movedBytes: UInt64 = 0

        for item in plan.items {
            if Task.isCancelled {
                outcomes.append(.skipped(url: item.file.url, reason: "Operation cancelled"))
                continue
            }

            switch validator.validate(item) {
            case .valid:
                do {
                    let resultingURL = try trashService.trash(item.file.url)
                    outcomes.append(
                        .trashed(original: item.file.url, resultingURL: resultingURL)
                    )
                    movedBytes += item.file.byteSize
                } catch {
                    outcomes.append(
                        .failed(url: item.file.url, message: error.localizedDescription)
                    )
                }
            case let .invalid(reason):
                outcomes.append(.skipped(url: item.file.url, reason: reason))
            }
        }

        return ExecutionReport(outcomes: outcomes, movedBytes: movedBytes)
    }
}
