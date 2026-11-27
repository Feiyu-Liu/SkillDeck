# ExecPlan: T25 Apply a remote Source Replacement

M5 follow-up for M4. Adds the `RemoteSkillSourceReplacement` variant of
`applyRemoteState`, decided by the maintainer on 2026-11-27. Contract:
`../m5-sync-apply-contract.md`, the variant row, `sourceReplaced`, and the
Source Replacement outline. Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

When another Device replaces a synced Skill's Source, this Device can apply the
new Generation in one Workspace transaction, without asking its user. The
Skill keeps its Managed Skill ID and everything a local Source Replacement
keeps. It gets the new Source and the new history from the pack.

### Context

- **Read first:**
  - root `CONTEXT.md`: Source Replacement, Source Lineage, Published Revision
    History, Skill Slot;
  - the M5 contract;
  - the T08 and T09 cards and their reviews in
    `../reviews/2026-11-24-m5-review.md`.
- **Reuse:**
  - **The local path:** `replaceSource` in `lib/src/api/skills_repository.dart`,
    with `source_replacement_preparation.dart` and the destructive handlers in
    `lib/src/composition/`. It deletes the previous lineage after the Business
    Commit Point is finalized.
  - **Install's pack path:** `remote_install_preparation.dart` creates a Store
    from a verified pack. T14 makes it write Recovery Bundles with history.
  - **Removal's guard:** T09's `RemoteSkillRemoval` already runs a destructive
    path guarded by `expectedEffective` instead of a `DestructiveIntent`,
    through `DestructivePlanningStatePort`. Follow the same pattern.
- **T11's rule** still holds: the generic operation layer names no
  `WorkspaceOperationKind`.

### Contract

- **New request variant:** `RemoteSkillSourceReplacement`, with
  `managedSkillId`, `expectedEffective`, `packPath`, `effective`, optional
  `upstream`, and `source`.
  - Its constructor rejects with `ArgumentError`, as `RemoteSkillInstall`'s
    does:
    - a Local or Adopted Snapshot descriptor;
    - a null `upstream`, except with a Synced Origin of
      `originSourceType: adoptedSnapshot`.
- **New result:** `sourceReplaced`.
- **The check order** follows T09's removal handler:
  1. the Skill exists, else `skillNotFound`;
  2. the `expectedEffective` guard, else `staleSnapshot` with
     `effectiveRevisionChanged`;
  3. the retry check: the requested Source Descriptor, Effective, and Upstream
     are already selected, so `noChange`;
  4. a Dirty Draft or an Update Candidate Session, so
     `draftResolutionRequired`;
  5. the pack verifies, with T02's outcomes on failure;
  6. a changed Declared Skill Name whose Skill Slot holds a different Skill, so
     `skillSlotOccupied(occupant)`.
- **Effect:** everything a local Source Replacement does, with the pack as the
  content and `effective` and `upstream` selected:
  - Activations;
  - Slot relocation;
  - metadata kept;
  - the previous lineage deleted after finalization.

  The committed-change feed records the Skill as a `content` change, plus
  anything a local Source Replacement records.
- No other public API change. No schema change unless the operation record
  needs one; if it does, say so in the Decision Log.

### Acceptance

Tests through the public API with real Stores, unless noted.

- **Replacement:**
  - a Git-sourced Skill with Activations, a Favorite, a Note, and tags gets a
    new Git Source from a pack with unrelated history;
  - it returns `sourceReplaced`;
  - the Managed Skill ID, Activations, metadata, and tags are kept;
  - Published History lists only the new history;
  - the previous Store is gone after finalization;
  - `exportRevisionPack` then exports the new history.
- **Synced Origin:** replacement onto a Synced Origin descriptor, with and
  without `upstream`, under Install's rules.
- **Validation:** each rejected constructor input throws `ArgumentError`.
- **Guards:**
  - each check-order case, including `noChange` on retry, leaves no Operation
    Record and changes nothing;
  - a Dirty Draft gives `draftResolutionRequired`;
  - a malformed or incomplete pack gives T02's outcomes.
- **Slot:**
  - a Declared Skill Name change onto a free slot relocates it;
  - onto a slot another Skill holds, it gives `skillSlotOccupied` with that
    occupant.
- **Crash and recovery (may use internal types):** a crash before the
  Business Commit Point leaves the old Source and history. A crash after it
  completes the replacement on recovery. The T08 and T09 crash harness
  patterns apply.
- **Feed:** the committed-change feed shows one `content` entry for the Skill.
- **Generic layer:** a search of `OperationCoordinator` and
  `DriftOperationControlPlane` finds no `WorkspaceOperationKind.`.
- **Gates:** the T01 gates, including `dart pub get --enforce-lockfile` and
  `dart run tool/regenerate.dart` with a clean tree afterwards. Report each
  command's own exit code.

### Scope fence

- **In scope:** `packages/skills_workspace/`.
- **Out of scope:**
  - `skills_cloud` (T26);
  - deciding whether this Device has unsynced revisions (T26);
  - changing local `replaceSource` behaviour;
  - the native layer.
- **Expected size:** about 12–20 files, 1,000–1,800 lines including tests.

### Stop and ask if

- The local Source Replacement path cannot be reused without changing its own
  behaviour.
- It needs a new journal phase or recovery entry kind.
- Keeping metadata or Activations differs from what a local Source Replacement
  does.

## Maintained by Codex

### Progress

- [x] Add RemoteSkillSourceReplacement and sourceReplaced.
- [x] Reuse remote pack preparation and local replacement transaction/recovery.
- [x] Preserve identity, Activations and metadata while replacing history.
- [x] Cover validation, guard order, slots and real before/after-commit crashes.

### Decision Log

- Split the existing planner's prepared-candidate assembly into a shared method. Local acquisition still supplies its original single-root candidate; remote preparation supplies separately selected Effective/Upstream metadata.
- The plan alignment guard now accepts exactly the selected one or two revision records in the new lineage. Local replacement behavior is unchanged.
- Remote expected guard failures finish as unchanged preparation: operation-owned staging is rolled back without a retained Operation Record. No generic coordinator/control-plane changes, new journal phase, recovery kind or schema migration.
- Installation's adopted-snapshot rule remains the current card's rule: a null external Upstream uses Effective as the receiver's private recovery baseline, omitted from outward inspection/export.

### Surprises

- Durable publish only accepts direct siblings. Remote preparation moves its verified Store/Bundle between operation-owned staging directories and flushes both parent directories before sealing the existing destructive plan.
- The shared crash helper needed the same destructive/backup maintenance collaborators as production; its content/install paths remain covered by the full suite.

### Follow-ups

No native code or local replaceSource behavior was changed. Cross-platform release acceptance remains separate from these macOS tests.

### Outcome

Six real Workspace scenarios pass, including both crash boundaries. Full gates and coverage are recorded in ../validation/m4-client-workspace-2026-11-27.md.
