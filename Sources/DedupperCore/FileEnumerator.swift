import Darwin
import Foundation

public protocol FileEnumerating: Sendable {
    func inventory(for pair: FolderPair) async throws -> ScanInventory
}

public struct FileEnumerator: FileEnumerating {
    public init() {}

    public func inventory(for pair: FolderPair) async throws -> ScanInventory {
        try await Task.detached(priority: .userInitiated) {
            try inventorySynchronously(for: pair)
        }.value
    }

    private func inventorySynchronously(for pair: FolderPair) throws -> ScanInventory {
        try Task.checkCancellation()
        var files: [ScannedFile] = []
        var skips: [ScanSkip] = []

        for side in FolderSide.allCases {
            let root = canonicalURL(pair[side], isDirectory: true)
            let keys: Set<URLResourceKey> = [
                .isRegularFileKey,
                .isPackageKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
                .isReadableKey,
                .fileSizeKey,
                .contentModificationDateKey
            ]
            let errorHandler: (URL, Error) -> Bool = { url, _ in
                skips.append(ScanSkip(url: url, reason: .unreadable))
                return true
            }

            guard let iterator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsPackageDescendants],
                errorHandler: errorHandler
            ) else {
                skips.append(ScanSkip(url: root, reason: .unreadable))
                continue
            }

            for case let url as URL in iterator {
                try Task.checkCancellation()
                do {
                    let values = try url.resourceValues(forKeys: keys)
                    if values.isPackage == true {
                        skips.append(ScanSkip(url: url, reason: .package))
                        continue
                    }
                    if values.isSymbolicLink == true {
                        skips.append(ScanSkip(url: url, reason: .symbolicLink))
                        continue
                    }
                    if values.isAliasFile == true {
                        skips.append(ScanSkip(url: url, reason: .alias))
                        continue
                    }
                    if values.isReadable == false {
                        skips.append(ScanSkip(url: url, reason: .unreadable))
                        continue
                    }
                    guard values.isRegularFile == true,
                          let size = values.fileSize,
                          let date = values.contentModificationDate else {
                        continue
                    }

                    let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
                    files.append(
                        ScannedFile(
                            url: url,
                            side: side,
                            relativePath: String(url.path.dropFirst(prefix.count)),
                            byteSize: UInt64(size),
                            modificationDate: date
                        )
                    )
                } catch {
                    skips.append(ScanSkip(url: url, reason: .metadataFailure))
                }
            }
        }

        return ScanInventory(
            files: files.sorted { $0.url.path < $1.url.path },
            skips: skips.sorted { $0.url.path < $1.url.path }
        )
    }

    private func canonicalURL(_ url: URL, isDirectory: Bool) -> URL {
        url.withUnsafeFileSystemRepresentation { representation in
            guard let representation, let resolved = realpath(representation, nil) else {
                return url.standardizedFileURL
            }
            defer { free(resolved) }
            return URL(
                fileURLWithFileSystemRepresentation: resolved,
                isDirectory: isDirectory,
                relativeTo: nil
            )
        }
    }
}
