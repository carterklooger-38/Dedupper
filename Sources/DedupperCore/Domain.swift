import Foundation

public enum FolderSide: String, CaseIterable, Codable, Sendable {
    case original
    case backup
}

public struct FolderPair: Equatable, Sendable {
    public let original: URL
    public let backup: URL

    public init(original: URL, backup: URL) {
        self.original = original
        self.backup = backup
    }

    public subscript(side: FolderSide) -> URL {
        side == .original ? original : backup
    }
}

public struct ScannedFile: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let side: FolderSide
    public let relativePath: String
    public let byteSize: UInt64
    public let modificationDate: Date

    public init(
        url: URL,
        side: FolderSide,
        relativePath: String,
        byteSize: UInt64,
        modificationDate: Date
    ) {
        self.url = url
        self.side = side
        self.relativePath = relativePath
        self.byteSize = byteSize
        self.modificationDate = modificationDate
    }
}

public struct ScanSkip: Hashable, Sendable {
    public enum Reason: String, Sendable {
        case package
        case symbolicLink
        case alias
        case unreadable
        case metadataFailure
    }

    public let url: URL
    public let reason: Reason

    public init(url: URL, reason: Reason) {
        self.url = url
        self.reason = reason
    }
}

public struct ScanInventory: Sendable {
    public let files: [ScannedFile]
    public let skips: [ScanSkip]

    public init(files: [ScannedFile], skips: [ScanSkip]) {
        self.files = files
        self.skips = skips
    }
}

public enum DuplicateKind: String, CaseIterable, Sendable {
    case withinOriginal = "Within Original"
    case withinBackup = "Within Backup"
    case acrossFolders = "Across Folders"
    case acrossAndWithin = "Across + Within"
}

public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let digest: String
    public let files: [ScannedFile]

    public init(id: String? = nil, digest: String, files: [ScannedFile]) {
        self.id = id ?? digest
        self.digest = digest
        self.files = files.sorted {
            ($0.side.rawValue, $0.relativePath) < ($1.side.rawValue, $1.relativePath)
        }
    }

    public var kind: DuplicateKind {
        let originalCount = files.count { $0.side == .original }
        let backupCount = files.count { $0.side == .backup }
        if backupCount == 0 { return .withinOriginal }
        if originalCount == 0 { return .withinBackup }
        if originalCount == 1 && backupCount == 1 { return .acrossFolders }
        return .acrossAndWithin
    }
}

public struct PlannedDeletion: Hashable, Sendable {
    public let groupID: String
    public let expectedDigest: String
    public let file: ScannedFile

    public init(groupID: String, expectedDigest: String, file: ScannedFile) {
        self.groupID = groupID
        self.expectedDigest = expectedDigest
        self.file = file
    }
}

public struct DeletionPlan: Sendable {
    public let items: [PlannedDeletion]
    public let groupsLosingAllCopies: Set<String>

    public init(items: [PlannedDeletion], groupsLosingAllCopies: Set<String>) {
        self.items = items
        self.groupsLosingAllCopies = groupsLosingAllCopies
    }

    public var totalBytes: UInt64 {
        items.reduce(0) { $0 + $1.file.byteSize }
    }
}

public enum FileActionOutcome: Sendable {
    case trashed(original: URL, resultingURL: URL?)
    case skipped(url: URL, reason: String)
    case failed(url: URL, message: String)
}

public struct ExecutionReport: Sendable {
    public let outcomes: [FileActionOutcome]
    public let movedBytes: UInt64

    public init(outcomes: [FileActionOutcome], movedBytes: UInt64 = 0) {
        self.outcomes = outcomes
        self.movedBytes = movedBytes
    }

    public var movedCount: Int {
        outcomes.reduce(into: 0) { count, outcome in
            if case .trashed = outcome { count += 1 }
        }
    }
}
