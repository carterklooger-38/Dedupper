import Foundation
import XCTest
@testable import DedupperApp
@testable import DedupperCore

@MainActor
final class AppModelTests: XCTestCase {
    func testScanWaitsForBothFolders() async {
        let fixture = try! TemporaryAppFolders()
        let model = makeModel(groups: [])
        model.originalURL = fixture.original

        await model.startScan()

        XCTAssertEqual(model.phase, .selectingFolders)
        XCTAssertEqual(model.errorMessage, "Choose both an Original and a Backup folder.")
    }

    func testInvalidPairShowsValidationError() async throws {
        let fixture = try TemporaryAppFolders()
        let model = makeModel(groups: [])
        model.originalURL = fixture.original
        model.backupURL = fixture.original

        await model.startScan()

        XCTAssertEqual(model.phase, .selectingFolders)
        XCTAssertEqual(model.errorMessage, "Choose two different folders.")
    }

    func testSuccessfulScanPublishesGroupsAndSkips() async throws {
        let fixture = try TemporaryAppFolders()
        let groups = makeGroups()
        let skip = ScanSkip(url: fixture.original.appendingPathComponent("link"), reason: .symbolicLink)
        let model = makeModel(groups: groups, skips: [skip])
        model.originalURL = fixture.original
        model.backupURL = fixture.backup

        await model.startScan()

        XCTAssertEqual(model.phase, .reviewing)
        XCTAssertEqual(model.groups, groups)
        XCTAssertEqual(model.scanSkips, [skip])
        XCTAssertNil(model.errorMessage)
    }

    func testVisibleGroupsApplyKindAndCaseInsensitivePathFilter() async throws {
        let fixture = try TemporaryAppFolders()
        let model = makeModel(groups: makeGroups())
        model.originalURL = fixture.original
        model.backupURL = fixture.backup
        await model.startScan()

        model.kindFilter = .withinOriginal
        XCTAssertEqual(model.visibleGroups.map(\.id), ["photo"])

        model.kindFilter = nil
        model.searchText = "REPORT"
        XCTAssertEqual(model.visibleGroups.map(\.id), ["report"])
    }

    func testSelectAllVisibleDoesNotSelectFilteredOutFiles() async throws {
        let fixture = try TemporaryAppFolders()
        let groups = makeGroups()
        let model = makeModel(groups: groups)
        model.originalURL = fixture.original
        model.backupURL = fixture.backup
        await model.startScan()
        model.kindFilter = .withinOriginal

        model.selectAllVisible()

        XCTAssertEqual(model.markedURLs, Set(groups[1].files.map(\.url)))
    }

    func testMarkedFilesSurviveSortingAndCanCreateVerificationPlan() async throws {
        let fixture = try TemporaryAppFolders()
        let groups = makeGroups()
        let model = makeModel(groups: groups)
        model.originalURL = fixture.original
        model.backupURL = fixture.backup
        await model.startScan()
        let selected = try XCTUnwrap(groups[0].files.first?.url)

        model.toggleMarked(selected)
        model.sortOrder = .path
        let presented = model.presentVerification()

        XCTAssertTrue(presented)
        XCTAssertEqual(model.phase, .verifying)
        XCTAssertEqual(model.pendingPlan?.items.map { $0.file.url }, [selected])
    }

    func testEmptySelectionCannotOpenVerification() async throws {
        let fixture = try TemporaryAppFolders()
        let model = makeModel(groups: makeGroups())
        model.originalURL = fixture.original
        model.backupURL = fixture.backup
        await model.startScan()

        XCTAssertFalse(model.presentVerification())
        XCTAssertEqual(model.phase, .reviewing)
        XCTAssertNil(model.pendingPlan)
    }

    func testCancellingVerificationKeepsMarksAndReturnsToReview() async throws {
        let fixture = try TemporaryAppFolders()
        let groups = makeGroups()
        let model = makeModel(groups: groups)
        model.originalURL = fixture.original
        model.backupURL = fixture.backup
        await model.startScan()
        let selected = try XCTUnwrap(groups[0].files.first?.url)
        model.toggleMarked(selected)
        XCTAssertTrue(model.presentVerification())

        model.cancelVerification()

        XCTAssertEqual(model.phase, .reviewing)
        XCTAssertEqual(model.markedURLs, [selected])
        XCTAssertNil(model.pendingPlan)
    }

    func testConfirmedExecutionRefreshesGroupsAndStoresReport() async throws {
        let fixture = try TemporaryAppFolders()
        let groups = makeGroups()
        let selected = try XCTUnwrap(groups[0].files.first?.url)
        let report = ExecutionReport(outcomes: [
            .trashed(original: selected, resultingURL: URL(fileURLWithPath: "/Trash/item"))
        ])
        let model = makeModel(groups: groups, report: report)
        model.originalURL = fixture.original
        model.backupURL = fixture.backup
        await model.startScan()
        model.toggleMarked(selected)
        XCTAssertTrue(model.presentVerification())

        await model.confirmDeletion()

        XCTAssertEqual(model.phase, .completed)
        XCTAssertEqual(model.executionReport?.movedCount, 1)
        XCTAssertEqual(model.groups.map(\.id), ["photo"])
        XCTAssertTrue(model.markedURLs.isEmpty)
        XCTAssertNil(model.pendingPlan)
    }

    func testNewScanClearsWorkflowState() async throws {
        let fixture = try TemporaryAppFolders()
        let groups = makeGroups()
        let model = makeModel(groups: groups)
        model.originalURL = fixture.original
        model.backupURL = fixture.backup
        await model.startScan()
        model.searchText = "report"
        model.kindFilter = .acrossFolders
        model.selectAllVisible()

        model.newScan()

        XCTAssertEqual(model.phase, .selectingFolders)
        XCTAssertNil(model.originalURL)
        XCTAssertNil(model.backupURL)
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertTrue(model.markedURLs.isEmpty)
        XCTAssertEqual(model.searchText, "")
        XCTAssertNil(model.kindFilter)
    }

    private func makeModel(
        groups: [DuplicateGroup],
        skips: [ScanSkip] = [],
        report: ExecutionReport = ExecutionReport(outcomes: [])
    ) -> AppModel {
        AppModel(
            validator: FolderPairValidator(),
            enumerator: InventoryStub(inventory: ScanInventory(files: groups.flatMap(\.files), skips: skips)),
            matcher: MatcherStub(groups: groups),
            planner: ActionPlanner(),
            executor: ExecutorStub(report: report)
        )
    }

    private func makeGroups() -> [DuplicateGroup] {
        [
            DuplicateGroup(
                id: "report",
                digest: "digest-report",
                files: [
                    appFile("/Original/Annual Report.pdf", side: .original),
                    appFile("/Backup/report-copy.pdf", side: .backup)
                ]
            ),
            DuplicateGroup(
                id: "photo",
                digest: "digest-photo",
                files: [
                    appFile("/Original/Photos/photo.jpg", side: .original),
                    appFile("/Original/Photos/photo copy.jpg", side: .original)
                ]
            )
        ]
    }

    private func appFile(_ path: String, side: FolderSide) -> ScannedFile {
        ScannedFile(
            url: URL(fileURLWithPath: path),
            side: side,
            relativePath: path,
            byteSize: 10,
            modificationDate: .distantPast
        )
    }
}

private struct InventoryStub: FileEnumerating {
    let inventory: ScanInventory
    func inventory(for pair: FolderPair) async throws -> ScanInventory { inventory }
}

private struct MatcherStub: ContentMatching {
    let groups: [DuplicateGroup]
    func groups(from files: [ScannedFile]) async throws -> [DuplicateGroup] { groups }
}

private struct ExecutorStub: TrashExecuting {
    let report: ExecutionReport
    func execute(_ plan: DeletionPlan) async -> ExecutionReport { report }
}

private final class TemporaryAppFolders {
    let root: URL
    let original: URL
    let backup: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DedupperAppTests-\(UUID().uuidString)", isDirectory: true)
        original = root.appendingPathComponent("Original", isDirectory: true)
        backup = root.appendingPathComponent("Backup", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}
