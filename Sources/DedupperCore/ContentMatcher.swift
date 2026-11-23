import CryptoKit
import Foundation

public protocol ContentHashing: Sendable {
    func digest(of url: URL) throws -> String
}

public protocol ByteComparing: Sendable {
    func equal(_ lhs: URL, _ rhs: URL) throws -> Bool
}

public protocol ContentMatching: Sendable {
    func groups(from files: [ScannedFile]) async throws -> [DuplicateGroup]
}

public struct SHA256FileHasher: ContentHashing {
    public init() {}

    public func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else {
                break
            }
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct FileByteComparer: ByteComparing {
    public init() {}

    public func equal(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let left = try FileHandle(forReadingFrom: lhs)
        let right = try FileHandle(forReadingFrom: rhs)
        defer {
            try? left.close()
            try? right.close()
        }

        while true {
            try Task.checkCancellation()
            let leftData = try left.read(upToCount: 1_048_576) ?? Data()
            let rightData = try right.read(upToCount: 1_048_576) ?? Data()
            if leftData != rightData { return false }
            if leftData.isEmpty { return true }
        }
    }
}

public struct ContentMatcher: ContentMatching {
    private let hasher: any ContentHashing
    private let comparer: any ByteComparing

    public init(
        hasher: any ContentHashing = SHA256FileHasher(),
        comparer: any ByteComparing = FileByteComparer()
    ) {
        self.hasher = hasher
        self.comparer = comparer
    }

    public func groups(from files: [ScannedFile]) async throws -> [DuplicateGroup] {
        try await Task.detached(priority: .userInitiated) {
            try groupsSynchronously(from: files)
        }.value
    }

    private func groupsSynchronously(from files: [ScannedFile]) throws -> [DuplicateGroup] {
        try Task.checkCancellation()
        let sizeBuckets = Dictionary(grouping: files, by: \.byteSize)
        var result: [DuplicateGroup] = []

        for size in sizeBuckets.keys.sorted(by: >) {
            try Task.checkCancellation()
            guard let candidates = sizeBuckets[size], candidates.count > 1 else { continue }

            var digestBuckets: [String: [ScannedFile]] = [:]
            for file in candidates.sorted(by: { $0.url.path < $1.url.path }) {
                try Task.checkCancellation()
                digestBuckets[try hasher.digest(of: file.url), default: []].append(file)
            }

            for digest in digestBuckets.keys.sorted() {
                guard let candidates = digestBuckets[digest], candidates.count > 1 else { continue }
                let confirmed = try byteConfirmedPartitions(candidates).filter { $0.count > 1 }
                for (index, partition) in confirmed.enumerated() {
                    let id = confirmed.count == 1 ? digest : "\(digest)-\(index)"
                    result.append(DuplicateGroup(id: id, digest: digest, files: partition))
                }
            }
        }

        return result.sorted {
            let leftSize = $0.files.first?.byteSize ?? 0
            let rightSize = $1.files.first?.byteSize ?? 0
            return leftSize == rightSize ? $0.id < $1.id : leftSize > rightSize
        }
    }

    private func byteConfirmedPartitions(_ candidates: [ScannedFile]) throws -> [[ScannedFile]] {
        var partitions: [[ScannedFile]] = []
        for candidate in candidates {
            try Task.checkCancellation()
            var matchingIndex: Int?
            for index in partitions.indices {
                if let representative = partitions[index].first,
                   try comparer.equal(representative.url, candidate.url) {
                    matchingIndex = index
                    break
                }
            }
            if let matchingIndex {
                partitions[matchingIndex].append(candidate)
            } else {
                partitions.append([candidate])
            }
        }
        return partitions
    }
}
