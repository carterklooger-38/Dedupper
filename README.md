# Dedupper

Dedupper is a native macOS utility for reviewing exact duplicate files in two user-selected folders. It finds byte-identical copies within either folder and across both folders, then presents every copy in a parallel Original/Backup view.

## Requirements

- macOS 15 or later
- Xcode 26.2 or a compatible Swift 6.2 toolchain

## Build and test

```bash
swift test
swift build
swift run Dedupper
```

The current Swift Package executable is intended for local MVP development. Signed `.app` packaging, sandbox entitlements, and notarization are outside the current implementation scope.

## Workflow

1. Choose non-overlapping Original and Backup folders.
2. Scan recursively for exact duplicate content.
3. Review groups labeled Within Original, Within Backup, Across Folders, or Across + Within.
4. Select any individual files or use visible/group batch controls.
5. Select a file and press Space to open native Quick Look.
6. Review the immutable deletion plan.
7. Use **Verify and Move to Trash** to execute the plan.

## Safety and privacy

- Scanning, hashing, byte comparison, and action planning happen locally.
- The application has no account, network dependency, or analytics.
- No file moves before the final verification action.
- Every file is revalidated for size, modification date, and content digest immediately before acting.
- Confirmed files move through the macOS Trash API and are never permanently deleted by Dedupper.
- Changed, missing, and inaccessible files are skipped and reported individually.
- A failure affecting one file does not stop or misreport the rest of the batch.
- Storage moved to Trash is not described as reclaimed until the user empties Trash.

## Current scope

The MVP compares exactly two selected folders. Similar-image matching, semantic document matching, comparisons involving more folders, recurring scans, signed distribution packaging, and automatic deletion are not included.

See [the product brief](docs/product-brief.md) and [the implementation plan](docs/superpowers/plans/2026-08-04-dedupper-mvp.md) for detailed decisions.
