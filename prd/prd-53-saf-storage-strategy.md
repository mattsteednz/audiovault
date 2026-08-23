# prd-53 — Chunk O: Storage Access Strategy (SAF exit plan) — DOC ONLY

Status: [ ] decision memo written / [ ] owner decided
No code in this chunk. Play Store policy blocker: MANAGE_EXTERNAL_STORAGE
(AndroidManifest.xml:6) is restricted to core file-management apps; an
audiobook player will very likely be rejected at review. Today the scanner does
raw dart:io traversal (scanner_service.dart) over a user-picked path, and
Drive promotion writes into user folders.

## Options
A. SAF persisted URI permissions — take persistable permission on the picked
   tree (file_picker supports SAF on Android), traverse via DocumentFile/
   DocumentsContract (needs a small platform channel or saf_util-style package),
   stream copy for promote/download writes. Pros: compliant, no big UX change.
   Cons: scanner rewrite for tree URIs; performance overhead on huge libraries;
   iOS unaffected (already sandboxed picker).
B. READ_MEDIA_AUDIO + MediaStore bucket discovery (permission ALREADY declared
   but unused). Discover audio via MediaStore grouped by RELATIVE_PATH bucket;
   metadata/covers still need file access — MediaStore gives content URIs w/
   direct file paths on most devices via openFileDescriptor. Cons: book-folder
   grouping heuristic gets lossy; writing covers/positions.json next to books
   becomes impossible outside app storage → backup format must move to
   app-storage or Drive-only.
C. Dual-channel: keep MANAGE_EXTERNAL_STORAGE for sideload/GitHub-APK builds;
   ship Play variant with SAF. Pros: zero regression for existing users.
   Cons: two storage codepaths forever; build flavours complexity.

## Recommendation
Option A as the Play target, keeping C's flavour split ONLY if existing
sideload users would regress (they keep full FS build). Option B alone cannot
support positions.json-next-to-books and cover writing.

## Exit criteria for implementation PRD (future)
- Scan works over SAF tree on Android 11+ with 3-level nesting + CUE/OPF/M4B.
- Promote-from-staging writes via SAF without MANAGE permission.
- positions.json export/import relocated or wrapped per strategy.
- Play data-safety form drafted.

## Owner decision
DECIDED: <fill in — required before any implementation PRD is written>
