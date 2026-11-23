import Foundation

public enum ActionPlanningError: Error, Equatable, Sendable {
    case fileOutsideResults(URL)
}

public protocol ActionPlanning: Sendable {
    func markedURLs(
        in groups: [DuplicateGroup],
        groupIDs: Set<String>,
        side: FolderSide?
    ) -> Set<URL>

    func makePlan(
        groups: [DuplicateGroup],
        markedURLs: Set<URL>
    ) throws -> DeletionPlan
}

public struct ActionPlanner: ActionPlanning {
    public init() {}

    public func markedURLs(
        in groups: [DuplicateGroup],
        groupIDs: Set<String>,
        side: FolderSide?
    ) -> Set<URL> {
        Set(
            groups
                .filter { groupIDs.contains($0.id) }
                .flatMap { group in
                    group.files
                        .filter { side == nil || $0.side == side }
                        .map(\.url)
                }
        )
    }

    public func makePlan(
        groups: [DuplicateGroup],
        markedURLs: Set<URL>
    ) throws -> DeletionPlan {
        typealias Entry = (groupID: String, digest: String, file: ScannedFile)
        let lookup: [URL: Entry] = Dictionary(
            uniqueKeysWithValues: groups.flatMap { group in
                group.files.map { file in
                    (file.url, (group.id, group.digest, file))
                }
            }
        )

        for url in markedURLs where lookup[url] == nil {
            throw ActionPlanningError.fileOutsideResults(url)
        }

        let items = markedURLs.compactMap { lookup[$0] }
            .map { entry in
                PlannedDeletion(
                    groupID: entry.groupID,
                    expectedDigest: entry.digest,
                    file: entry.file
                )
            }
            .sorted { $0.file.url.path < $1.file.url.path }

        let groupsLosingAllCopies = Set(
            groups
                .filter { Set($0.files.map(\.url)).isSubset(of: markedURLs) }
                .map(\.id)
        )

        return DeletionPlan(
            items: items,
            groupsLosingAllCopies: groupsLosingAllCopies
        )
    }
}
