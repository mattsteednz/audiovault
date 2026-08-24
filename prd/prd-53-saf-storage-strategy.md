# prd-53 — Storage Access Strategy: Decision Memo for Owner

## Context
`MANAGE_EXTERNAL_STORAGE` (All files access) is a Play-restricted permission:
an audiobook player will almost certainly be rejected at review. Today that is
fine because distribution is GitHub-Release sideloads only.

## Options
1. **Status quo** (recommended while sideload-only): keep MANAGE_EXTERNAL_STORAGE.
   Zero work; best UX (user picks any folder once).
2. **SAF / DocumentTree**: persist one tree URI via ACTION_OPEN_DOCUMENT_TREE;
   scanner walks DocumentFile tree. Cost: rewrite ScannerService+cover IO over
   SAF (slow: stat per file), no real paths → Drive promote-to-local and
   positions.json export paths need abstraction. Est. 1–2 weeks + device QA.
3. **App-directed storage**: books live under app storage only; user "imports"
   via SAF copy-on-add. Simplest runtime model but doubles storage on import
   and changes user workflow.
4. **MediaStore (READ_MEDIA_AUDIO)**: read audio via MediaStore without All-files.
   Misses OPF/cover sidecars unless also granted media images; folder-layout
   semantics (author/series nesting) are lost — incompatible with the app's
   folder-as-library core design.

## Recommendation
Stay on option 1 now. Re-evaluate ONLY if Play distribution becomes a goal;
at that point option 2 (SAF) is the credible path and should be scoped as a
full PRD with device QA budget. Record decision below when made.

## Owner decision
[ ] Keep status quo        [ ] Pursue SAF (option 2)        Date: ________
