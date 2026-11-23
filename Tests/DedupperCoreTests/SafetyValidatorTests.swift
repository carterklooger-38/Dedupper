import Foundation
import XCTest
@testable import DedupperCore

final class SafetyValidatorTests: XCTestCase {
    func testAcceptsUnchangedFile() throws {
        let fixture = try TwoFolderFixture()
        let file = try fixture.record(contents: "same", path: "Original/file")
        let item = try plannedDeletion(for: file)

        XCTAssertEqual(SafetyValidator().validate(item), .valid)
    }

    func testRejectsMissingFile() throws {
        let fixture = try TwoFolderFixture()
        let file = try fixture.record(contents: "same", path: "Original/file")
        let item = try plannedDeletion(for: file)
        try FileManager.default.removeItem(at: file.url)

        assertInvalid(SafetyValidator().validate(item), contains: "missing")
    }

    func testRejectsChangedSize() throws {
        let fixture = try TwoFolderFixture()
        let file = try fixture.record(contents: "same", path: "Original/file")
        let item = try plannedDeletion(for: file)
        try Data("different-size".utf8).write(to: file.url)

        assertInvalid(SafetyValidator().validate(item), contains: "size changed")
    }

    func testRejectsChangedModificationDate() throws {
        let fixture = try TwoFolderFixture()
        let file = try fixture.record(contents: "same", path: "Original/file")
        let item = try plannedDeletion(for: file)
        try FileManager.default.setAttributes(
            [.modificationDate: file.modificationDate.addingTimeInterval(60)],
            ofItemAtPath: file.url.path
        )

        assertInvalid(SafetyValidator().validate(item), contains: "modification date changed")
    }

    func testRejectsChangedDigestEvenWhenSizeAndDateMatch() throws {
        let fixture = try TwoFolderFixture()
        let file = try fixture.record(contents: "AAAA", path: "Original/file")
        let originalDigest = try SHA256FileHasher().digest(of: file.url)
        try Data("BBBB".utf8).write(to: file.url)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
        let currentDate = try XCTUnwrap(attributes[.modificationDate] as? Date)
        let currentMetadata = ScannedFile(
            url: file.url,
            side: file.side,
            relativePath: file.relativePath,
            byteSize: file.byteSize,
            modificationDate: currentDate
        )
        let item = PlannedDeletion(
            groupID: "group",
            expectedDigest: originalDigest,
            file: currentMetadata
        )

        assertInvalid(SafetyValidator().validate(item), contains: "contents changed")
    }

    private func plannedDeletion(for file: ScannedFile) throws -> PlannedDeletion {
        PlannedDeletion(
            groupID: "group",
            expectedDigest: try SHA256FileHasher().digest(of: file.url),
            file: file
        )
    }

    private func assertInvalid(
        _ result: ValidationResult,
        contains text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .invalid(reason) = result else {
            return XCTFail("Expected invalid result", file: file, line: line)
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains(text), "Reason was: \(reason)", file: file, line: line)
    }
}
