import Foundation
import XCTest
@testable import DedupperCore

final class FileEnumeratorTests: XCTestCase {
    func testEnumeratesNestedFilesOnBothSidesAndSkipsSymbolicLinks() async throws {
        let fixture = try TwoFolderFixture()
        try fixture.write("one", to: "Original/nested/a.txt")
        try fixture.write("two", to: "Backup/b.txt")
        try fixture.symlink(
            "Original/link.txt",
            destination: fixture.url("Original/nested/a.txt")
        )

        let result = try await FileEnumerator().inventory(for: fixture.pair)

        XCTAssertEqual(Set(result.files.map(\.relativePath)), ["nested/a.txt", "b.txt"])
        XCTAssertEqual(
            result.skips.first(where: { $0.url.lastPathComponent == "link.txt" })?.reason,
            .symbolicLink
        )
    }

    func testSkipsPackageAndItsContents() async throws {
        let fixture = try TwoFolderFixture()
        try fixture.write("inside", to: "Original/Demo.app/Contents/file.txt")
        try fixture.write("outside", to: "Backup/file.txt")

        let result = try await FileEnumerator().inventory(for: fixture.pair)

        XCTAssertFalse(result.files.contains { $0.relativePath.contains("Demo.app") })
        XCTAssertEqual(
            result.skips.first(where: { $0.url.lastPathComponent == "Demo.app" })?.reason,
            .package
        )
    }

    func testRecordsCorrectSideSizeAndRelativePath() async throws {
        let fixture = try TwoFolderFixture()
        let fileURL = try fixture.write("hello", to: "Original/deep/file.txt")

        let result = try await FileEnumerator().inventory(for: fixture.pair)
        let file = try XCTUnwrap(result.files.first)

        XCTAssertEqual(file.url, canonicalTestURL(fileURL))
        XCTAssertEqual(file.side, .original)
        XCTAssertEqual(file.relativePath, "deep/file.txt")
        XCTAssertEqual(file.byteSize, 5)
    }

    func testCancelledTaskThrowsCancellationError() async throws {
        let fixture = try TwoFolderFixture()
        try fixture.write("data", to: "Original/file.txt")

        let task = Task {
            try Task.checkCancellation()
            return try await FileEnumerator().inventory(for: fixture.pair)
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
