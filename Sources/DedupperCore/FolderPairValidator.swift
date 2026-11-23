import Foundation

public enum FolderPairValidationError: Error, Equatable, Sendable {
    case missingFolder(FolderSide)
    case notDirectory(FolderSide)
    case sameFolder
    case overlappingFolders
}

public protocol FolderPairValidating: Sendable {
    func validate(original: URL, backup: URL) throws -> FolderPair
}

public struct FolderPairValidator: FolderPairValidating {
    public init() {}

    public func validate(original: URL, backup: URL) throws -> FolderPair {
        let original = original.standardizedFileURL.resolvingSymlinksInPath()
        let backup = backup.standardizedFileURL.resolvingSymlinksInPath()

        try validateDirectory(original, side: .original)
        try validateDirectory(backup, side: .backup)

        guard original != backup else {
            throw FolderPairValidationError.sameFolder
        }
        guard !contains(original, backup), !contains(backup, original) else {
            throw FolderPairValidationError.overlappingFolders
        }

        return FolderPair(original: original, backup: backup)
    }

    private func validateDirectory(_ url: URL, side: FolderSide) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FolderPairValidationError.missingFolder(side)
        }
        guard isDirectory.boolValue else {
            throw FolderPairValidationError.notDirectory(side)
        }
    }

    private func contains(_ parent: URL, _ child: URL) -> Bool {
        let prefix = parent.path.hasSuffix("/") ? parent.path : parent.path + "/"
        return child.path.hasPrefix(prefix)
    }
}
