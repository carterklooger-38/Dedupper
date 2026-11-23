import XCTest
@testable import DedupperCore

final class DomainTests: XCTestCase {
    func testDuplicateKindUsesFileDistribution() {
        let original1 = ScannedFile.fixture("/original/a", side: .original)
        let original2 = ScannedFile.fixture("/original/b", side: .original)
        let backup1 = ScannedFile.fixture("/backup/a", side: .backup)
        let backup2 = ScannedFile.fixture("/backup/b", side: .backup)

        XCTAssertEqual(
            DuplicateGroup(digest: "1", files: [original1, original2]).kind,
            .withinOriginal
        )
        XCTAssertEqual(
            DuplicateGroup(digest: "2", files: [backup1, backup2]).kind,
            .withinBackup
        )
        XCTAssertEqual(
            DuplicateGroup(digest: "3", files: [original1, backup1]).kind,
            .acrossFolders
        )
        XCTAssertEqual(
            DuplicateGroup(digest: "4", files: [original1, original2, backup1, backup2]).kind,
            .acrossAndWithin
        )
    }
}
