import Darwin
import Foundation
import XCTest
@testable import DedupperCore

extension ScannedFile {
    static func fixture(
        _ path: String,
        side: FolderSide,
        size: UInt64 = 4,
        date: Date = .distantPast
    ) -> Self {
        .init(
            url: URL(fileURLWithPath: path),
            side: side,
            relativePath: URL(fileURLWithPath: path).lastPathComponent,
            byteSize: size,
            modificationDate: date
        )
    }
}

final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DedupperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func makeDirectory(_ relativePath: String) throws -> URL {
        let directory = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func write(_ contents: String, to relativePath: String) throws -> URL {
        let file = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: file)
        return file
    }
}

final class TwoFolderFixture {
    let root: TemporaryDirectory
    let original: URL
    let backup: URL
    let pair: FolderPair

    init() throws {
        root = try TemporaryDirectory()
        original = try root.makeDirectory("Original")
        backup = try root.makeDirectory("Backup")
        pair = FolderPair(original: original, backup: backup)
    }

    func url(_ relativePath: String) -> URL {
        root.url.appendingPathComponent(relativePath)
    }

    @discardableResult
    func write(_ contents: String, to relativePath: String) throws -> URL {
        try root.write(contents, to: relativePath)
    }

    func symlink(_ relativePath: String, destination: URL) throws {
        let link = url(relativePath)
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
    }

    func record(contents: String, path: String) throws -> ScannedFile {
        let fileURL = try write(contents, to: path)
        let canonicalURL = canonicalTestURL(fileURL)
        let values = try canonicalURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let side: FolderSide = path.hasPrefix("Original/") ? .original : .backup
        let prefix = side == .original ? "Original/" : "Backup/"
        return ScannedFile(
            url: canonicalURL,
            side: side,
            relativePath: String(path.dropFirst(prefix.count)),
            byteSize: UInt64(try XCTUnwrap(values.fileSize)),
            modificationDate: try XCTUnwrap(values.contentModificationDate)
        )
    }
}

func canonicalTestURL(_ url: URL, isDirectory: Bool = false) -> URL {
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
