# ExecPlan: T01 Revision Pack export and the public revision identifier

Milestone M1. Plan: `../phase1-plan.md`. Simplicity rules: see
`../execplan-template.md`. They apply in full.

## Set by the planner

### Goal

A caller can write, to a file path it chooses, a Revision Pack holding the
complete closure of one managed Skill's Effective and Upstream heads. The
caller gets back opaque identifiers for those two heads.

### Context

- Decisions: R11 seam 1, and R16 for the identifier. The identifier's string
  form is the commit ID. Callers treat it as opaque and never parse it, derive
  paths from it, or infer ancestry from it.
- Vocabulary: **Revision Pack** and its relationships in the root
  `CONTEXT.md`. A Revision Pack is not a Revision Recovery Bundle.
- Read first:
  - `createRecoveryPack` in `lib/src/application/runtime/revision_engine_port.dart`
    and its use in `lib/src/composition/revision_recovery_bundle_publisher.dart`.
    It already writes the closure of retained roots, but into a staging
    directory as `objects.pack` plus `objects.idx`.
  - `exportSkillDriftArtifact`, for how an existing read operation writes to a
    caller-supplied location.
  - `lib/src/infrastructure/database/drift_revision_pointer_reader.dart`, for
    where the current revision pointers come from.

All paths are under `packages/skills_workspace/`.

### Contract

Names are provisional. Follow package naming, but keep the shape.

- `RevisionId`: a public, immutable value type.
  - Constructed from its string form, which is validated as a commit ID.
  - `value` or `toString()` returns that string. Equality is by value.
  - It does not expose `RevisionObjectId`, which stays internal.
- `SkillsRepository.exportRevisionPack(ExportRevisionPackRequest)` returns a
  `SkillsOperation<RevisionPackExport>`.
  - The request holds a `ManagedSkillId` and a destination file path.
  - `RevisionPackExport` holds `effective: RevisionId` and
    `upstream: RevisionId?`. Upstream is absent when the Skill has no Upstream
    Revision.
  - Expected failures are typed outcomes with stable codes: unknown Skill,
    destination unusable (exists, or its directory is missing or not
    writable), and cancelled.

### Acceptance

- The written file is a single standard Git pack. Indexing it in a fresh
  repository yields every object reachable from both returned heads.
- A Skill with an Upstream Revision exports both heads. A Skill without one
  exports the Effective head only.
- Nothing is left at the destination after a failure or a cancellation.
- The export takes no Workspace mutation, writes no SQLite row or Operation
  Record, and leaves the Revision Store unchanged.
- `RevisionId` rejects strings that are not commit IDs, and round-trips its
  string form.
- Gates, from `packages/skills_workspace/`:
  - `dart format --output=none --set-exit-if-changed .`
  - `dart analyze --fatal-infos`
  - `dart test -j 1`
  - `dart test -j 1 integration_test`
  - the four-step coverage pipeline in `CLAUDE.md`, at 85%
  - if native headers change: `dart run tool/regenerate.dart`, then
    `git status --porcelain --untracked-files=all` is clean apart from your
    intended changes

### Scope fence

- In scope: `packages/skills_workspace/` only. That covers `lib/`, `test/`,
  `integration_test/`, and, only if needed, `native/`.
- Out of scope:
  - pack import (T02);
  - any other public use of `RevisionId`, such as adding it to snapshots or
    history models;
  - computing the pack's SHA-256, which is `skills_cloud`'s job;
  - schema changes;
  - App changes.
- Expected size: about 8–12 files, roughly 400–700 lines including tests.

### Stop and ask if

- Writing a single pack file needs a new native entry point rather than
  reusing the recovery pack one.
- The export would need to hold the Workspace lock for longer than reading the
  revision pointers.
- The closure cannot be computed without reading Store state that SQLite does
  not authorize.

## Maintained by Codex

### Progress

- [ ] …

### Decision Log

### Surprises

### Follow-ups

### Outcome
