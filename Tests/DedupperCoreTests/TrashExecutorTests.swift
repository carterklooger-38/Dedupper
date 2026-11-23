import Foundation
import XCTest
@testable import DedupperCore

final class TrashExecutorTests: XCTestCase {
    func testValidFileIsTrashedAndReported() async {
        let trash = TrashSpy()
        let plan = makePlan(paths: ["/first"])

        let report = await TrashExecutor(validator: AlwaysValid(), trash: trash).execute(plan)

        XCTAssertEqual(trash.receivedURLs.map(\.path), ["/first"])
        XCTAssertEqual(report.movedCount, 1)
        XCTAssertEqual(report.movedBytes, 4)
        guard case let .trashed(original, resultingURL) = report.outcomes[0] else {
            return XCTFail("Expected trashed outcome")
        }
        XCTAssertEqual(original.path, "/first")
        XCTAssertEqual(resultingURL?.path, "/Trash/first")
    }

    func testInvalidFileNeverCallsTrash() async {
        let trash = TrashSpy()
        let report = await TrashExecutor(
            validator: AlwaysInvalid(reason: "changed"),
            trash: trash
        ).execute(makePlan(paths: ["/first"]))

        XCTAssertTrue(trash.receivedURLs.isEmpty)
        guard case let .skipped(url, reason) = report.outcomes[0] else {
            return XCTFail("Expected skipped outcome")
        }
        XCTAssertEqual(url.path, "/first")
        XCTAssertEqual(reason, "changed")
    }

    func testPartialFailureContinuesInPlanOrder() async {
        let secondURL = URL(fileURLWithPath: "/second")
        let trash = TrashSpy(failingURLs: [secondURL])
        let plan = makePlan(paths: ["/first", "/second", "/third"])

        let report = await TrashExecutor(validator: AlwaysValid(), trash: trash).execute(plan)

        XCTAssertEqual(trash.receivedURLs.map(\.path), ["/first", "/second", "/third"])
        XCTAssertEqual(report.outcomes.count, 3)
        guard case .trashed = report.outcomes[0],
              case .failed = report.outcomes[1],
              case .trashed = report.outcomes[2] else {
            return XCTFail("Expected success, failure, success in plan order")
        }
    }

    private func makePlan(paths: [String]) -> DeletionPlan {
        DeletionPlan(
            items: paths.map { path in
                PlannedDeletion(
                    groupID: "group",
                    expectedDigest: "digest",
                    file: .fixture(path, side: .original)
                )
            },
            groupsLosingAllCopies: []
        )
    }
}

private struct AlwaysValid: SafetyValidating {
    func validate(_ item: PlannedDeletion) -> ValidationResult { .valid }
}

private struct AlwaysInvalid: SafetyValidating {
    let reason: String
    func validate(_ item: PlannedDeletion) -> ValidationResult { .invalid(reason) }
}

private enum TrashSpyError: Error { case refused }

private final class TrashSpy: Trashing, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    private let failingURLs: Set<URL>

    init(failingURLs: Set<URL> = []) {
        self.failingURLs = failingURLs
    }

    var receivedURLs: [URL] {
        lock.withLock { storage }
    }

    func trash(_ url: URL) throws -> URL? {
        lock.withLock { storage.append(url) }
        if failingURLs.contains(url) { throw TrashSpyError.refused }
        return URL(fileURLWithPath: "/Trash").appendingPathComponent(url.lastPathComponent)
    }
}
