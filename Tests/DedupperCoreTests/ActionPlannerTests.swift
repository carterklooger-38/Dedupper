import Foundation
import XCTest
@testable import DedupperCore

final class ActionPlannerTests: XCTestCase {
    func testMarksOnlyRequestedSideOfSelectedGroups() {
        let groups = makeGroups()
        let planner = ActionPlanner()

        let original = planner.markedURLs(
            in: groups,
            groupIDs: ["mixed"],
            side: .original
        )
        let backup = planner.markedURLs(
            in: groups,
            groupIDs: ["mixed"],
            side: .backup
        )
        let all = planner.markedURLs(
            in: groups,
            groupIDs: ["mixed"],
            side: nil
        )

        XCTAssertEqual(original, [URL(fileURLWithPath: "/original/m1"), URL(fileURLWithPath: "/original/m2")])
        XCTAssertEqual(backup, [URL(fileURLWithPath: "/backup/m3")])
        XCTAssertEqual(all, original.union(backup))
    }

    func testMakesDeterministicPlanForIndividualFilesAndCountsPhysicalBytes() throws {
        let groups = makeGroups()
        let marked: Set<URL> = [
            URL(fileURLWithPath: "/backup/m3"),
            URL(fileURLWithPath: "/original/a")
        ]

        let plan = try ActionPlanner().makePlan(groups: groups, markedURLs: marked)

        XCTAssertEqual(plan.items.map { $0.file.url.path }, ["/backup/m3", "/original/a"])
        XCTAssertEqual(plan.totalBytes, 14)
        XCTAssertEqual(plan.groupsLosingAllCopies, [])
    }

    func testMarksGroupAsLosingAllCopiesOnlyWhenEveryFileIsSelected() throws {
        let groups = makeGroups()
        let allAcross = Set(groups[0].files.map(\.url))

        let complete = try ActionPlanner().makePlan(groups: groups, markedURLs: allAcross)
        let partial = try ActionPlanner().makePlan(
            groups: groups,
            markedURLs: [try XCTUnwrap(groups[0].files.first).url]
        )

        XCTAssertEqual(complete.groupsLosingAllCopies, ["across"])
        XCTAssertEqual(partial.groupsLosingAllCopies, [])
    }

    func testRejectsURLOutsideScanResults() {
        let unknown = URL(fileURLWithPath: "/elsewhere/unknown")

        XCTAssertThrowsError(
            try ActionPlanner().makePlan(groups: makeGroups(), markedURLs: [unknown])
        ) { error in
            XCTAssertEqual(error as? ActionPlanningError, .fileOutsideResults(unknown))
        }
    }

    func testEmptySelectionProducesEmptyPlan() throws {
        let plan = try ActionPlanner().makePlan(groups: makeGroups(), markedURLs: [])
        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertTrue(plan.groupsLosingAllCopies.isEmpty)
        XCTAssertEqual(plan.totalBytes, 0)
    }

    private func makeGroups() -> [DuplicateGroup] {
        [
            DuplicateGroup(
                id: "across",
                digest: "digest-a",
                files: [
                    .fixture("/original/a", side: .original, size: 7),
                    .fixture("/backup/a", side: .backup, size: 7)
                ]
            ),
            DuplicateGroup(
                id: "mixed",
                digest: "digest-m",
                files: [
                    .fixture("/original/m1", side: .original, size: 7),
                    .fixture("/original/m2", side: .original, size: 7),
                    .fixture("/backup/m3", side: .backup, size: 7)
                ]
            )
        ]
    }
}
