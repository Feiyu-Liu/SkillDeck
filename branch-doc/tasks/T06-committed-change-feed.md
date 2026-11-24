# ExecPlan: T06 Committed-change feed

Milestone M5. Independent of T07. Plan: `../phase1-plan.md`. Contract:
`../m5-sync-apply-contract.md`, section "Seam 4". Simplicity rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

`skills_cloud` can ask the Workspace which Skills changed since a
RepositoryRevision it last saw. It gets a correct answer even when a Skill was
removed, and an explicit signal when the Workspace's revision went backwards.

### Context

- Decision: R11 seam 4. The maintainer chose one latest entry per Skill, not a
  full log.
- What exists today:
  - Business change sets live only in `OperationJournals.planJson`. They are
    deleted when the operation completes.
  - `OperationRecords` has no revision column.
  - A completed Removal leaves no Operation Record.

  None of these can serve as the feed.
- Read first, all under `packages/skills_workspace/lib/src/`:
  - `DriftOperationControlPlane.commitBusinessState` in
    `infrastructure/database/drift_operation_control_plane.dart`. It is the one
    transaction that applies mutations and sets `repositoryRevision`.
  - `application/operations/workspace_business_changes.dart`, the mutation
    kinds that decide content versus metadata.
  - `recoverPrimaryForStartup`, the startup control-plane recovery. It can
    restore a database whose revision is below one a caller already saw.
  - The T03 migration pattern in `workspace_database.dart` and its migration
    test.

### Contract

Names are provisional.

- `SkillsRepository.inspectCommittedChanges(InspectCommittedChangesRequest)`
  returns a `SkillsOperation<CommittedChanges>`. The request holds `since`, a
  `RepositoryRevision`.
- `CommittedChanges` is one of:
  - **`changes(current, entries, vocabularyChanged)`:**
    - each entry holds a `ManagedSkillId`, the `RepositoryRevision` of its
      latest change, and a non-empty set of kinds from `content`, `metadata`,
      and `removed`;
    - `vocabularyChanged` is true when the tag vocabulary changed after
      `since`.
  - **`resetRequired(current)`:** returned when `since` is greater than
    `current`.
- **Kinds:**
  - `content`: a change to the Skill's revision selection, or its creation;
  - `metadata`: a change to its Favorite, Note, or Tag Assignments;
  - `removed`: deletion of the managed Skill.

  A tag deletion that cascades away assignments marks each affected Skill
  `metadata`.
- **Schema v5:** one new table, keyed by Managed Skill ID, plus a single row for
  the vocabulary. It is written inside `commitBusinessState`, in the same
  transaction as the revision bump. Migration from v4 starts empty.

### Acceptance

- **Kinds:** install, update, publish, restore, favorite, note, tag assignment,
  tag create, rename, and delete, and removal each produce the expected entry
  kinds at the committed revision.
- **No-ops:** a no-op metadata call, which does not bump the revision, adds
  nothing.
- **Since filter:** entries at or before `since` are not returned. An entry
  whose latest change is after `since` is returned once, with its latest
  revision.
- **Removal:** a removed Skill is reported `removed` after the Removal
  commits.
- **Rollback:** a rolled-back operation leaves the feed unchanged.
- **Regression:** `since` greater than the current revision returns
  `resetRequired`. Cover this with a test that simulates a restored control
  plane.
- **Migration:** v4 to v5 keeps all existing data. The schema dump and generated
  helpers are updated.
- **Gates:** the T01 gates, plus `dart run tool/regenerate.dart` with a clean
  tree afterwards.

### Scope fence

- **In scope:** `packages/skills_workspace/`.
- **Out of scope:**
  - any apply operation (T07–T09);
  - feed pruning;
  - App changes;
  - exposing operation IDs or mutation payloads.
- **Expected size:** about 8–12 files plus generated output, roughly 400–700
  hand-written lines.

### Stop and ask if

- Some committed change does not pass through `commitBusinessState`, so it
  would be missed.
- Classifying a mutation as content or metadata is ambiguous for an existing
  mutation kind.
- The feed would need to record anything beyond IDs, revisions, and kinds.

## Maintained by Codex

### Progress

- [x] Add the schema v5 table, migration, and generated Drift artifacts.
- [x] Track changes at the Business Commit Point and read them through the Workspace facade.
- [x] Pass focused acceptance tests for all expected change kinds, cursor behavior, rollback, and migration.
- [ ] Run the full acceptance gates after integration.

### Decision Log

- Keep independent revisions for Content, Metadata, and Removal in each Skill row so a later change preserves earlier kinds that remain newer than the cursor.
- Derive Content from a changed Revision selection. Read the affected Tag Assignments inside the same transaction before a tag deletion cascades.
- Read the metadata revision and feed rows in one SQLite transaction. A vocabulary row uses a reserved subject alongside the Skill rows.

### Surprises

### Follow-ups

### Outcome

On Dart 3.14.0, all 26 tests passed across the public facade, schema migration, and commit control-plane suites. These include rollback after a late commit failure and cursor reset against a saved pre-commit database. Strict package analysis, targeted formatting, and regeneration passed.
