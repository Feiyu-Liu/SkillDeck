# ExecPlan: T07 Applying remote content to an existing Skill

Milestone M5. Builds on T01, T02, and T05. Independent of T06. Plan:
`../phase1-plan.md`. Contract: `../m5-sync-apply-contract.md`, sections "Seam 3",
"Results", and "Content rules". Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

Given an existing managed Skill, the revision `skills_cloud` last saw as its
Effective Revision, and a target Lineage Head (`effective`, `upstream`), the
Workspace brings the Skill to that head in one guarded transaction. It
fast-forwards, publishes a clean Sync Merge, or opens an Update Candidate
Session, and reports which.

### Context

- Decisions: R3 and R4. A clean Sync Merge publishes automatically, and a
  conflicting one uses the existing conflict review.
- The closest existing flow is Update. Most of what T07 needs exists there,
  under `packages/skills_workspace/lib/src/`:
  - **Update handler:** `composition/update_command_handlers.dart`, then
    `OperationCoordinator.executeDeferred`.
  - **Planning and assembly:** `application/update/update_planner.dart`, which
    has `planUpdate`, the clean-publish assembly, and `_assembleSession` for
    conflicts.
  - **Merge and publish:** `WorkspaceRevisionPreparationService.prepareUpdate` in
    `composition/revision_preparation_service.dart`. It runs the merge, creates
    the merge commit, writes the recovery bundle, and stages materialization.
  - **Dirty Draft check:** `UpdateDraftInspectionPort.inspectForUpdate` and
    `inspectForCleanup`. They map to `dirtyDraftResolutionRequired`, and an
    existing Session maps to `updateCandidateResolutionRequired`.
  - **Effective guard:** `DriftResolutionPlanner.validateEffectiveRevision` in
    `application/drift/drift_resolution_planner.dart`.
  - **Pointer change:** `RevisionSelectionChangePlan`, checked at commit by
    `_requirePreviousSelection`.
  - **Revision engine:** `RevisionEnginePort.isAncestor` and `merge`.
- Two things have no precedent:
  - **Moving the Effective pointer to a commit that already exists.** Restore
    Publish creates a new commit instead. A `RevisionSelectionChangePlan`
    whose intended Effective is an existing object, with no commit creation,
    already expresses it.
  - **A merge base.** `merge` takes its base as `previousUpstream`. A Sync Merge
    needs the real merge base of L and R, so the engine gains a merge-base
    operation (libgit2 `git_merge_base`).

### Contract

Names are provisional.

- `SkillsRepository.applyRemoteState(ApplyRemoteStateRequest)` returns a
  `SkillsOperation<RemoteApplyResult>`.
  - `ApplyRemoteStateRequest` is a sealed type. This task adds only
    `RemoteSkillContent`, with `managedSkillId`, `expectedEffective`,
    `effective`, `upstream`, and an optional `packPath`. All revisions are
    `RevisionId`s.
  - `RemoteApplyResult` is a sealed type. This task adds `noChange`,
    `fastForwarded`, `merged(newEffective: RevisionId)`, `conflicted`, and
    `draftResolutionRequired`.
  - T08 and T09 add their variants and results later. Do not add them now.
- **Expected failures,** using existing codes:
  - guard mismatch: `staleSnapshot` with `reason: effectiveRevisionChanged`;
  - unknown Skill: `skillNotFound`;
  - missing objects: `revisionStoreCorrupt`;
  - cancellation: `operationCancelled`.

  When `packPath` is given, a malformed or incomplete pack fails with the T02
  import outcome mapped to a typed failure, and nothing else changes.
- **Internal engine addition:** `mergeBase(repositoryPath, a, b)` returns the
  best common ancestor. It goes through the worker and the native layer, and is
  not public.
- **Behaviour:** the decision table, merge outcomes, Upstream rule, and object
  rule in the contract's "Content rules".

### Acceptance

Each item is a test through the public API with a real Store. Use the existing
public facade test fixtures.

- **No change:** L = R returns `noChange`, and the revision does not bump. R an
  ancestor of L also returns `noChange`.
- **Fast-forward:**
  - L an ancestor of R returns `fastForwarded`;
  - Effective is exactly R, and no new commit exists;
  - the Repository Copy and Activations show R's files;
  - a clean Draft is re-anchored.
- **Clean merge:**
  - Divergent, non-conflicting histories return `merged`;
  - the new commit has parents `[L, R]` and the merged tree;
  - Activations show it.
- **Conflict:**
  - Conflicting histories return `conflicted`;
  - an Update Candidate Session exists, and the existing resolve and publish
    flow completes it;
  - Effective is unchanged until then.
- **Blocked Skill:** a Dirty Draft or an existing Session returns
  `draftResolutionRequired`, and nothing changes.
- **Upstream:** the descendant Upstream is kept when one descends from the
  other. Otherwise the target `upstream` is kept.
- **Guard:** a wrong `expectedEffective` gives `staleSnapshot`, and nothing
  changes.
- **Objects:** with `packPath`, objects that exist only in the pack are applied.
  A failure or cancellation before commit leaves the live Store, SQLite, and
  the filesystem as they were, including after a simulated crash, using the
  existing crash or recovery harnesses. After commit, the Skill's used staging
  is gone.
- **Repeats:** repeating a successful call with the refreshed
  `expectedEffective` returns `noChange`. A repeat with the old guard returns
  `staleSnapshot` (wording corrected 2026-11-24, M5 review item 2).
- **Gates:**
  - the T01 gates;
  - native changes need `dart run tool/regenerate.dart`, a clean tree, and the
    native test suite.

### Scope fence

- **In scope:** `packages/skills_workspace/`, `native/` included.
- **Out of scope:**
  - Install, metadata, Removal, and vocabulary (T08, T09);
  - Generation changes;
  - the committed-change feed (T06);
  - App changes;
  - schema changes.
- **Expected size:** about 15–25 files, roughly 900–1,600 hand-written lines
  including C and tests.

### Stop and ask if

- Moving the pointer to an existing commit needs a new journal or recovery
  entry kind.
- Staged objects cannot enter the live Store as a recovery entry that rolls
  back cleanly.
- The Sync Merge needs a change to the existing `merge` semantics. The Update
  flow must keep its behaviour.
- Reusing the Update assembly would mean threading Cloud-specific flags through
  Update code. In that case, prefer a separate small assembler.
- The work would need a schema change.

## Maintained by Codex

### Progress

- [x] Wired the guarded public operation for existing managed Skills.
- [x] Tested pack staging, fast-forward, clean merge, conflict resolution, and
  recovery before and after the Business Commit Point.

### Decision Log

- The operation validates objects in an operation-owned Store. Its recovery
  entries publish only new Git object paths. Existing objects stay readable
  during a crash and retention refs can be updated independently.
- A conflict candidate records both merge parents in Git. Its Session keeps
  the selected Upstream so the existing publish flow can preserve both facts.
- Clean Drafts are re-materialized at their new base. Recovery checks the
  previously observed Draft fingerprint when it captures the before image.
- A retry with a stale Expected Effective returns `staleSnapshot`. Refresh the
  guard and repeat to get `noChange` when the target is already contained.

### Surprises

### Follow-ups

### Outcome

Local macOS arm64 gates used Dart 3.14.0. The full Workspace suite passed
1,624 tests, with the network suite skipped by default. The native
integration suite passed two tests, and the native runtime and ABI checks
passed. The coverage gate passed at 89.06% line coverage. Lockfile
resolution, formatting, strict analysis, and reproducible generation of
the Drift schema and FFI bindings passed.
