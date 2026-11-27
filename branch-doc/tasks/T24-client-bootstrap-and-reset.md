# ExecPlan: T24 Client: new-Device bootstrap, reset, and Device Exclusions

Milestone M4, client side, part 3 of 3, after T23. Simplicity rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

A newly signed-in Device materializes every Cloud Lineage it has not excluded.
A Device whose feed cursor has expired resets without re-uploading anything.
Device Exclusions keep chosen Lineages off one Device.

### Context

- **Read first:**
  - R6 (new Device, linking, reset) and R10;
  - contract v0.1, sections Cloud Library and Account Change Feed, especially
    `feedCursor` and `410 cursorExpired`;
  - T23's `Reconciler`, ports, and fakes.
- **Linking** an existing local Skill to a Lineage is automatic only on an
  exact Portable Source, Slot Key, and content match (R6). Content match here
  means the local Effective equals the head's Effective.

### Contract

- **Bootstrap:** list the whole library, then for each Lineage:
  - **excluded:** skip it;
  - **a local Skill matches exactly:** link it, then reconcile it as in T23;
  - **otherwise:** download the head's pack and apply `RemoteSkillInstall`,
    mapping a Device-Bound Portable Source to a Synced Origin Source;
  - **`skillSlotOccupied`:** Needs Attention, "Skill Slot occupied by a
    different local Skill". The actions are replace the local Skill, or keep
    it and add a Device Exclusion.

  Then set the feed cursor to the listing's `feedCursor`.

  Bootstrap creates no Activations. Report the installed Skills, so the App can
  offer its one-time activation step in M7.
- **Reset,** on `cursorExpired`: bootstrap again. Each linked Skill whose
  Lineage is missing from the library becomes Needs Attention, "Missing from
  the Cloud Library after a reset". The actions are remove it here, keep it
  here as Device Only, or Upload it as a new Cloud Lineage. It is never
  re-uploaded automatically.
- **Device Exclusions:** add or remove one, kept in `SyncStateStore`.
  - Adding an exclusion for a linked Skill unlinks it here and changes nothing
    in the Cloud Library.
  - Removing an exclusion lets the next bootstrap or Feed Check materialize the
    Lineage.
- **Resolving actions:** methods for the actions of the two Attention Reasons
  above. Each one runs through the Workspace port and `CloudApi`.

### Acceptance

Each item is a test with the fakes.

- **New Device:** with three Lineages, two of them Device-Bound on another
  Device, all three are installed. Device-Bound ones get a Synced Origin
  Source. The feed is then read from `feedCursor`, and a change made during the
  listing is not missed.
- **Exact match** links without installing; a near match (same Slot Key,
  different content) does not link.
- **Slot occupied:** the outcome is right, and each resolving action is
  tested.
- **Exclusion:** an excluded Lineage is skipped by bootstrap and by later Feed
  Checks; removing the exclusion materializes it.
- **Reset:**
  - after `cursorExpired`, a Skill whose Lineage was removed long ago becomes
    "Missing from the Cloud Library after a reset", with no Upload;
  - each of its three actions is tested, and "Upload it as a new Cloud Lineage"
    creates a new Lineage.
- **Lost responses** during bootstrap (a list page, a download) end correctly
  on the next run, with no duplicate install.
- **Gates:** T16's gates, each with its own exit code; line coverage of the new
  files reported.

### Scope fence

- **In scope:** `packages/skills_cloud/`.
- **Out of scope:**
  - Generation change;
  - metadata and tags;
  - the App and its activation step (M7);
  - durable state;
  - changing `skills_workspace`.
- **Expected size:** about 8–14 files, 1,000–1,800 lines including tests.

### Stop and ask if

- The exact-match rule needs a Workspace read that the M5 contract and T23's
  port do not have.
- Bootstrap needs to create Activations.

## Maintained by Codex

### Progress

- [x] Bootstrap through paged Library reads, exact matching and pack installs.
- [x] Reset expired cursors without automatically re-uploading missing Skills.
- [x] Implement exclusions and explicit slot/missing-copy resolution actions.
- [x] Cover lost reads and repeat bootstrap without duplicate installs.

### Decision Log

- Linking compares PortableSource, the Workspace-derived Slot Key, and Effective. Existing links to a different Lineage are not silently reassigned.
- Removing a Device Exclusion clears the feed cursor. The next check re-lists, even without a newer remote version, and can recover after a network failure.
- Replacing an unlinked bootstrap occupant uses T25's now-available replacement seam. If it replaces a copy linked elsewhere, that previous Lineage is excluded locally after success. A Generation-change slot collision on an already linked Skill must first be resolved locally, preserving the original managed identity.
- Bootstrap reports installed IDs and creates no Activations. Lost list/download responses leave its cursor unadvanced.

### Surprises

None.

### Follow-ups

Activation prompts and durable Device Exclusions remain M7.

### Outcome

Bootstrap/reset/exclusion tests pass. Final gates and coverage: ../validation/m4-client-workspace-2026-11-27.md.
