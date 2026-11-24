# ExecPlan: T03 Synced Origin Source descriptor

Milestone M1. Independent of T01 and T02. Plan: `../phase1-plan.md`.
Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

The Workspace can store and return a Synced Origin Source as a Skill's
provenance. That is the credential-free, path-free descriptor a Device records
for a Skill it received through Personal Sync when the Skill's Source is a
Local or Adopted Snapshot Source on another Device. Update checks report it as
not checkable.

### Context

- Decisions: R7, and R11 seam 5 (the Phase 1 part only).
- Vocabulary: **Synced Origin Source**, Origin Device, and Portable Source, in
  the root `CONTEXT.md` and in `packages/skills_cloud/CONTEXT.md`.
- Read first, all under `packages/skills_workspace/`:
  - `lib/src/domain/source_descriptor.dart`, the sealed descriptor family;
  - `lib/src/infrastructure/database/source_descriptor_codec.dart`, which is
    current-only, and whose header says historical payload codecs belong to
    migration code;
  - the descriptor table in
    `lib/src/infrastructure/database/workspace_database.dart`. Its `kind` CHECK
    constraint lists the four current kinds, so a new kind needs a schema
    migration (v3 to v4);
  - the `updateUnsupported` handling of `AdoptedSnapshotSourceDescriptor` in
    `lib/src/application/source/source_acquisition_coordinator.dart`.

### Contract

Names are provisional.

- `SyncedOriginSourceDescriptor`, a new `SourceDescriptor` variant, with:
  - `originSourceType`: Local or Adopted Snapshot;
  - `originDeviceLabel`: a display string the caller supplies. The Workspace
    never interprets it, and it is not a cloud identifier;
  - `displayLabel`: a display string.
- No path, locator, URL, credential, or cloud identifier, in the type or in its
  encoding.
- Persisted as a new descriptor kind. Existing kinds and their stored rows are
  unchanged.
- Update checks for a Skill with this Source report the existing
  update-unsupported outcome, the same as Adopted Snapshot Sources.

### Acceptance

- The descriptor round-trips through the codec and through the database.
- The v3 to v4 migration keeps every existing descriptor row readable and
  unchanged. Use the existing Drift migration test pattern with
  `drift_schemas/`.
- An encoded payload that carries an unexpected field, or anything that looks
  like a path or URL, is rejected on decode.
- `checkUpdates` on such a Skill reports update-unsupported and never acquires
  a Source.
- Exhaustive switches over `SourceDescriptor` handle the new variant
  explicitly, with no default branch added to silence them.
- Gates: the same as T01. In addition, run `dart run tool/regenerate.dart`,
  commit the generated Drift output and the new schema dump, and confirm the
  tree is clean afterwards.

### Scope fence

- In scope: `packages/skills_workspace/`.
- Out of scope:
  - creating this descriptor from anywhere. The Sync apply contract does that
    in M5, so tests construct it directly;
  - the Cloud Release Source (Phase 2);
  - App display of the new provenance.
- Expected size: about 6–10 files plus generated output, roughly 300–500
  hand-written lines.

### Stop and ask if

- Any existing descriptor row would need rewriting.
- The schema change grows beyond the `kind` constraint and the payload for the
  new kind.
- Another public model would need the Origin Device as more than a display
  label.

## Maintained by Codex

### Progress

- [x] Added the descriptor, strict payload decoding, and the v3-to-v4 migration.
- [x] Verified source round trips, snapshot projection, historical rows, and unsupported update checks.

### Decision Log

- The table migration changes the allowed descriptor kinds and copies existing row values, including the original JSON bytes.
- The App adapter handles the new variant as a distinct source kind without an address. Existing UI and grouping code handle that case without adding a provenance presentation.

### Surprises

- The App already exhaustively matches the public source descriptor. A compatibility change was required to keep it compiling.

### Follow-ups

- M5 creates the descriptor when applying state received through Personal Sync.
- Review item 3 (label validation rejects legitimate names; a card defect): see `../reviews/2026-11-24-m1-m2-review.md`.

### Outcome

On macOS arm64 with Dart 3.14.0, all 35 focused source and migration tests passed. Regeneration reproduced the Drift outputs and v4 schema. The full Workspace suite passed at 88.89% line coverage. Flutter 3.50.0 passed strict App analysis and all 49 focused App tests.
