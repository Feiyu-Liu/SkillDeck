# ExecPlan: T08 Installing a synced Skill from a pack

Milestone M5. Builds on T02, T07, T11, and T12. Plan: `../phase1-plan.md`.
Contract: `../m5-sync-apply-contract.md`, sections "Seam 3", "Results", and
"Other variants" (Install). Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

A Device that does not have a synced Skill yet can create it from a
downloaded Head Pack in one guarded transaction. The new Skill has the given
Effective and Upstream Revisions, its history, and its Source Descriptor, and
no Activations. If a different local Skill already holds the Skill Slot, the
Workspace says which one and changes nothing.

### Context

- Decisions:
  - R6: a new Device materializes each Cloud Lineage and creates no
    Activations;
  - R7: Local and Adopted Snapshot Sources arrive on other Devices as a
    Synced Origin Source;
  - maintainer decision 2026-11-24: a new Device installs straight from a
    pack file.
- **Closest flows,** under `packages/skills_workspace/lib/src/`:
  - **Install:** `application/install/initial_import_planner.dart`, and
    `prepareInitialRevisions` / `_createStoreAndBundle` in
    `composition/revision_preparation_service.dart`. They create a candidate
    Store from a tree and promote it with the operation's recovery entries.
  - **Slot collision:** `_validateNewSlot` in `initial_import_planner.dart`.
    It returns `sourceReplacementRequired`; remote install returns
    `skillSlotOccupied(occupant)` instead.
  - **Pack into a Store:** `prepareRemoteRevisionStore` in
    `composition/remote_revision_store.dart` (T07) and `stageRevisionPack`
    (T02).
  - **Command shape:** `composition/remote_content_command.dart` (T07, after
    T11), including `OperationPreparationUnchanged` for results that change
    nothing.
- **History:** the new Device's Published Revision History of earlier commits
  comes from the service's `lineage_revisions` projection (ADR-0105 revision,
  Sync data), not from the Workspace. The Workspace only records the install
  operation itself.

### Contract

Names are provisional.

- Add `RemoteSkillInstall` to `ApplyRemoteStateRequest`, with:
  - `packPath`;
  - `effective: RevisionId` and `upstream: RevisionId?`;
  - `source`: a Git, Well-known, or Synced Origin Source Descriptor. The
    constructor rejects a Local or Adopted Snapshot descriptor with an
    `ArgumentError`, because those are Device-Bound (R7).
- **Absent Upstream (decided 2026-11-25, answering Codex's question):**
  - `upstream` may be null only when `source` is a Synced Origin whose
    `originSourceType` is `adoptedSnapshot`. Such a Skill has no tracked
    Upstream, which is why `exportRevisionPack` omits it on the origin Device.
  - The constructor throws `ArgumentError` when `upstream` is null for any
    other source, or set for that one.
  - When it is null, the internal Upstream is the root commit of
    `effective`'s history. On the origin Device, adoption sets the internal
    Upstream to the initial commit and later publishes never move it, so both
    Devices then hold the same baseline.
  - `exportRevisionPack` and `inspectRevisionSelections` still report no
    Upstream for the installed Skill.
- **Same gap in T07:** make `RemoteSkillContent.upstream` nullable. Null means
  the Lineage Head has no Upstream: keep the local internal Upstream, and skip
  the contract's Upstream rule. Do not check the Source here.
- Add two results to `RemoteApplyResult`:
  - `installed(managedSkillId)`;
  - `skillSlotOccupied(occupant: ManagedSkillId)`.
- **Behaviour:**
  - the pack must contain the full closure of `effective` and, when given,
    `upstream`;
  - the new Skill's Slot Key and names come from `effective`'s tree, which
    must be a valid Skill;
  - the Skill is created with the given descriptor, a new Source Lineage, and
    a selection of `effective` and the Upstream above. It has no Draft and no
    Activations;
  - the committed-change feed reports `content` for the new Skill (T06 should
    already do this through the selection change).
- **Slot rules:**
  - a different Skill in the slot returns `skillSlotOccupied(occupant)`;
  - **retry:** if the occupant's current Effective and Upstream equal the
    request's and its Source Descriptor equals `source`, the call returns
    `installed(occupant)` and changes nothing. This makes a lost response safe
    to retry without remembering callers. Commit IDs include their creation
    time, so an independent local Skill never matches by accident.
- **Expected failures,** using existing codes:
  - a malformed, incomplete, or unreadable pack: the T07 pack failures;
  - an invalid `effective` tree: `invalidSkill`, or `unsupportedSkillName`;
  - cancellation: `operationCancelled`.
- **Not in this card:** initial metadata. `skills_cloud` sets Favorite, Note,
  and Tag Assignments afterwards with T09's `RemoteSkillMetadata`. The
  contract is updated to match.

### Acceptance

Each item is a test through the public API with a real Store and a pack made
by `exportRevisionPack` on a donor Workspace. Use the existing fixtures,
including `test/support/remote_revision_pack_fixture.dart`.

- **Install:**
  - returns `installed(id)`;
  - `inspectRevisionSelections` returns exactly `effective` and `upstream`;
  - the Repository Copy shows `effective`'s files, and there are no
    Activations;
  - the Source Descriptor reads back equal to `source`;
  - a later `exportRevisionPack` of the new Skill contains the donor's
    history;
  - the committed-change feed reports `content` for `id`.
- **Adopted Snapshot origin:**
  - a donor that adopted a snapshot and then published locally installs on
    the new Workspace with a null `upstream`;
  - the new Skill's internal Upstream is the root commit, and
    `exportRevisionPack` and `inspectRevisionSelections` report no Upstream;
  - a later content apply with a null `upstream` keeps that internal Upstream.
- **Request validation:** a null `upstream` with any other source, and a
  non-null one with an Adopted Snapshot origin, both throw `ArgumentError`.
- **Customized donor:** with a donor whose Effective differs from its
  Upstream, both are installed as given.
- **Synced Origin:** a donor installed from a Local Source installs on the new
  Workspace with a Synced Origin descriptor, and Update on it fails with
  `updateUnsupported`, as source acquisition already does for Synced Origin.
- **Slot occupied:** a different local Skill in the slot gives
  `skillSlotOccupied` with its ID, and nothing changes.
- **Retry:** repeating a successful install returns `installed` with the same
  ID, does not bump the revision, and leaves no Operation Record.
- **Failures:** a malformed or incomplete pack and an invalid `effective`
  each leave SQLite, the Stores, and the filesystem unchanged, and leave one
  failed Operation Record, as T11 requires.
- **Crash:** a crash before and after the Business Commit Point recovers to
  "not installed" and "installed" respectively, using the existing crash
  harness from T07.
- **Gates:** the T01 gates.

### Scope fence

- **In scope:** `packages/skills_workspace/`, including making
  `RemoteSkillContent.upstream` nullable, and the Install outline in the
  contract.
- **Out of scope:**
  - initial metadata, Favorite, Note, and Tag Assignments (T09);
  - Removal and the tag vocabulary (T09);
  - creating Activations, or the new-Device activation step (M7);
  - linking an existing local Skill to a Lineage, which `skills_cloud` decides
    from `skillSlotOccupied` (R6 Linking);
  - Generation changes;
  - App changes;
  - native and schema changes.
- **Expected size:** about 12–20 files, 650–1,200 lines including tests.

### Stop and ask if

- The install needs a new journal phase, recovery entry kind, or schema
  change.
- Reusing the install planner would mean threading Cloud flags through it. In
  that case, prefer a small separate assembler, as T07 did.
- The Source Lineage or Source rows need something the descriptor cannot
  provide, for example a locator or a fetch time for a Git Source.
- A pack whose `upstream` is not an ancestor of `effective` cannot be
  installed with the current selection rules.
- `effective`'s history has more than one root commit, so the internal
  Upstream for an Adopted Snapshot origin is ambiguous.

## Maintained by Codex

### Progress

- [ ] …

### Decision Log

### Surprises

### Follow-ups

### Outcome
