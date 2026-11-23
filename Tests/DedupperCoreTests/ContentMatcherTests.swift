import Foundation
import XCTest
@testable import DedupperCore

final class ContentMatcherTests: XCTestCase {
    func testMatchesSameBytesWithDifferentNamesAcrossFolders() async throws {
        let fixture = try TwoFolderFixture()
        let original = try fixture.record(contents: "identical", path: "Original/report.txt")
        let backup = try fixture.record(contents: "identical", path: "Backup/copy.bin")

        let groups = try await ContentMatcher().groups(from: [original, backup])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].kind, .acrossFolders)
        XCTAssertEqual(Set(groups[0].files.map(\.url)), [original.url, backup.url])
    }

    func testDoesNotMatchSameNameWithDifferentBytes() async throws {
        let fixture = try TwoFolderFixture()
        let original = try fixture.record(contents: "AAAA", path: "Original/file.txt")
        let backup = try fixture.record(contents: "BBBB", path: "Backup/file.txt")

        let groups = try await ContentMatcher().groups(from: [original, backup])
        XCTAssertEqual(groups, [])
    }

    func testClassifiesWithinOriginalWithinBackupAndMixedGroups() async throws {
        let fixture = try TwoFolderFixture()
        let files = try [
            fixture.record(contents: "original-only", path: "Original/o1"),
            fixture.record(contents: "original-only", path: "Original/o2"),
            fixture.record(contents: "backup-only", path: "Backup/b1"),
            fixture.record(contents: "backup-only", path: "Backup/b2"),
            fixture.record(contents: "mixed", path: "Original/m1"),
            fixture.record(contents: "mixed", path: "Original/m2"),
            fixture.record(contents: "mixed", path: "Backup/m3")
        ]

        let groups = try await ContentMatcher().groups(from: files)

        XCTAssertEqual(Set(groups.map(\.kind)), [.withinOriginal, .withinBackup, .acrossAndWithin])
    }

    func testExcludesSingletonAndIncludesDuplicateEmptyFiles() async throws {
        let fixture = try TwoFolderFixture()
        let singleton = try fixture.record(contents: "single", path: "Original/single")
        let empty1 = try fixture.record(contents: "", path: "Original/empty")
        let empty2 = try fixture.record(contents: "", path: "Backup/empty")

        let groups = try await ContentMatcher().groups(from: [singleton, empty1, empty2])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].files.map(\.url)), [empty1.url, empty2.url])
    }

    func testByteConfirmationSplitsSimulatedHashCollision() async throws {
        let fixture = try TwoFolderFixture()
        let a1 = try fixture.record(contents: "AAAA", path: "Original/a1")
        let a2 = try fixture.record(contents: "AAAA", path: "Backup/a2")
        let b1 = try fixture.record(contents: "BBBB", path: "Original/b1")
        let b2 = try fixture.record(contents: "BBBB", path: "Backup/b2")
        let matcher = ContentMatcher(
            hasher: ConstantHasher(value: "collision"),
            comparer: FileByteComparer()
        )

        let groups = try await matcher.groups(from: [a1, b2, a2, b1])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.digest)), ["collision"])
        XCTAssertEqual(Set(groups.map(\.id)), ["collision-0", "collision-1"])
        XCTAssertEqual(Set(groups.map { Set($0.files.map(\.url)) }), [Set([a1.url, a2.url]), Set([b1.url, b2.url])])
    }

    func testResultsSortByDescendingSizeThenID() async throws {
        let fixture = try TwoFolderFixture()
        let small1 = try fixture.record(contents: "aa", path: "Original/small")
        let small2 = try fixture.record(contents: "aa", path: "Backup/small")
        let large1 = try fixture.record(contents: "larger", path: "Original/large")
        let large2 = try fixture.record(contents: "larger", path: "Backup/large")

        let groups = try await ContentMatcher().groups(from: [small1, large1, small2, large2])

        XCTAssertEqual(groups.map { $0.files[0].byteSize }, [6, 2])
    }

    func testCancelledTaskThrowsCancellationError() async throws {
        let fixture = try TwoFolderFixture()
        let first = try fixture.record(contents: "same", path: "Original/a")
        let second = try fixture.record(contents: "same", path: "Backup/b")
        let task = Task {
            try Task.checkCancellation()
            return try await ContentMatcher().groups(from: [first, second])
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }
}

private struct ConstantHasher: ContentHashing {
    let value: String
    func digest(of url: URL) throws -> String { value }
}
