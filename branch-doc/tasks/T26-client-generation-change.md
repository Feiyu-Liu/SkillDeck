# ExecPlan: T26 Client: Generation change in both directions

Milestone M4, client side, after T23. It can run in parallel with T24 and
T25; it needs T25's contract, not its code. Simplicity rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

A Source Replacement on one Device reaches the others:
- the Device that replaced the Source starts a new Generation of the Lineage;
- every other Device applies it without asking, unless an Attention Reason
  stops it.

### Context

- **Read first:**
  - R3, R4, and R10;
  - contract v0.1, the Upload and Generation change sections;
  - the M5 contract's Source Replacement outline (T25);
  - T23's `Reconciler`, ports, and fakes.
- A Generation change is atomic on the service. A Device never sees a new
  Generation without its head.

### Contract

- **Port:** `SyncWorkspace` gains the `RemoteSkillSourceReplacement` apply with
  its results. The fake Workspace implements T25's behaviour: unrelated
  history, the Skill kept, and the check order.
- **State:** `SyncStateStore` keeps, per linked Skill, the Generation and the
  head Effective it last reconciled.
- **Outbound:** a linked Skill's Portable Source differs from the Lineage's
  `source` after a local change. Then the Device:
  1. exports a Head Pack;
  2. uploads it to Generation g + 1;
  3. calls Generation change, expecting g.

  On `wrongGeneration`, it reconciles with the returned Lineage.
- **Inbound:** the Lineage's Generation is newer than the one reconciled here.
  - **Unsynced revisions here:** the local Effective differs from the head
    Effective last reconciled. The outcome is Needs Attention, "Source replaced
    on another Device while this Device has unsynced revisions". Nothing is
    applied.
  - **Otherwise:**
    1. download the new head's pack;
    2. apply `RemoteSkillSourceReplacement`, mapping a Device-Bound Portable
       Source to a Synced Origin Source.

    `sourceReplaced` makes the Skill Synced. `draftResolutionRequired` and
    `skillSlotOccupied` map to the R10 reasons, as in T23.
- **Resolving actions** for the new reason:
  - **Accept the replacement:** apply it as above. This Device's unsynced
    revisions are lost; say so in the method's documentation.
  - **Keep this Device's copy as Device Only:** unlink the Skill here, and add
    a Device Exclusion for the Lineage, so that later checks do not reinstall
    it into the same slot.
- **Both Devices replace the Source at once:** one Generation change wins. The
  other Device gets `wrongGeneration` and reconciles. Its own replacement then
  counts as unsynced revisions, so it gets the Attention Reason.

### Acceptance

Each item is a test with T22's fake service and T23's fake Workspace.

- **Outbound:** after a local Source Replacement, the Lineage is at
  Generation 2 with the new head and `source`.
- **Inbound:** the other Device's Skill gets the new Source and history, and
  keeps its Managed Skill ID. A Device-Bound Source arrives as Synced Origin.
- **Unsynced revisions:**
  - a local publish not yet uploaded gives the Attention Reason;
  - accept applies the replacement;
  - keep-as-Device-Only unlinks and excludes, and a later Feed Check leaves the
    Skill alone.
- **Draft** and **slot occupied** give their reasons, with nothing applied.
- **Both at once:** the two-Device race from the Contract ends with one
  Generation 2 head, and the Attention Reason on the losing Device.
- **Lost responses:** Generation change commits but the response is lost; the
  next check ends Synced, with no third Generation.
- **Gates:** T16's gates, each with its own exit code; line coverage of the new
  files reported.

### Scope fence

- **In scope:** `packages/skills_cloud/`.
- **Out of scope:**
  - `skills_workspace` (T25);
  - the App and its prompts (M7);
  - metadata and tags.
- **Expected size:** about 6–12 files, 800–1,500 lines including tests.

### Stop and ask if

- Telling unsynced revisions apart needs anything beyond the reconciled head
  and the local selection.
- A case needs ancestry decided outside the Workspace.

## Maintained by Codex

### Progress

### Decision Log

### Surprises

### Follow-ups

### Outcome
