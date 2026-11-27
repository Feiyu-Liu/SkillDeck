# ExecPlan: T23 Client: Reconciliation, Upload, and Download for linked Skills

Milestone M4, client side, part 2 of 3, after T22. Implements R3 and R4 for
Skills that are already linked to a Cloud Lineage, plus starting, stopping, and
removing sync. T24 adds new-Device bootstrap and reset. Simplicity rules: see
`../execplan-template.md`.

## Set by the planner

### Goal

`skills_cloud` keeps each linked Skill in step with its Lineage Head:
- it applies remote changes through the Workspace;
- it Uploads local ones;
- it Sync Merges a Divergence;
- it propagates Synced Removal and Stop Syncing.

It keeps no outbox, and it reports a typed outcome per Skill. Every test runs
against T22's fake service and a fake Workspace.

### Context

- **Read first:**
  - R3, R4, R6, and R10;
  - `packages/skills_cloud/CONTEXT.md`, Personal Sync and Boundary with Skill
    Workspace;
  - contract v0.1, especially "Client flow (informative)";
  - `../m5-sync-apply-contract.md`, for the Workspace seams and their results.
- **`skills_cloud` does not depend on `skills_workspace`,** so it stays pure
  Dart. It defines a port for the Workspace operations it needs, and the App
  adapts `SkillsRepository` to it in M7. The operations are:
  - `inspectRevisionSelections`;
  - `inspectCommittedChanges`;
  - `exportRevisionPack`;
  - `applyRemoteState` with `RemoteSkillContent`, `RemoteSkillInstall`, and
    `RemoteSkillRemoval`;
  - and a read of a Skill's Source Descriptor and Declared Skill Name.
- **The Workspace decides ancestry,** so the client never parses commit IDs.
  - `applyRemoteState` with the head's pack answers `noChange` when the head is
    equal to or behind the local Effective.
  - It answers `fastForwarded`, `merged`, `conflicted`, or
    `draftResolutionRequired` otherwise.
  - So the client learns that it is ahead from `noChange` with L ≠ R, and then
    Uploads.
- **T04's `FeedCheckScheduler`** triggers Feed Checks. T23 provides the check
  it calls.

### Contract

New public API of `skills_cloud`. Names may change; record why in the Decision
Log.

- **`SyncWorkspace` port:** the operations above, as typed methods. Paths are
  strings.
  - Its results mirror the Workspace's: the M5 results, the export failures,
    `skillNotFound`, and `skillSlotOccupied`.
  - Ship a fake implementation in `testing.dart`. It keeps commits and files in
    memory, decides ancestry, merges cleanly when two sides edit different
    files and conflicts otherwise, and writes T22's fake pack encoding.
- **`PortableSource`:** the device-independent form of a Source Descriptor, per
  CONTEXT.md.
  - Git and Well-known keep their portable fields.
  - Device-Bound Sources keep only the source type, the Origin Device label,
    and a display label. They carry no path.
  - It has a versioned JSON encoding, used as the contract's `source`. Read
    `packages/skills_workspace/lib/src/domain/source_descriptor.dart` for the
    fields.
  - **The other direction:** a non-origin Device installs a Device-Bound
    Source as a Synced Origin Source (T03).
- **`SyncStateStore` port, with an in-memory implementation:** per linked Skill
  it holds the Lineage ID, the last reconciled Lineage `version`, and the
  `clientKey` while a create is pending. Per Device it holds the Account Change
  Feed cursor and the Workspace committed-change cursor. Durable storage is M7.
- **`Reconciler`:** built with `CloudApi`, the `SyncWorkspace`, the
  `SyncStateStore`, and a scratch directory for packs.
  - **Feed Check:** reads the feed from the cursor, then reconciles each
    changed Lineage whose version is newer than the version last reconciled. It
    returns T04's `FeedCheckResult`, passing `Retry-After` through.
  - **Local changes:** reads Workspace committed changes, then reconciles each
    changed linked Skill. A local removal of a linked Skill sends Synced
    Removal.
  - **Start syncing a Skill:** creates the Lineage with a stored `clientKey`,
    Uploads, and advances from `null`.
  - **Stop syncing a Skill:** sends `stop`, then unlinks it locally. The Skill
    stays as Device Only.
  - **Per-Skill reconciliation,** following the contract's client flow:
    - Remote `removed`: apply Removal.
    - Remote `stopped`: unlink, and keep the Skill as Device Only.
    - **Remote content:** download the head's pack and apply it.
    - **Uploads:** Upload after `merged`, or after `noChange` with L ≠ R. Check
      the 16 MiB bound before sending.
    - **`staleHead`:** start again from the returned head, up to a small
      fixed number of attempts per check.
- **Outcome per Skill:** a sealed value that M7 turns into Sync Status.
  - Synced.
  - Waiting to Upload: the network or the service is unavailable.
  - Needs Attention, with these Attention Reasons:
    - incoming change waits behind a Draft;
    - Sync Merge conflict, carrying `head.device.name` for attribution;
    - removed on another Device while a Draft exists here;
    - too large to sync.
  - Account conditions are separate.
- **Upstream on Divergence:** `merged` returns only the new Effective. Read the
  Upstream to advance with through `inspectRevisionSelections`. The client never
  picks one itself.
- **No queue:** what to do is always derived from Workspace state, Lineage
  state, and `SyncStateStore`. Losing any response must be safe.

### Acceptance

Each item is a test with T22's fake service and the fake Workspace.

- **Fast-forward:** Device B applies A's new head, and its outcome is Synced.
- **Local ahead:** a local publish is Uploaded and advanced, and the outcome is
  Synced.
- **Divergence, clean:** both Devices publish offline; A advances first. B gets
  `staleHead`, Sync Merges, Uploads, and advances. A then fast-forwards to the
  merge.
- **Divergence, conflicting:** B's outcome is Needs Attention, Sync Merge
  conflict, attributed to A's Device name. Nothing is uploaded.
- **Draft:** an incoming change for a Skill with a Dirty Draft gives "waits
  behind a Draft". Other Skills still sync in the same check.
- **Lost responses:** the fake commits, then drops the response, for:
  - Lineage create: repeated with the same `clientKey`;
  - upload;
  - Head Advance;
  - removal.

  In each case, the next check ends Synced (or removed), with no duplicate
  Lineage and no extra head.
- **Removal both ways:**
  - a local Removal sends Synced Removal;
  - a remote removal removes the Skill here;
  - with a Draft, it gives "removed on another Device while a Draft exists
    here".
- **Stop Syncing both ways:** both Devices keep the Skill, unlinked.
- **Too large:** an export over 16 MiB and a `packTooLarge` answer each give
  "too large to sync", with nothing advanced.
- **Unavailable:** a 503 or a connection failure gives Waiting to Upload, and a
  later check completes the Upload.
- **Feed:**
  - entries with a version already reconciled cause no download;
  - unknown kinds are skipped;
  - `Retry-After` reaches `FeedCheckResult`.
- **`PortableSource`:** the encoding round-trips. A Device-Bound Source carries
  no path; a test builds one with a path-like label and checks the encoding.
- **CONTEXT.md:** the Attention Reason table gains "Too large to sync",
  decided on 2026-11-27, with its actions.
- **Gates:** T16's gates, each with its own exit code; line coverage of the new
  files reported.

### Scope fence

- **In scope:** `packages/skills_cloud/`, and its `CONTEXT.md`.
- **Out of scope:**
  - **Generation change, in either direction:** T25 adds the Workspace
    variant, and T26 the client side.
  - New-Device bootstrap, reset, Device Exclusions, and linking a local Skill
    to an existing Lineage (T24).
  - Metadata and tags (v0.2, M6).
  - The App, Sync Status UI, and durable state (M7).
  - Changing `skills_workspace`.
- **Expected size:** about 15–25 files, 2,000–3,000 lines including tests.

### Stop and ask if

- A case needs the client to decide ancestry or parse a commit ID.
- A Workspace result needed here is missing from the M5 contract.
- An outcome has no Attention Reason in R10, and is not resolved by retrying.
- The Upstream that the Workspace selects after a merge breaks contract v0.1's
  Head Advance rule 5.

## Maintained by Codex

### Progress

- [x] Add Workspace/state ports, PortableSource and typed per-Skill outcomes.
- [x] Reconcile linked Skills and propagate upload, removal and Stop Syncing.
- [x] Recover lost create/upload/advance/removal responses by reading state.
- [x] Test clean divergence, conflicting divergence, Drafts and size limits.

### Decision Log

- Workspace methods mirror the existing operations; a stateless slotKeyForName port delegates to the Workspace's existing public derivation. This prevents a second production Slot Key algorithm.
- SyncStateStore is scoped to one account/device. It retains mappings, observed versions, pending create keys and cursors, never an outbox. M7 must switch stores with accounts.
- A check makes at most three reconciliation attempts. Unsettled feed/local pages keep their old cursor so the next check revisits them; settled versions skip repeat application.
- Upstream after a merge is always read back from the Workspace. Protocol/Workspace-contract defects fail explicitly with stable StateError codes rather than appearing as a perpetually retrying Sync Status.
- Added Too large to sync to CONTEXT with the accepted actions.

### Surprises

None.

### Follow-ups

The real SkillsRepository adapter, durable state and status presentation are M7.

### Outcome

Fake two-Device scenarios pass. Final gates and coverage: ../validation/m4-client-workspace-2026-11-27.md.
