import Foundation
import XCTest
@testable import DedupperCore

final class FolderPairValidatorTests: XCTestCase {
    func testAcceptsSiblingFolders() throws {
        let root = try TemporaryDirectory()
        let original = try root.makeDirectory("Original")
        let backup = try root.makeDirectory("Backup")

        let pair = try FolderPairValidator().validate(original: original, backup: backup)

        XCTAssertEqual(pair.original, original.standardizedFileURL)
        XCTAssertEqual(pair.backup, backup.standardizedFileURL)
    }

    func testRejectsSameFolder() throws {
        let root = try TemporaryDirectory()
        let folder = try root.makeDirectory("Same")

        assertValidationError(.sameFolder) {
            try FolderPairValidator().validate(original: folder, backup: folder)
        }
    }

    func testRejectsNestedFolderInEitherDirection() throws {
        let root = try TemporaryDirectory()
        let original = try root.makeDirectory("Original")
        let nested = try root.makeDirectory("Original/Backup")

        assertValidationError(.overlappingFolders) {
            try FolderPairValidator().validate(original: original, backup: nested)
        }
        assertValidationError(.overlappingFolders) {
            try FolderPairValidator().validate(original: nested, backup: original)
        }
    }

    func testRejectsMissingFolderOnEitherSide() throws {
        let root = try TemporaryDirectory()
        let existing = try root.makeDirectory("Existing")

        assertValidationError(.missingFolder(.original)) {
            try FolderPairValidator().validate(
                original: root.url.appendingPathComponent("Missing"),
                backup: existing
            )
        }
        assertValidationError(.missingFolder(.backup)) {
            try FolderPairValidator().validate(
                original: existing,
                backup: root.url.appendingPathComponent("Missing")
            )
        }
    }

    func testRejectsRegularFileOnEitherSide() throws {
        let root = try TemporaryDirectory()
        let folder = try root.makeDirectory("Folder")
        let file = try root.write("data", to: "file.txt")

        assertValidationError(.notDirectory(.original)) {
            try FolderPairValidator().validate(original: file, backup: folder)
        }
        assertValidationError(.notDirectory(.backup)) {
            try FolderPairValidator().validate(original: folder, backup: file)
        }
    }

    private func assertValidationError<T>(
        _ expected: FolderPairValidationError,
        operation: () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? FolderPairValidationError, expected, file: file, line: line)
        }
    }
}
