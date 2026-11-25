# ExecPlan: T13 Recovery Bundles that keep every retained revision

Milestone M5. Fixes item T08-1 of `../reviews/2026-11-24-m5-review.md`. The
defect predates Cloud. Decision: option (a), chosen by the maintainer on
2026-11-25. Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

After a Skill's revision Store is lost, the Workspace rebuilds it from the
Recovery Bundle and opens. The Skill's Published History, Restore Publish, and
export work again. This holds no matter how many times the Skill was published.

### Context

- **Defect:** the probe in the review, run on `8393db6`:
  1. install a local Skill;
  2. publish two Drafts;
  3. close the Workspace and move the Store aside;
  4. reopen it.

  Reopening fails with `recoveryFailed`, `{reason:
  revisionReferenceReconciliationFailed}`. The rebuilt Store lacks the first
  publish.
- **Cause:**
  - Each operation rebuilds the Skill's bundle from only a few roots, for
    example publish's `[commit]` plus the current Upstream and Effective. See
    the `_writeRecoveryBundle` callers in
    `lib/src/composition/revision_preparation_service.dart`, and also
    `remote_content_preparation.dart`, `remote_install_preparation.dart`, and
    `source_replacement_preparation.dart`.
  - The native recovery pack stores each root's commit and tree, not its
    parents.
  - At open, `DriftRevisionReferenceReconciliation` wants a retention ref for
    every object in Published History. When one is missing, open fails.
- **Decision (a):** a bundle's roots include every object that reference
  reconciliation retains for the Skill's lineage, so the native call and the
  manifest format stay the same. Option (b), a bundle that always carries full
  history, was not chosen.
- **Existing code to reuse:**
  - `_readDesiredStores` and `_addPublishedHistory` in
    `lib/src/infrastructure/database/drift_revision_reference_reconciliation.dart`
    give the exact set to cover;
  - `_readPublishedRoots` in `drift_draft_update_state.dart` already feeds
    Published History roots to the Update Candidate paths.

### Contract

No public API, schema, native, or manifest-format change.

- **Bundle roots:** every Recovery Bundle a mutation writes has roots that
  include every object reference reconciliation would retain for that lineage
  once the operation commits:
  - the Upstream and Effective;
  - every before and after object in Published History;
  - the Draft base;
  - the Update Candidate Session objects.

  Refs for in-flight operation plans are excluded; journal recovery handles
  them.
- **One rule:** derive the set in one place, so a new mutation cannot forget
  it. Prefer the smallest mechanism, and record it in the Decision Log.
- **T08:** keep `includeHistory` for the initial install bundle unless the new
  rule makes it redundant. Say which in the Decision Log.

### Acceptance

Each item is a test through the public API with a real Store, unless noted.

- **The probe:**
  1. install, publish twice, close, and move the Store aside;
  2. reopen.

  Then:
  - open succeeds, and the Skill reports `recovered`;
  - Published History lists the same entries as before the loss;
  - Restore Publish of the first publish succeeds and shows its files;
  - `exportRevisionPack` succeeds.
- **Other retained objects:** the same loss and reopen also succeed when the
  Skill has:
  - a Dirty Draft whose base is an older revision;
  - an open Update Candidate Session;
  - a Restore Publish in its history.

  Use the existing fixtures. If one case is costly to build, say so in
  Surprises rather than dropping it silently.
- **Invariant:** after a mixed sequence of operations, every object in
  reconciliation's desired set for the lineage is in the live bundle's
  manifest roots. The sequence is install, publish, Restore Publish, a remote
  content apply, and a remote install. This test may use internal types.
- **Record, do not fix:** for a Skill whose Effective came from
  `applyRemoteState` with remote-only ancestors, run the same loss and reopen,
  and report in Surprises:
  - whether open succeeds;
  - whether `exportRevisionPack` succeeds.

  Decision (a) does not keep those ancestors, so export may fail. The
  maintainer decides afterwards.
- All existing crash, recovery, and bundle tests pass unchanged, or the
  Decision Log says why one changed.
- **Gates:** the T01 gates. Report each command's own exit code.

### Scope fence

- **In scope:** `packages/skills_workspace/`.
- **Out of scope:**
  - native, schema, and manifest-format changes;
  - rebuilding existing Workspaces' bundles at open;
  - keeping remote-only or donor ancestors;
  - changing what reconciliation retains;
  - T09.

  Existing Workspaces keep a short bundle until the next operation on each
  Skill. Whether to rebuild bundles at open is a separate decision.
- **Expected size:** about 5–10 files, 200–500 lines including tests.

### Stop and ask if

- A desired object can be missing from a live Store in a Workspace that opens
  today, so adding it as a root would make a mutation fail.
- Bundle building becomes noticeably slower in an existing performance or
  timing test.
- The fix needs a native, schema, or manifest change, or a change to what
  reconciliation retains.
- Source replacement, Removal, or another path writes bundles in a way that
  the one rule cannot cover.

## Maintained by Codex

### Progress

- [ ] …

### Decision Log

### Surprises

### Follow-ups

### Outcome
