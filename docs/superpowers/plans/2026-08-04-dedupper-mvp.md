# Dedupper MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use $subagent-driven-development (recommended) or $executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS app that scans two user-selected folders, groups byte-identical files within and across them, previews files with Quick Look, and moves individually or collectively selected copies to the Trash after verification.

**Architecture:** Use a Swift Package with a testable `DedupperCore` library and a native SwiftUI `DedupperApp` executable. Core services own folder validation, enumeration, hashing, byte confirmation, action planning, pre-delete revalidation, and Trash operations; the app target owns macOS folder pickers, Quick Look, presentation state, and the parallel review interface.

**Tech Stack:** Swift 6.2, Swift Package Manager, SwiftUI, AppKit, Observation, QuickLookUI, CryptoKit, XCTest, macOS 15 deployment target.

## Global Constraints

- Scan exactly two non-overlapping, user-selected folders labeled Original and Backup.
- Scan nested directories recursively and compare exact file bytes within either folder and across both folders.
- Skip packages, symbolic links, aliases, filesystem loops, and unreadable files; report skips without failing the scan.
- Keep scanning and hashing off the main actor and make scans cancellable.
- Group every byte-identical copy together and classify it as Within Original, Within Backup, Across Folders, or Across + Within.
- Preserve native Space-bar Quick Look for every listed file.
- Default to no destructive action; allow file, group, filtered Select All, and side-based batch selection.
- All red deletion actions create a reviewable plan and require a final **Verify and Move to Trash** action.
- Revalidate size, modification date, and content digest immediately before moving each file.
- Use only the macOS Trash operation; never permanently delete a file.
- Process batch results independently and report every success, skip, and failure.
- Keep all file contents, paths, hashes, and scan results local; add no network dependency or analytics.
- Distribution packaging, signing, notarization, visual similarity, semantic similarity, scheduled scans, and comparison of more than two folders are outside this plan.

## File Structure

```text
Package.swift
Sources/
  DedupperCore/
    Domain.swift                 # Folder sides, scanned files, groups, plans, and result types
    FolderPairValidator.swift    # Rejects identical, nested, missing, or non-directory selections
    FileEnumerator.swift         # Recursively records eligible files and scan skips
    ContentMatcher.swift         # Size bucketing, SHA-256 hashing, and byte confirmation
    ActionPlanner.swift          # File/group/side selection and immutable deletion plans
    SafetyValidator.swift        # Rechecks a planned file immediately before Trash
    TrashExecutor.swift          # Per-file Trash execution and partial-failure reporting
  DedupperApp/
    DedupperApp.swift            # SwiftUI entry point
    AppModel.swift               # Main-actor workflow state and service orchestration
    FolderPicker.swift           # NSOpenPanel adapter
    QuickLookCoordinator.swift   # QLPreviewPanel data source and keyboard preview state
    RootView.swift               # Folder selection, progress, results, and completion routing
    ParallelReviewView.swift     # Parallel Original/Backup group presentation and selection
    VerificationView.swift       # Destructive-action summary and final verification control
Tests/
  DedupperCoreTests/
    TestFiles.swift
    FolderPairValidatorTests.swift
    FileEnumeratorTests.swift
    ContentMatcherTests.swift
    ActionPlannerTests.swift
    SafetyValidatorTests.swift
    TrashExecutorTests.swift
  DedupperAppTests/
    AppModelTests.swift
```

---

### Task 1: Package Scaffold and Domain Model

**Files:**
- Create: `Package.swift`
- Create: `Sources/DedupperCore/Domain.swift`
- Create: `Tests/DedupperCoreTests/TestFiles.swift`
- Test: `Tests/DedupperCoreTests/DomainTests.swift`

**Interfaces:**
- Consumes: Nothing; this is the foundation task.
- Produces: `FolderSide`, `FolderPair`, `ScannedFile`, `ScanSkip`, `ScanInventory`, `DuplicateKind`, `DuplicateGroup`, `PlannedDeletion`, `DeletionPlan`, `FileActionOutcome`, and `ExecutionReport`.

- [ ] **Step 1: Create the package and write failing domain tests**

Create `Package.swift` with one core library, one app executable, and separate core/app test targets:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Dedupper",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DedupperCore", targets: ["DedupperCore"]),
        .executable(name: "Dedupper", targets: ["DedupperApp"])
    ],
    targets: [
        .target(name: "DedupperCore"),
        .executableTarget(name: "DedupperApp", dependencies: ["DedupperCore"]),
        .testTarget(name: "DedupperCoreTests", dependencies: ["DedupperCore"]),
        .testTarget(name: "DedupperAppTests", dependencies: ["DedupperApp", "DedupperCore"])
    ]
)
```

Create tests proving the four classifications:

```swift
import XCTest
@testable import DedupperCore

final class DomainTests: XCTestCase {
    func testDuplicateKindUsesFileDistribution() {
        let original1 = ScannedFile.fixture("/original/a", side: .original)
        let original2 = ScannedFile.fixture("/original/b", side: .original)
        let backup1 = ScannedFile.fixture("/backup/a", side: .backup)
        let backup2 = ScannedFile.fixture("/backup/b", side: .backup)

        XCTAssertEqual(DuplicateGroup(digest: "1", files: [original1, original2]).kind, .withinOriginal)
        XCTAssertEqual(DuplicateGroup(digest: "2", files: [backup1, backup2]).kind, .withinBackup)
        XCTAssertEqual(DuplicateGroup(digest: "3", files: [original1, backup1]).kind, .acrossFolders)
        XCTAssertEqual(DuplicateGroup(digest: "4", files: [original1, original2, backup1, backup2]).kind, .acrossAndWithin)
    }
}
```

- [ ] **Step 2: Run the domain test and verify it fails**

Run: `swift test --filter DomainTests`

Expected: compilation fails because the domain types and `ScannedFile.fixture` do not exist.

- [ ] **Step 3: Implement the domain types and shared test fixture**

Use URL as the stable in-session file identity. Make every cross-actor value `Sendable`, and sort files deterministically by side then path inside `DuplicateGroup.init`.

```swift
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

    public init(url: URL, side: FolderSide, relativePath: String, byteSize: UInt64, modificationDate: Date) {
        self.url = url
        self.side = side
        self.relativePath = relativePath
        self.byteSize = byteSize
        self.modificationDate = modificationDate
    }
}

public struct ScanSkip: Hashable, Sendable {
    public enum Reason: String, Sendable { case package, symbolicLink, alias, unreadable, metadataFailure }
    public let url: URL
    public let reason: Reason
}

public struct ScanInventory: Sendable {
    public let files: [ScannedFile]
    public let skips: [ScanSkip]
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
}

public struct DeletionPlan: Sendable {
    public let items: [PlannedDeletion]
    public let groupsLosingAllCopies: Set<String>
    public var totalBytes: UInt64 { items.reduce(0) { $0 + $1.file.byteSize } }
}

public enum FileActionOutcome: Sendable {
    case trashed(original: URL, resultingURL: URL?)
    case skipped(url: URL, reason: String)
    case failed(url: URL, message: String)
}

public struct ExecutionReport: Sendable {
    public let outcomes: [FileActionOutcome]
    public var movedCount: Int { outcomes.count { if case .trashed = $0 { true } else { false } } }
}
```

Create `Tests/DedupperCoreTests/TestFiles.swift`:

```swift
import Foundation
@testable import DedupperCore

extension ScannedFile {
    static func fixture(_ path: String, side: FolderSide, size: UInt64 = 4, date: Date = .distantPast) -> Self {
        .init(url: URL(fileURLWithPath: path), side: side, relativePath: URL(fileURLWithPath: path).lastPathComponent, byteSize: size, modificationDate: date)
    }
}
```

- [ ] **Step 4: Run the domain test**

Run: `swift test --filter DomainTests`

Expected: all four classification assertions pass.

### Task 2: Folder Pair Validation

**Files:**
- Create: `Sources/DedupperCore/FolderPairValidator.swift`
- Test: `Tests/DedupperCoreTests/FolderPairValidatorTests.swift`

**Interfaces:**
- Consumes: `FolderPair` from Task 1.
- Produces: `FolderPairValidating.validate(original:backup:) throws -> FolderPair` and `FolderPairValidationError`.

- [ ] **Step 1: Write validation tests**

Cover two valid sibling folders plus identical, nested, missing, and regular-file selections. Create temporary paths with `FileManager`, and assert the exact error case for each rejection.

```swift
func testRejectsNestedFolder() throws {
    let root = try TemporaryDirectory()
    let original = try root.makeDirectory("Original")
    let nested = try root.makeDirectory("Original/Backup")
    XCTAssertThrowsError(try FolderPairValidator().validate(original: original, backup: nested)) {
        XCTAssertEqual($0 as? FolderPairValidationError, .overlappingFolders)
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `swift test --filter FolderPairValidatorTests`

Expected: compilation fails because `FolderPairValidator` is undefined.

- [ ] **Step 3: Implement canonical-path validation**

```swift
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
        guard original != backup else { throw FolderPairValidationError.sameFolder }
        guard !contains(original, backup) && !contains(backup, original) else {
            throw FolderPairValidationError.overlappingFolders
        }
        return FolderPair(original: original, backup: backup)
    }

    private func validateDirectory(_ url: URL, side: FolderSide) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FolderPairValidationError.missingFolder(side)
        }
        guard isDirectory.boolValue else { throw FolderPairValidationError.notDirectory(side) }
    }

    private func contains(_ parent: URL, _ child: URL) -> Bool {
        child.path.hasPrefix(parent.path.hasSuffix("/") ? parent.path : parent.path + "/")
    }
}
```

- [ ] **Step 4: Run validator tests**

Run: `swift test --filter FolderPairValidatorTests`

Expected: valid siblings pass and all four invalid cases return the expected error.

### Task 3: Recursive File Enumeration

**Files:**
- Create: `Sources/DedupperCore/FileEnumerator.swift`
- Extend: `Tests/DedupperCoreTests/TestFiles.swift`
- Test: `Tests/DedupperCoreTests/FileEnumeratorTests.swift`

**Interfaces:**
- Consumes: `FolderPair`, `ScannedFile`, `ScanInventory`, and `ScanSkip`.
- Produces: `FileEnumerating.inventory(for:) async throws -> ScanInventory`.

- [ ] **Step 1: Write enumeration tests**

Create sibling Original and Backup fixtures containing nested regular files, a symbolic link, and a directory marked as a package. Assert that regular files from both sides have correct relative paths, the symlink and package are skipped, and `Task.cancel()` causes `CancellationError`.

```swift
func testEnumeratesNestedFilesOnBothSidesAndSkipsSymbolicLinks() async throws {
    let fixture = try TwoFolderFixture()
    try fixture.write("one", to: "Original/nested/a.txt")
    try fixture.write("two", to: "Backup/b.txt")
    try fixture.symlink("Original/link.txt", destination: fixture.url("Original/nested/a.txt"))

    let result = try await FileEnumerator().inventory(for: fixture.pair)

    XCTAssertEqual(Set(result.files.map(\.relativePath)), ["nested/a.txt", "b.txt"])
    XCTAssertEqual(result.skips.first(where: { $0.url.lastPathComponent == "link.txt" })?.reason, .symbolicLink)
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter FileEnumeratorTests`

Expected: compilation fails because `FileEnumerator` does not exist.

- [ ] **Step 3: Implement recursive enumeration**

Use `FileManager.DirectoryEnumerator` with `.skipsHiddenFiles` deliberately omitted so hidden user files are compared. Request `.isRegularFileKey`, `.isPackageKey`, `.isSymbolicLinkKey`, `.isAliasFileKey`, `.isReadableKey`, `.fileSizeKey`, and `.contentModificationDateKey`; use `.skipsPackageDescendants`. Provide an enumeration error handler that appends `.unreadable` for the failed URL and continues. Check cancellation for every enumerated URL. A metadata read failure appends `.metadataFailure` and continues.

```swift
public protocol FileEnumerating: Sendable {
    func inventory(for pair: FolderPair) async throws -> ScanInventory
}

public struct FileEnumerator: FileEnumerating {
    public init() {}

    public func inventory(for pair: FolderPair) async throws -> ScanInventory {
        try await Task.detached(priority: .userInitiated) {
            var files: [ScannedFile] = []
            var skips: [ScanSkip] = []
            for side in FolderSide.allCases {
                let root = pair[side]
                let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .isSymbolicLinkKey, .isAliasFileKey, .isReadableKey, .fileSizeKey, .contentModificationDateKey]
                let errorHandler: (URL, Error) -> Bool = { url, _ in
                    skips.append(.init(url: url, reason: .unreadable))
                    return true
                }
                guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants], errorHandler: errorHandler) else { continue }
                for case let url as URL in iterator {
                    try Task.checkCancellation()
                    do {
                        let values = try url.resourceValues(forKeys: Set(keys))
                        if values.isPackage == true { skips.append(.init(url: url, reason: .package)); continue }
                        if values.isSymbolicLink == true { skips.append(.init(url: url, reason: .symbolicLink)); continue }
                        if values.isAliasFile == true { skips.append(.init(url: url, reason: .alias)); continue }
                        if values.isReadable == false { skips.append(.init(url: url, reason: .unreadable)); continue }
                        guard values.isRegularFile == true,
                              let size = values.fileSize,
                              let date = values.contentModificationDate else { continue }
                        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
                        files.append(.init(url: url, side: side, relativePath: String(url.path.dropFirst(prefix.count)), byteSize: UInt64(size), modificationDate: date))
                    } catch {
                        skips.append(.init(url: url, reason: .metadataFailure))
                    }
                }
            }
            return ScanInventory(files: files, skips: skips)
        }.value
    }
}
```

- [ ] **Step 4: Run enumeration tests**

Run: `swift test --filter FileEnumeratorTests`

Expected: recursive files are returned, skip reasons are recorded, and cancellation throws.

### Task 4: Exact Content Matching

**Files:**
- Create: `Sources/DedupperCore/ContentMatcher.swift`
- Test: `Tests/DedupperCoreTests/ContentMatcherTests.swift`

**Interfaces:**
- Consumes: `[ScannedFile]` and `DuplicateGroup`.
- Produces: `ContentHashing.digest(of:) throws -> String`, `ByteComparing.equal(_:_:) throws -> Bool`, and `ContentMatching.groups(from:) async throws -> [DuplicateGroup]`.

- [ ] **Step 1: Write matcher tests**

Test same bytes/different names, same name/different bytes, within-Original, within-Backup, across-folders, Across + Within, singleton exclusion, zero-byte files, deterministic ordering, and cancellation. Inject a fake hasher returning one digest for different contents to prove byte confirmation splits a simulated hash collision.

```swift
func testByteConfirmationSplitsHashCollision() async throws {
    let fixture = try TwoFolderFixture()
    let a = try fixture.record(contents: "AAAA", path: "Original/a")
    let b = try fixture.record(contents: "BBBB", path: "Backup/b")
    let matcher = ContentMatcher(hasher: ConstantHasher("collision"), comparer: FileByteComparer())
    XCTAssertEqual(try await matcher.groups(from: [a, b]), [])
}
```

- [ ] **Step 2: Verify matcher tests fail**

Run: `swift test --filter ContentMatcherTests`

Expected: compilation fails because matching protocols and implementations are undefined.

- [ ] **Step 3: Implement streamed SHA-256 and byte confirmation**

Use 1 MiB chunks so large files are never loaded fully into memory. First bucket by `byteSize`, discard singleton buckets, hash remaining candidates, then partition each same-size/same-hash bucket by comparing each candidate against a representative. Emit only byte-confirmed partitions containing at least two files. Check cancellation before hashing and comparing each file.

```swift
import CryptoKit
import Foundation

public protocol ContentHashing: Sendable { func digest(of url: URL) throws -> String }
public protocol ByteComparing: Sendable { func equal(_ lhs: URL, _ rhs: URL) throws -> Bool }
public protocol ContentMatching: Sendable { func groups(from files: [ScannedFile]) async throws -> [DuplicateGroup] }

public struct SHA256FileHasher: ContentHashing {
    public init() {}
    public func digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct FileByteComparer: ByteComparing {
    public init() {}
    public func equal(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let left = try FileHandle(forReadingFrom: lhs)
        let right = try FileHandle(forReadingFrom: rhs)
        defer { try? left.close(); try? right.close() }
        while true {
            let a = try left.read(upToCount: 1_048_576) ?? Data()
            let b = try right.read(upToCount: 1_048_576) ?? Data()
            if a != b { return false }
            if a.isEmpty { return true }
        }
    }
}
```

Implement `ContentMatcher` with `init(hasher: ContentHashing = SHA256FileHasher(), comparer: ByteComparing = FileByteComparer())`. Preserve the SHA-256 value in `DuplicateGroup.digest` for later safety validation. For a normal bucket, use the digest as the group ID; only when a simulated or real hash collision produces multiple byte-distinct duplicate partitions, construct groups with `DuplicateGroup(id: "\(digest)-\(partitionIndex)", digest: digest, files: partition)`. Sort final groups by descending `files.first!.byteSize`, then group ID.

- [ ] **Step 4: Run matcher tests and the core suite**

Run: `swift test --filter ContentMatcherTests && swift test`

Expected: matching tests pass, including the forced collision case, and the full core suite remains green.

### Task 5: Selection and Immutable Deletion Planning

**Files:**
- Create: `Sources/DedupperCore/ActionPlanner.swift`
- Test: `Tests/DedupperCoreTests/ActionPlannerTests.swift`

**Interfaces:**
- Consumes: `[DuplicateGroup]` and `Set<URL>`.
- Produces: `ActionPlanning.markedURLs(in:groupIDs:side:) -> Set<URL>` and `makePlan(groups:markedURLs:) throws -> DeletionPlan`.

- [ ] **Step 1: Write planning tests**

Prove that individual files, group selection, Original-side, Backup-side, all-copy, and filtered subsets mark exactly the expected URLs. Assert that unknown URLs throw `ActionPlanningError.fileOutsideResults`, duplicate URLs are deduplicated, items sort by path, totals count every selected physical copy, and `groupsLosingAllCopies` includes a group only when all its files are marked.

- [ ] **Step 2: Verify planning tests fail**

Run: `swift test --filter ActionPlannerTests`

Expected: compilation fails because `ActionPlanner` is undefined.

- [ ] **Step 3: Implement selection helpers and plan snapshots**

```swift
import Foundation

public enum ActionPlanningError: Error, Equatable, Sendable { case fileOutsideResults(URL) }

public protocol ActionPlanning: Sendable {
    func markedURLs(in groups: [DuplicateGroup], groupIDs: Set<String>, side: FolderSide?) -> Set<URL>
    func makePlan(groups: [DuplicateGroup], markedURLs: Set<URL>) throws -> DeletionPlan
}

public struct ActionPlanner: ActionPlanning {
    public init() {}

    public func markedURLs(in groups: [DuplicateGroup], groupIDs: Set<String>, side: FolderSide?) -> Set<URL> {
        Set(groups.filter { groupIDs.contains($0.id) }.flatMap { group in
            group.files.filter { side == nil || $0.side == side }.map(\.url)
        })
    }

    public func makePlan(groups: [DuplicateGroup], markedURLs: Set<URL>) throws -> DeletionPlan {
        let lookup = Dictionary(uniqueKeysWithValues: groups.flatMap { group in
            group.files.map { ($0.url, (group.id, group.digest, $0)) }
        })
        for url in markedURLs where lookup[url] == nil { throw ActionPlanningError.fileOutsideResults(url) }
        let items = markedURLs.compactMap { lookup[$0] }.map {
            PlannedDeletion(groupID: $0.0, expectedDigest: $0.1, file: $0.2)
        }.sorted { $0.file.url.path < $1.file.url.path }
        let losingAll = Set(groups.filter { Set($0.files.map(\.url)).isSubset(of: markedURLs) }.map(\.id))
        return DeletionPlan(items: items, groupsLosingAllCopies: losingAll)
    }
}
```

- [ ] **Step 4: Run planner tests**

Run: `swift test --filter ActionPlannerTests`

Expected: selection scope, storage totals, deterministic ordering, and all-copy warnings pass.

### Task 6: Revalidation and Per-File Trash Execution

**Files:**
- Create: `Sources/DedupperCore/SafetyValidator.swift`
- Create: `Sources/DedupperCore/TrashExecutor.swift`
- Test: `Tests/DedupperCoreTests/SafetyValidatorTests.swift`
- Test: `Tests/DedupperCoreTests/TrashExecutorTests.swift`

**Interfaces:**
- Consumes: `PlannedDeletion`, `DeletionPlan`, `ContentHashing`, and outcome/report types.
- Produces: `SafetyValidating.validate(_:) -> ValidationResult`, `Trashing.trash(_:) throws -> URL?`, and `TrashExecuting.execute(_:) async -> ExecutionReport`.

- [ ] **Step 1: Write validator and executor tests**

Validator cases: unchanged file is valid; missing, changed size, changed modification date, changed digest, and unreadable file are invalid with stable user-facing reasons. Executor cases: valid file calls the Trash spy once; invalid file never calls Trash; one thrown Trash error does not stop later files; and outcomes remain in plan order.

```swift
func testPartialFailureContinuesInPlanOrder() async {
    let trash = TrashSpy(failingURLs: [secondURL])
    let report = await TrashExecutor(validator: AlwaysValid(), trash: trash).execute(plan)
    XCTAssertEqual(trash.receivedURLs, [firstURL, secondURL, thirdURL])
    XCTAssertEqual(report.outcomes.count, 3)
}
```

- [ ] **Step 2: Verify safety tests fail**

Run: `swift test --filter 'SafetyValidatorTests|TrashExecutorTests'`

Expected: compilation fails because validation and Trash interfaces are undefined.

- [ ] **Step 3: Implement pre-delete revalidation**

```swift
import Foundation

public enum ValidationResult: Equatable, Sendable { case valid; case invalid(String) }
public protocol SafetyValidating: Sendable { func validate(_ item: PlannedDeletion) -> ValidationResult }

public struct SafetyValidator: SafetyValidating {
    private let hasher: any ContentHashing
    public init(hasher: any ContentHashing = SHA256FileHasher()) { self.hasher = hasher }

    public func validate(_ item: PlannedDeletion) -> ValidationResult {
        do {
            let values = try item.file.url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { return .invalid("File is missing or is no longer a regular file") }
            guard UInt64(values.fileSize ?? -1) == item.file.byteSize else { return .invalid("File size changed after scanning") }
            guard values.contentModificationDate == item.file.modificationDate else { return .invalid("File modification date changed after scanning") }
            guard try hasher.digest(of: item.file.url) == item.expectedDigest else { return .invalid("File contents changed after scanning") }
            return .valid
        } catch {
            return .invalid("File could not be revalidated: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Implement Trash execution**

`FileManagerTrash.trash(_:)` must call `FileManager.default.trashItem(at:resultingItemURL:)`. `TrashExecutor.execute(_:)` runs off the main actor, checks cancellation between items, validates first, calls Trash only for `.valid`, catches each Trash error independently, and returns ordered `.trashed`, `.skipped`, or `.failed` outcomes.

```swift
public protocol Trashing: Sendable { func trash(_ url: URL) throws -> URL? }
public struct FileManagerTrash: Trashing {
    public init() {}
    public func trash(_ url: URL) throws -> URL? {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }
}

public protocol TrashExecuting: Sendable { func execute(_ plan: DeletionPlan) async -> ExecutionReport }
```

- [ ] **Step 5: Run safety and full core tests**

Run: `swift test --filter 'SafetyValidatorTests|TrashExecutorTests' && swift test`

Expected: all validation states and partial-failure behavior pass; the full core suite remains green.

### Task 7: App Workflow Model and Folder Picker

**Files:**
- Create: `Sources/DedupperApp/AppModel.swift`
- Create: `Sources/DedupperApp/FolderPicker.swift`
- Test: `Tests/DedupperAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: all core validator, enumerator, matcher, planner, and executor protocols.
- Produces: `@MainActor @Observable AppModel`, `AppModel.Phase`, and `FolderPicking.chooseFolder(title:) async -> URL?`.

- [ ] **Step 1: Write workflow model tests with protocol fakes**

Test: folder choices remain inert until both exist; invalid pairs expose the exact validation error; scan transitions `idle -> scanning -> results`; cancellation returns to folder selection without files changing; scan results retain skips; text and kind filters derive visible groups; Select All uses only visible groups; clearing the filter permits all groups; marked file URLs survive sorting; plan creation does not execute Trash; confirmed execution transitions to completion with its report.

- [ ] **Step 2: Verify app-model tests fail**

Run: `swift test --filter AppModelTests`

Expected: compilation fails because `AppModel` and `FolderPicking` are undefined.

- [ ] **Step 3: Implement the folder picker adapter**

```swift
import AppKit
import Foundation

@MainActor protocol FolderPicking {
    func chooseFolder(title: String) async -> URL?
}

@MainActor struct NSOpenPanelFolderPicker: FolderPicking {
    func chooseFolder(title: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        return await panel.begin() == .OK ? panel.url : nil
    }
}
```

- [ ] **Step 4: Implement `AppModel` orchestration**

Define phases `.selectingFolders`, `.scanning`, `.reviewing`, `.verifying(DeletionPlan)`, `.executing`, and `.completed(ExecutionReport)`. Store `originalURL`, `backupURL`, `groups`, `scanSkips`, `markedURLs`, `searchText`, `kindFilter`, `errorMessage`, and the active scan `Task`. Inject protocol dependencies in `init`. All mutable UI state stays on `@MainActor`; `startScan()` awaits the already non-main enumerator/matcher; `cancelScan()` cancels the task; `visibleGroups` applies kind then case-insensitive path/name filtering; and `selectAllVisible()` unions every file URL from `visibleGroups` without touching hidden selections.

- [ ] **Step 5: Run app-model and full tests**

Run: `swift test --filter AppModelTests && swift test`

Expected: every workflow transition and selection-scope test passes.

### Task 8: Native Quick Look and Parallel Review UI

**Files:**
- Create: `Sources/DedupperApp/QuickLookCoordinator.swift`
- Create: `Sources/DedupperApp/ParallelReviewView.swift`
- Create: `Sources/DedupperApp/RootView.swift`
- Create: `Sources/DedupperApp/DedupperApp.swift`

**Interfaces:**
- Consumes: `AppModel`, `DuplicateGroup`, `DuplicateKind`, and file selection state.
- Produces: a runnable macOS window, folder selection screen, cancellable progress screen, accessible parallel results, filtering, selection, batch actions, and Space-bar Quick Look.

- [ ] **Step 1: Add Quick Look coordinator**

Create a `@MainActor` `QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate` that stores `[URL]` and a selected index, returns URLs as `QLPreviewItem`, reloads `QLPreviewPanel.shared()`, sets `currentPreviewItemIndex`, and makes the panel key and ordered front. `close()` must call `orderOut(nil)` and retain no URLs.

- [ ] **Step 2: Build the parallel result presentation**

Use a `List` of duplicate groups. Each group row contains a fixed-width Original column, a center badge/action column, and a fixed-width Backup column. Each file entry includes a checkbox bound to `AppModel.markedURLs`, filename, relative path, formatted size/date, and focus selection for Quick Look. Empty sides display “No matching copy in this folder.”

Map kinds to badge symbols and colors while always rendering the text label:

```swift
extension DuplicateKind {
    var symbolName: String {
        switch self {
        case .withinOriginal, .withinBackup: "square.stack.3d.up"
        case .acrossFolders: "arrow.left.arrow.right"
        case .acrossAndWithin: "square.stack.3d.up.fill"
        }
    }
    var tint: Color {
        switch self {
        case .withinOriginal: .orange
        case .withinBackup: .yellow
        case .acrossFolders: .blue
        case .acrossAndWithin: .purple
        }
    }
}
```

Add toolbar controls for search, kind filter, selected count, Select All Visible, Clear Selection, Mark Original Side, Mark Backup Side, and the red Review Delete action. Group menus expose Delete Original Side, Delete Backup Side, Delete All Copies, and Keep All. These actions only alter `markedURLs`; they do not call Trash.

- [ ] **Step 3: Wire Space-bar Quick Look and accessibility**

Track `focusedFileURL`. Add `.focusable()` and `.onKeyPress(.space)` to the review container; if a file is focused, show all files in its group with that URL selected. Add accessibility labels that include filename, folder side, group type, and whether the file is marked for Trash. Ensure every colored badge includes its visible text.

- [ ] **Step 4: Add app entry point and workflow routing**

`DedupperApp` owns `@State private var model = AppModel.live()` and `@State private var quickLook = QuickLookCoordinator()`. `RootView` switches on phase: folder pickers and Scan button, progress with Cancel, `ParallelReviewView`, verification sheet, execution progress, or completion summary. Use a minimum window size of 1,000 x 650 points and default size of 1,240 x 780.

- [ ] **Step 5: Build and launch the app for the first UI checkpoint**

Run: `swift build && swift run Dedupper`

Expected: build succeeds; a native macOS window opens; two folders can be selected; results show parallel labeled groups; selecting a file and pressing Space opens Quick Look; no action moves a file yet.

### Task 9: Verification UI, Execution, and Completion Reporting

**Files:**
- Create: `Sources/DedupperApp/VerificationView.swift`
- Modify: `Sources/DedupperApp/AppModel.swift`
- Modify: `Sources/DedupperApp/RootView.swift`
- Modify: `Sources/DedupperApp/ParallelReviewView.swift`
- Test: `Tests/DedupperAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `DeletionPlan`, `groupsLosingAllCopies`, `TrashExecuting`, and `ExecutionReport`.
- Produces: non-destructive review, red final verification, execution progress, updated result groups, and per-file outcome summaries.

- [ ] **Step 1: Add failing execution-state tests**

Assert that an empty selection cannot open verification; verification displays group/file counts, side counts, total bytes, sorted paths, and all-copy warnings; cancel returns to reviewing with marks intact; execution only starts from the Verify action; successful or missing files are removed from displayed results; failed/skipped files remain; and groups with fewer than two remaining files disappear because they are no longer duplicates.

- [ ] **Step 2: Run tests and verify failure**

Run: `swift test --filter AppModelTests`

Expected: new verification and post-execution assertions fail.

- [ ] **Step 3: Implement verification view**

Render an immutable `DeletionPlan` with duplicate-group count, file count, total bytes, Original and Backup counts, sorted relative paths, and a prominent warning section when `groupsLosingAllCopies` is nonempty. Provide a neutral Cancel button and destructive red **Verify and Move to Trash** button. Disable dismissal while execution is active.

- [ ] **Step 4: Implement execution and result refresh**

`AppModel.confirmDeletion()` sets `.executing`, awaits `TrashExecuting.execute(plan)`, removes only `.trashed` and missing-file `.skipped` URLs from groups, drops groups with fewer than two remaining files, clears those URLs from `markedURLs`, stores the report, and enters `.completed`. “Back to Results” returns to `.reviewing`; “New Scan” clears groups, marks, filters, URLs, skips, and report, then returns to `.selectingFolders`.

- [ ] **Step 5: Run tests and a safe manual Trash check**

Run: `swift test && swift run Dedupper`

Expected: all tests pass. For manual verification, create disposable files inside a newly created temporary test pair, scan them, mark one, verify the exact displayed path, move it to Trash, confirm the other copy remains, and restore or empty the test file from Trash manually after inspection. Never point this check at user data.

### Task 10: End-to-End Acceptance and Documentation

**Files:**
- Create: `Tests/DedupperCoreTests/AcceptanceTests.swift`
- Create: `README.md`
- Modify: `docs/product-brief.md` only if implementation reveals a genuine contradiction; do not silently expand scope.

**Interfaces:**
- Consumes: the completed core and app workflow.
- Produces: executable acceptance coverage and operator documentation.

- [ ] **Step 1: Add acceptance tests from the product brief**

Use temporary folders and real local file I/O to cover: same contents/different names, same name/different bytes, Within Original, Within Backup, Across Folders, Across + Within, filtered selection, byte-confirmed hash collision through injection, changed file skipped before Trash, partial Trash failure, and cancelled scan. Use a Trash spy in automated tests so tests never touch the real macOS Trash.

- [ ] **Step 2: Run acceptance tests and verify any uncovered behavior fails**

Run: `swift test --filter AcceptanceTests`

Expected: any missing integration wiring fails with a focused assertion; no test modifies files outside its temporary directory.

- [ ] **Step 3: Close acceptance gaps without adding features**

Make only the minimal core or app-model changes required for the named acceptance cases. Preserve all public interfaces from prior tasks unless a failing test proves the interface cannot express an approved requirement; if one changes, update every call site and test in the same step.

- [ ] **Step 4: Document local build and safety behavior**

`README.md` must include:

```markdown
# Dedupper

Native macOS exact-duplicate review for two user-selected folders.

## Requirements

- macOS 15 or later
- Xcode 26.2 or a compatible Swift 6.2 toolchain

## Build and test

```bash
swift test
swift build
swift run Dedupper
```

## Safety

Dedupper scans locally, performs no automatic deletion, verifies every deletion plan, rechecks each file before acting, and moves confirmed files to the macOS Trash rather than deleting them permanently.

## Current scope

The MVP finds byte-identical files within and across exactly two selected, non-overlapping folders. Similar-content matching, recurring scans, and signed distribution packaging are not included.
```

- [ ] **Step 5: Run final automated verification**

Run: `swift test && swift build -c release`

Expected: all tests pass with zero failures and the release build completes successfully.

- [ ] **Step 6: Run final manual acceptance checklist**

Using only disposable folders, verify folder rejection, scan cancellation, all four visible group badges, path/name filtering, filtered Select All, individual file marking, all three side/group batch choices, Space-bar Quick Look, all-copy warning, verification cancellation, one successful Trash move, one simulated failure report, Back to Results, and New Scan. Expected: every accepted product-brief behavior is observable and no file moves before the final red verification action.

## Review Gates

1. After Task 4, review correctness and performance of enumeration, hashing, byte confirmation, cancellation, and grouping before building UI.
2. After Task 6, review destructive-operation safety, especially stale-file rejection and partial failures.
3. After Task 8, review the parallel table, accessible group distinctions, selection semantics, and Quick Look before enabling real Trash execution.
4. After Task 9, perform the disposable-folder Trash check and review every affected path before continuing.
5. Task 10 must pass completely before the MVP is described as implementation-complete.
