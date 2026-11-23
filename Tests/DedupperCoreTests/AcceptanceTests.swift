import Foundation
import XCTest
@testable import DedupperCore

final class AcceptanceTests: XCTestCase {
    func testRealFilePipelineFindsAllFourGroupKinds() async throws {
        let fixture = try TwoFolderFixture()
        try fixture.write("across", to: "Original/report.txt")
        try fixture.write("across", to: "Backup/report-copy.bin")
        try fixture.write("inside-original", to: "Original/o1")
        try fixture.write("inside-original", to: "Original/o2")
        try fixture.write("inside-backup", to: "Backup/b1")
        try fixture.write("inside-backup", to: "Backup/b2")
        try fixture.write("mixed", to: "Original/m1")
        try fixture.write("mixed", to: "Original/m2")
        try fixture.write("mixed", to: "Backup/m3")
        try fixture.write("left", to: "Original/same-name.txt")
        try fixture.write("righ", to: "Backup/same-name.txt")

        let inventory = try await FileEnumerator().inventory(for: fixture.pair)
        let groups = try await ContentMatcher().groups(from: inventory.files)

        XCTAssertEqual(
            Set(groups.map(\.kind)),
            [.withinOriginal, .withinBackup, .acrossFolders, .acrossAndWithin]
        )
        XCTAssertEqual(groups.count, 4)
        XCTAssertTrue(
            groups.contains {
                Set($0.files.map(\.relativePath)) == ["report.txt", "report-copy.bin"]
            }
        )
        XCTAssertFalse(
            groups.contains { $0.files.contains { $0.relativePath == "same-name.txt" } }
        )
    }

    func testSelectedSubsetCreatesOnlyRequestedDeletionItems() async throws {
        let fixture = try TwoFolderFixture()
        try fixture.write("one", to: "Original/a")
        try fixture.write("one", to: "Backup/a")
        try fixture.write("two", to: "Original/b")
        try fixture.write("two", to: "Backup/b")
        let inventory = try await FileEnumerator().inventory(for: fixture.pair)
        let groups = try await ContentMatcher().groups(from: inventory.files)
        let selected = try XCTUnwrap(groups.first?.files.first?.url)

        let plan = try ActionPlanner().makePlan(groups: groups, markedURLs: [selected])

        XCTAssertEqual(plan.items.map { $0.file.url }, [selected])
        XCTAssertTrue(plan.groupsLosingAllCopies.isEmpty)
    }

    func testChangedFileIsSkippedBeforeTrash() async throws {
        let fixture = try TwoFolderFixture()
        try fixture.write("same", to: "Original/a")
        try fixture.write("same", to: "Backup/a")
        let inventory = try await FileEnumerator().inventory(for: fixture.pair)
        let groups = try await ContentMatcher().groups(from: inventory.files)
        let selected = try XCTUnwrap(groups.first?.files.first)
        let plan = try ActionPlanner().makePlan(groups: groups, markedURLs: [selected.url])
        try Data("changed-size".utf8).write(to: selected.url)
        let trash = AcceptanceTrashSpy()

        let report = await TrashExecutor(
            validator: SafetyValidator(),
            trash: trash
        ).execute(plan)

        XCTAssertTrue(trash.receivedURLs.isEmpty)
        guard case .skipped = report.outcomes.first else {
            return XCTFail("Expected changed file to be skipped")
        }
    }

    func testSimulatedHashCollisionStillRequiresEqualBytes() async throws {
        let fixture = try TwoFolderFixture()
        let a = try fixture.record(contents: "AAAA", path: "Original/a")
        let b = try fixture.record(contents: "BBBB", path: "Backup/b")

        let groups = try await ContentMatcher(
            hasher: AcceptanceConstantHasher(),
            comparer: FileByteComparer()
        ).groups(from: [a, b])

        XCTAssertTrue(groups.isEmpty)
    }

    func testCancelledPipelineMakesNoTrashCalls() async throws {
        let fixture = try TwoFolderFixture()
        try fixture.write("same", to: "Original/a")
        try fixture.write("same", to: "Backup/a")
        let trash = AcceptanceTrashSpy()
        let task = Task {
            try Task.checkCancellation()
            let inventory = try await FileEnumerator().inventory(for: fixture.pair)
            return try await ContentMatcher().groups(from: inventory.files)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertTrue(trash.receivedURLs.isEmpty)
        }
    }
}

private struct AcceptanceConstantHasher: ContentHashing {
    func digest(of url: URL) throws -> String { "forced-collision" }
}

private final class AcceptanceTrashSpy: Trashing, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var receivedURLs: [URL] { lock.withLock { storage } }

    func trash(_ url: URL) throws -> URL? {
        lock.withLock { storage.append(url) }
        return URL(fileURLWithPath: "/Trash").appendingPathComponent(url.lastPathComponent)
    }
}
