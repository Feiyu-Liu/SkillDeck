# ExecPlan: T12 Reading the current revisions of Skills

Milestone M5. Builds on T01 and T06. Contract: `../m5-sync-apply-contract.md`,
section "Seam 4: current revisions". Decision: M5 review item 3, option C,
decided by the maintainer on 2026-11-24. Simplicity rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

`skills_cloud` can learn the current Effective and Upstream `RevisionId` of
the Skills it syncs with one cheap read, without exporting a pack.

### Context

- Today only `exportRevisionPack` returns these identifiers, and it writes a
  full-history pack to do it.
- `DriftRevisionPointerReader.readCurrentPackHeads` in
  `lib/src/infrastructure/database/drift_revision_pointer_reader.dart` already
  reads one Skill's heads, including the rule for when Upstream is absent.
  `exportRevisionPack` uses it.
- `inspectCommittedChanges` (T06) is the closest public read to copy:
  - its request and result types;
  - its handler in `lib/src/composition/read_command_handlers.dart`;
  - its entries in `WorkspaceOperationKind` and in
    `corrupt_skill_mutation_guard.dart`.

### Contract

Names are provisional.

- `SkillsRepository.inspectRevisionSelections(InspectRevisionSelectionsRequest)`
  returns `SkillsOperation<RevisionSelections>`.
  - The request holds a set of `ManagedSkillId`s. An empty set is allowed and
    gives an empty result.
  - `RevisionSelections` holds `current` (a `RepositoryRevision`) and, for each
    requested Skill that exists, `effective: RevisionId` and
    `upstream: RevisionId?`.
- **Rules:**
  - a requested Skill that does not exist, including a removed one, is left
    out of the result and is not an error;
  - Upstream is absent exactly when `exportRevisionPack` omits it;
  - `current` and every selection come from one SQLite transaction;
  - the operation reads only SQLite. It never opens the revision Store.
- **Expected failures:** `operationCancelled`. Anything else follows what the
  existing reads do.

### Acceptance

Each item is a test through the public API with the existing facade fixtures.

- After install, the result's `effective` and `upstream` equal what
  `exportRevisionPack` returns for the same Skill.
- After a local publish, `effective` is the new commit.
- After `applyRemoteState`:
  - `fastForwarded`: `effective` is the target;
  - `merged`: `effective` is `newEffective`;
  - `conflicted`: `effective` is unchanged.
- An Adopted Snapshot Skill has no `upstream`.
- An unknown ID and a removed Skill are left out, while the other requested
  Skills are still returned.
- With no change between them, `current` equals the `current` from
  `inspectCommittedChanges`.
- The call does not bump the RepositoryRevision and writes no journal or
  Operation Record.
- **Gates:** the T01 gates. No native or schema change is expected.

### Scope fence

- **In scope:** `packages/skills_workspace/`.
- **Out of scope:**
  - adding revision identifiers to the snapshot, the public Skill model, or
    the committed-change feed;
  - T08 and T09;
  - App changes.
- **Expected size:** about 5–9 files, 150–350 lines including tests.

### Stop and ask if

- The read needs a schema change, or needs to open the revision Store.
- Upstream for some Source kind cannot follow `exportRevisionPack`'s rule.
- You want to cap or page the request. Say why first.

## Maintained by Codex

### Progress

- [ ] …

### Decision Log

### Surprises

### Follow-ups

### Outcome
