# Dedupper MVP Product Brief

**Status:** Draft for product review

**Platform:** macOS

**Primary audience:** Everyday Mac users

**Last updated:** August 4, 2026

## Product summary

Dedupper is a native macOS utility that scans two user-selected folders, identifies files with exactly matching contents both within and across those folders, and helps the user remove unwanted copies safely. Results are displayed in a parallel review table so the user can understand where every copy exists before choosing what to keep.

The MVP prioritizes trust and recoverability. It never deletes files automatically or permanently. Every deletion moves files to the macOS Trash only after the user reviews and verifies the action.

## Problem

Everyday Mac users often keep an original folder and a backup or migrated copy. Over time, both folders accumulate duplicate files that consume storage and are difficult to compare manually. Finder can show filenames, sizes, and dates, but it does not provide a focused workflow for proving that files have identical contents and reviewing both locations together before cleanup.

Users need a simple way to answer three questions:

1. Which files have exactly matching contents within either selected folder or across both folders?
2. Where is each copy located, and can I preview it before acting?
3. Can I remove selected copies in bulk without risking an irreversible deletion?

## Product goal

Enable an everyday Mac user to compare two folders, confidently review all exact duplicate groups, and move selected copies to the Trash through an understandable and verifiable workflow.

## Non-goals

The MVP will not:

- Detect visually similar images, semantically similar documents, or other fuzzy matches.
- Compare more than two folders at once.
- Delete files automatically or permanently.
- Maintain a Dedupper archive.
- Reorganize the user's remaining files.
- Monitor folders continuously or run scheduled scans.
- Add cloud-storage-provider-specific behavior.

Visual and content-similarity detection may be explored after the exact-duplicate workflow has been validated.

## Core user journey

### 1. Select folders

The user selects exactly two folders with standard macOS folder pickers. The first is labeled **Original** and the second **Backup**. The labels communicate the user's intended roles; they do not change how matching works or grant one side automatic priority.

The app prevents the same folder from being selected for both roles. It also prevents one selected folder from containing the other, avoiding ambiguous pairs and overlapping destructive actions.

### 2. Scan and match

The app recursively scans readable regular files in both selected folders. Progress is visible, and the user can cancel without changing any files.

The app identifies exact duplicates by comparing file contents, not filenames, paths, creation dates, or modification dates. Files with different names are grouped when their bytes match. Matching covers the complete scan set: duplicates solely within Original, solely within Backup, and across both folders.

### 3. Review results

Each table row represents one exact-content group and includes every byte-identical copy found in either selected folder. The Original cell lists matching Original paths and the Backup cell lists matching Backup paths. A group appears only when it contains at least two files in total.

Every group has a visible text badge and corresponding styling:

- **Within Original** — all copies occur only in Original.
- **Within Backup** — all copies occur only in Backup.
- **Across Folders** — copies occur on both sides, with one copy on each side.
- **Across + Within** — copies occur on both sides and at least one side contains multiple copies.

The styling uses icons, text, and color so the distinction remains accessible without relying on color alone. An **Across + Within** group highlights all matching copies together in the same row.

| Selection | Original | Backup | Match details | Planned action |
| --- | --- | --- | --- | --- |
| File and group checkboxes | Matching names, relative paths, size, dates | Matching names, relative paths, size, dates | Type badge and exact-match status | Files marked for Trash or none |

The user can sort and filter results. Selecting either file and pressing **Space** opens the native macOS Quick Look preview. Closing Quick Look returns focus to the corresponding result.

Each row begins with no destructive action selected. Leaving a row unchanged keeps every listed copy.

### 4. Choose individual or batch actions

Each listed file has its own selection control, allowing the user to mark any individual copy for deletion. Group-level shortcuts provide:

- **Delete Original Side:** mark every Original-side copy in the group for Trash.
- **Delete Backup Side:** mark every Backup-side copy in the group for Trash.
- **Delete All Copies:** mark every copy in the group for Trash.
- **Keep All:** leave every copy in the group unchanged.

The table supports selecting individual files, any number of groups, and **Select All** for the currently displayed results. Batch controls can mark the selected files for Trash or apply Original-side, Backup-side, or both-sides actions to selected groups. Applying a batch choice creates a planned action that remains reviewable before execution; it does not immediately move files.

Changing filters does not silently expand selection. Select All applies only to rows currently displayed by the active filter, and the interface shows the exact selected count.

### 5. Verify deletion

All destructive controls are red and use clear labels. Activating a deletion plan opens a verification view that shows:

- The chosen action.
- The number of duplicate groups affected.
- The number of files that will move to the Trash.
- The total storage represented by those files.
- Whether Original, Backup, or both sides are affected.
- A scrollable list of the affected paths.

If a plan will delete every known copy in a group, whether from one folder or both, the verification view displays a prominent warning that neither selected folder will retain that content. The user must press a final red **Verify and Move to Trash** button. Cancelling or closing the view changes nothing.

### 6. Complete and report

Immediately before moving each file, the app verifies that it still exists and has not changed since scanning. Changed, missing, or newly inaccessible files are skipped.

The app uses the macOS Trash operation, never permanent deletion. The results view updates each affected row and provides a completion summary containing:

- Successfully trashed files.
- Skipped or failed files and the reason for each failure.
- Total storage moved to the Trash.

Files in the Trash may still consume disk space until the user empties it, so the interface describes this value as storage moved to the Trash rather than storage permanently reclaimed.

## Functional requirements

### Folder access

- Use macOS system folder pickers and user-granted access.
- Scan only the two folders explicitly selected by the user.
- Traverse nested directories recursively.
- Prevent identical or overlapping Original and Backup selections.
- Retain access only as needed for the active workflow in the MVP.

### Exact duplicate detection

- Enumerate readable regular files on both sides.
- Group files by byte size to eliminate impossible matches cheaply.
- Compute a cryptographic content hash only for same-folder or cross-folder size groups that could match.
- Confirm matching size-and-hash candidates with a byte-for-byte comparison before presenting them as exact duplicates.
- Support multiple files on either side with the same content by displaying a duplicate group containing all matching paths, rather than inventing arbitrary one-to-one pairs.
- Keep scanning work off the main interface thread and expose progress and cancellation.

### Review and selection

- Present Original and Backup paths in parallel, leaving a side empty for a same-folder-only group.
- Label and style Within Original, Within Backup, Across Folders, and Across + Within groups distinctly without relying on color alone.
- Display names, relative paths, byte sizes, and modification dates.
- Support individual-file selection, group selection, multi-selection, and Select All for visible results.
- Support sorting and basic text filtering.
- Preserve selections while sorting.
- Provide native Quick Look for either side through the Space bar.
- Default every result to no action.

### Deletion planning and execution

- Support marking any individual file for Trash.
- Support group and batch shortcuts for Original copies, Backup copies, all copies, or none.
- Support the same choices for any selected subset and for all visible results.
- Require a verification view before every execution.
- Revalidate file identity and availability before moving it.
- Move files exclusively through the macOS Trash API.
- Continue safely when part of a batch fails and report results per file.
- Never follow symbolic links or aliases as though they were target files.

## Technical design

The recommended implementation is a native macOS application built with Swift and SwiftUI. Native frameworks provide appropriate folder-permission handling, Quick Look integration, responsive macOS table behavior, and access to the system Trash operation.

### Components

1. **Folder Selector** — collects and validates the Original and Backup folder choices.
2. **Scan Coordinator** — recursively enumerates files, reports progress, handles cancellation, and keeps work off the main thread.
3. **Duplicate Matcher** — groups all candidates by size, calculates content hashes, confirms candidate contents byte for byte, and produces same-folder, cross-folder, or mixed duplicate groups.
4. **Results Model** — stores paths, metadata captured during scanning, match groups, selections, and planned actions.
5. **Parallel Review Table** — renders both sides, supports filtering and selection, and coordinates Quick Look.
6. **Action Planner** — converts individual and batch choices into an immutable deletion plan for verification.
7. **Safety Validator** — checks existence and confirms that size, modification state, and content identity still match the scan before execution.
8. **Trash Executor** — requests macOS Trash moves and records a success or failure for each file independently.

### Data flow

```text
Select Original and Backup folders
                |
                v
Recursively enumerate regular files
                |
                v
Group all candidates by size
                |
                v
Hash candidates, then confirm matches byte for byte
                |
                v
Display parallel duplicate groups
                |
                v
Select files or groups and assign individual or batch actions
                |
                v
Review immutable verification plan
                |
                v
Revalidate each file and move confirmed files to Trash
                |
                v
Refresh results and show per-file completion report
```

## Error handling and safety rules

- Scanning never modifies files.
- Cancelling a scan or verification operation leaves files unchanged.
- Packages, symbolic links, aliases, filesystem loops, and unreadable files are skipped and summarized.
- A file that disappears or changes after scanning is not deleted.
- Errors affecting one file do not cause the remaining verified batch operations to be misreported.
- The interface never describes a Trash move as permanent deletion or immediate disk-space reclamation.
- The app records operational results locally for the active session and does not upload file contents, hashes, paths, or metadata.

## Privacy principles

- All scanning, hashing, comparison, and action planning occur locally on the Mac.
- No account or network connection is required for the MVP.
- No file contents, paths, hashes, or scan results leave the device.
- The user controls which two folders the app may inspect.

## MVP success criteria

The MVP is successful when an everyday Mac user can:

1. Select two non-overlapping folders and scan their nested contents.
2. Reliably find files with identical bytes within either folder and across both folders, even when their names differ.
3. Distinguish same-folder, cross-folder, and mixed duplicate groups and understand where every copy exists.
4. Preview any copy by selecting it and pressing Space.
5. Select one file, several files or groups, all visible results, or every result after clearing the filter.
6. Choose to keep every copy or move any combination of individual, Original-side, Backup-side, or all copies to the Trash.
7. Review the exact scope of every destructive batch before confirming it.
8. Receive accurate per-file success, skip, and failure feedback.
9. Complete the workflow without Terminal or knowledge of hashing.

## Acceptance scenarios

1. **Same contents, different names:** Identically sized files with matching bytes but different filenames appear in the same duplicate result.
2. **Same name, different contents:** Files with the same name but different bytes are not reported as duplicates.
3. **Within one folder:** Two identical files found only in Original appear together with a Within Original badge and an empty Backup cell.
4. **Across folders:** One copy on each side appears with an Across Folders badge.
5. **Mixed duplicate group:** Multiple Original copies and at least one Backup copy appear together with an Across + Within badge, with all paths visible in one group.
6. **Selected subset:** A batch action changes only the explicitly selected visible files or groups.
7. **Select All under a filter:** Select All selects only displayed results and communicates that scope.
8. **Quick Look:** Pressing Space on either side previews the selected file and does not alter selection or planned actions.
9. **Delete one file:** Verification and execution move only the individually marked file to the Trash.
10. **Delete one side:** Verification and execution move only the chosen side to the Trash.
11. **Delete every copy:** Verification prominently warns that no scanned copy will remain before moving any file.
12. **Changed file:** A file modified after scanning is skipped during revalidation and remains in place.
13. **Partial failure:** Successful Trash moves remain accurately reported when another file in the same batch fails.
14. **Cancellation:** Cancelling scanning or verification causes no filesystem changes.

## Product metrics for validation

- Percentage of completed scans that reach the review table.
- Percentage of deletion plans confirmed versus cancelled.
- Number and rate of files skipped during scanning or pre-deletion validation.
- Batch-operation failure rate.
- Time from folder selection to actionable results.
- User-reported confidence that the correct copy was retained.

Metrics must be collected only with explicit user consent and must not include file contents, paths, filenames, or hashes.

## Future iterations

Potential post-MVP work includes visually similar image detection, content-similar document detection, comparison of more than two folders, richer filtering, and optional recurring scans. Each capability requires its own safety and trust review before inclusion.
