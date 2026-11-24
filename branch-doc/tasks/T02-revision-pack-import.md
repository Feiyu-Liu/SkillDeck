# ExecPlan: T02 Revision Pack import into staging

Milestone M1. Depends on T01, for `RevisionId`. Plan: `../phase1-plan.md`.
Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

A caller can hand the Workspace a Revision Pack file and the revisions it is
supposed to contain. The Workspace verifies the pack and indexes it into
non-authoritative staging next to the live Revision Store. It reports exactly
one of imported, malformed, or incomplete.

### Context

- Decision: R11 seam 2. Later, seam 3 (the Sync apply contract, M5) reads the
  staged objects inside one Workspace transaction. This task only stages
  them.
- Vocabulary: the **Revision Pack** relationships in the root `CONTEXT.md`.
  Import verifies every object and the completeness of the named revisions.
  Objects the Store already holds are a no-op. Import never writes a live
  Revision Store.
- Read first, all under `packages/skills_workspace/`:
  - `restoreRecoveryPack` in `lib/src/application/runtime/revision_engine_port.dart`
    and its native implementation in `native/src/revision_engine.c`. It verifies
    a pack and its closure, but only into a new bare Store.
  - `lib/src/composition/workspace_revision_maintenance.dart`, for how restore
    is driven today.
  - The existing native tests in `native/test/`, `test/native/`, and
    `integration_test/native_revision_worker_integration_test.dart`.

R11 names the new native work: importing next to a live Store instead of into
a new one.

### Contract

Names are provisional.

- `SkillsRepository.importRevisionPack(ImportRevisionPackRequest)` returns a
  `SkillsOperation<RevisionPackImport>`.
  - The request holds a `ManagedSkillId`, a pack file path, and the
    `RevisionId`s whose closure the pack must complete.
  - `RevisionPackImport` is exactly one of `imported`, `malformed`, or
    `incomplete`.
  - Other expected failures are typed outcomes with stable codes: unknown
    Skill, unreadable pack file, and cancelled.
- The closure check counts objects that are already in the live Store. A pack
  that only adds the missing objects is complete.

### Acceptance

- **imported:** a valid pack is imported, and every named revision's closure
  is readable afterwards from the Skill's Store plus staging.
- **Re-import:** importing the same pack twice reports imported both times
  and changes nothing the second time.
- **malformed:** truncated, corrupted, and wrong-format files each report
  malformed.
- **incomplete:** a pack missing part of a named closure reports incomplete.
  So does a named revision that is absent.
- **Live Store untouched:** before and after any import, the live Store's
  refs, SQLite, and Operation Records are byte-for-byte unchanged.
- **No leftovers:** a failure or a cancellation leaves no partial staging
  behind.
- **Gates:** the same as T01. Native changes also need `dart run
  tool/regenerate.dart` with a clean tree afterwards, and the native test
  suite.

### Scope fence

- In scope: `packages/skills_workspace/`, `native/` included.
- Out of scope:
  - applying staged content to the Effective Revision (seam 3, M5);
  - garbage collection of staged objects beyond cleanup after a failure;
  - downloads;
  - App changes.
- Expected size: about 10–15 files, roughly 700–1,200 lines including C and
  tests.

### Stop and ask if

- Staging needs a lifetime that outlives one operation, or cleanup that needs
  a schema change.
- Importing next to the live Store needs a new concurrency rule with the
  revision worker or with retention-ref maintenance.
- The pinned libgit2 cannot verify the closure without writing to the live
  object database.

## Maintained by Codex

### Progress

- [x] Added the Workspace import operation, native indexing, and named-revision validation.
- [x] Verified partial packs, live-only no-ops, repeated imports, malformed input, incomplete closures, and cancellation.

### Decision Log

- The existing per-Skill read permit protects access to the live object store during validation. The staging object database uses the live object database as a read-only alternate.
- Validated pack and index files are published by a single directory rename, using the indexed pack name to deduplicate repeated imports.
- Successful imports retain staged packs as file output for the later Sync apply milestone. Staging uses the Workspace layout and requires no database rows.

### Surprises

- libgit2 alone does not distinguish every missing dependency from malformed input. A separate walk checks the named commit, tree, and blob closure over staged and live objects. A thin pack with an unresolved delta base cannot be indexed and reports malformed. Phase 1 sends self-contained packs.

### Follow-ups

- M5 owns applying staged objects and any cleanup associated with that apply.
- Review item 2 (staged packs survive Skill removal; crashed imports leave `.pack-*` directories): see `../reviews/2026-11-24-m1-m2-review.md`.

### Outcome

On macOS arm64 with Dart 3.14.0, all six public API cases passed. The tests compare live Store, SQLite, and WAL bytes before and after import. Native ABI and runtime lifecycle checks passed. Regeneration reproduced the generated bindings byte for byte. The full Workspace suite passed at 88.89% line coverage.
