# ExecPlan: T05 Fixes from the M1 and M2 review

Milestone M1 follow-up. Fixes items 1, 2, 3, 4, and 6 of
`../reviews/2026-11-24-m1-m2-review.md`. Item 5 waits for M3. Plan:
`../phase1-plan.md`. Simplicity rules: see `../execplan-template.md`.

Read the review first. It holds the evidence for each item. This card only
fixes the outcome.

## Set by the planner

### Goal

Recovery Bundles behave exactly as they did before T01. Revision Pack export
still carries full history. Cloud staging leaves no Skill content behind after
a Skill is removed or a process exits. Synced Origin labels accept ordinary
names. Cloud CI matches the CLI template.

### Context

- **Item 1, maintainer decision (2026-11-24): split the paths.**
  - Recovery Bundles go back to the retained roots and their trees only, as
    before T01.
  - Only Revision Pack export walks ancestry.
- **Item 2:** staging lives at `WorkspaceLayout.revisionPackStagingPath`. Temporary
  import directories are created as `.pack-*` under `revision-stores/`.
  Removal is in `lib/src/composition/destructive_recovery_entries.dart`, and
  startup maintenance in `lib/src/composition/workspace_revision_maintenance.dart`.
- **Item 3:** see `_requirePortableDisplayLabel` in
  `lib/src/domain/source_descriptor.dart`. The type has no path or URL field,
  so it is path-free by construction.
- **Item 4:** `revision_pack_export_command.dart` stages the pack in
  `Directory.systemTemp`.
- **Item 6:** `.github/workflows/skills-cloud-ci.yml` against
  `.github/workflows/skilldeck-cli-ci.yml`, and `.github/tests/workflow_policy_test.rb`.

Paths are under `packages/skills_workspace/` unless they start with `.github/`.

### Contract

- **Recovery Bundles:** native `skills_workspace_revision_recovery_pack_create`
  packs each retained root with its tree and no ancestors, as it did before
  `4d2d3e2`.
- **Export:** the export gets the ancestry walk through its own native entry
  point, or a mode argument. Choose the smaller change. Keep the exported
  symbol lists and the generated bindings in step.
- **Export of a Store with an ancestry hole:** reports the existing
  `SkillsErrorCode.revisionStoreCorrupt` rather than an I/O failure. No new
  error code.
- **Synced Origin labels:** a label is valid when it is non-empty after
  trimming, has no control characters, and is at most 256 characters long.
  Nothing else is rejected. The codec's exact-field check stays.
- No new public API.

### Acceptance

- **Item 1:**
  - A test shows that a Recovery Bundle built from a Store with history holds
    the retained roots and their trees, and no ancestor commit outside the
    retained roots.
  - The existing T01 fresh-repository test still passes, with full history.
  - A Store missing an ancestor of the Effective head makes export report
    `revisionStoreCorrupt` and leaves nothing at the destination.
- **Item 2:**
  - Removing a Skill deletes its pack staging directory as well as its Store.
    Cover this in the existing destructive recovery tests, including recovery
    after an interrupted removal.
  - Startup maintenance deletes leftover `.pack-*` directories under
    `revision-stores/`.
  - Startup maintenance leaves `<id>.git` Stores and `<compact-id>.packs`
    staging untouched.
- **Item 3:** labels such as `notes:v2`, `Work / Personal`, and `..` are
  accepted. Empty labels, labels with control characters, and labels over 256
  characters are rejected.
- **Item 4:** export stages its temporary pack under the Workspace. The sweep
  from item 2 removes leftovers from an interrupted export too.
- **Item 6:**
  - the Cloud workflow uses the CLI template's `paths` filters (including
    `.github/**`) and its runner matrix;
  - the workflow policy test expects both.
- **Gates:** all T01 gates. For native changes, also run `dart run
  tool/regenerate.dart` and check the tree is clean. For item 6, run the
  workflow policy test.

### Scope fence

- **In scope:** `packages/skills_workspace/`, plus the Cloud workflow and its
  policy test.
- **Out of scope:**
  - review item 5, which belongs to M3;
  - deleting successfully staged packs other than on Skill removal (M5);
  - any change to Recovery Bundle restore;
  - App changes;
  - schema changes.
- **Expected size:** about 10–14 files, roughly 300–600 hand-written lines
  including tests.

### Stop and ask if

- Restoring the old Recovery Bundle behaviour breaks an existing test that
  depended on the T01 change.
- Removal of staging cannot be made part of the existing destructive recovery
  entries without a new journal entry kind.
- The startup sweep would need to tell an in-flight import from a leftover
  one. It should not, because startup runs before any operation. Ask if that
  assumption does not hold.

## Maintained by Codex

### Progress

- [x] Restored retained-root Recovery Bundles and verified full-history export, including the missing-ancestor failure.
- [x] Added Workspace staging cleanup on startup and journaled removal of a Skill's staged packs.
- [x] Updated Synced Origin validation and aligned Cloud CI with the CLI workflow.
- [x] Moved temporary pack cleanup into an explicit startup phase after journal recovery and made cleanup best effort.

### Decision Log

- Kept the existing native Recovery Bundle ABI and added a separate export entry point. Both use the same pack and index writer.
- Kept pack removal in the existing journal. Appended staging entries after existing removal entries to preserve their identifiers.
- Both import and export use the same temporary directory prefix. Startup sweeps those directories under the Workspace lock after journal recovery and before admitting operations. Unremovable directories are left for a later startup.
- The 256-character limit counts Unicode code points. Label content is preserved.

### Surprises

### Follow-ups

- Review item 5 is scheduled for M3.

### Outcome

On macOS arm64 with Flutter 3.50.0 and Dart 3.14.0, Workspace formatting, strict analysis, native integration, native ABI checks, and code generation passed. The coverage run passed 1,603 tests, with the network suite skipped by default, and reached 88.89% line coverage against the 85% gate.

The Cloud package passed lockfile enforcement, formatting, strict analysis, and all 10 tests. The local workflow policy suite passed all four tests. Hosted runner execution is pending.

The review item 7 follow-up passed all 28 tests in the startup coordinator and revision maintenance suites on macOS arm64 with Dart 3.14.0.
