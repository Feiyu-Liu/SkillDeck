# ExecPlan: T29 App: the real SyncWorkspace adapter and durable sync state

Milestone M7, part 1. It does not depend on M6, so it can start now. After T27.
Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

The App can build a `Reconciler` over the real Workspace. Its sync state
survives a restart, is kept per account, and holds no credentials.

### Context

- **Read first:**
  - root `CLAUDE.md`, the skilldeck-app architecture: the
    `SkillsWorkspaceRepository` seam, its decorators, and `SkillsManagerRuntime`;
  - `packages/skills_cloud/lib/src/sync/`: `SyncWorkspace`, `SyncStateStore`,
    `PortableSource`, and the fake in `lib/src/testing/`;
  - `../m5-sync-apply-contract.md`;
  - `../reviews/2026-11-27-m4-review.md`, items M4-6 and M4-7.
- **The adapter goes through the App's seam,** not around it. Extend
  `SkillsWorkspaceRepository` with what `SyncWorkspace` needs:
  - `inspectRevisionSelections`;
  - `inspectCommittedChanges`;
  - `exportRevisionPack`;
  - `applyRemoteState` with its variants;
  - the Source Descriptor and Declared Skill Name read;
  - the Slot Key derivation.

  Implement them in `PackageSkillsWorkspaceRepository` and both decorators, so
  that the diagnostics and the ownership gate apply to sync writes too.
- **The App maps `ManagedSkillId` to `WorkspaceSkillId`.** The adapter speaks
  `skills_cloud`'s string IDs. Keep one mapping, at the adapter.

### Contract

- **Dependency:** the App gains a path dependency on `packages/skills_cloud`.
  Update its lockfile; record the command.
- **`WorkspaceSyncAdapter`**, in `lib/features/cloud/data/`, implements
  `SyncWorkspace`:
  - **Source mapping:** each Source Descriptor maps to `PortableSource`, and
    each `PortableSource` maps to a Source Descriptor for Install and Source
    Replacement:
    - Git and Well-known keep their portable fields;
    - Local and Adopted Snapshot map to Device-Bound, with this Device's label
      and a display label, never a path;
    - a Synced Origin Source maps back to exactly the Device-Bound
      `PortableSource` it was installed from (M4-6);
    - a Device-Bound `PortableSource` maps to a Synced Origin Source (T03).
  - **Results:** every Workspace result and error code maps to the port's
    result type. Unknown codes map to `operationFailed`, never to success.
- **`FileSyncStateStore`** implements `SyncStateStore`:
  - one JSON file per account and Device, under the App support directory,
    in a `cloud/` folder;
  - the folder name is a hash of the origin and account ID, never the raw
    account ID or email;
  - writes go to a temporary file in the same folder, are flushed, then
    renamed;
  - a corrupt or unreadable file is moved aside and treated as empty, with a
    typed diagnostic. Sync then bootstraps again, which never re-uploads (R6);
  - it stores no token, URL, email, or `source` contents beyond what
    `SyncLink` already holds.
- **No UI** in this card.

### Acceptance

- **Adapter, through a real Workspace in a temporary directory:**
  - each Source type maps both ways, per the rules above;
  - **M4-6:** install a Device-Bound Lineage through the adapter, read it
    back, and compare with the Lineage's `source`: they are equal;
  - each port operation is called once through the decorator chain. A test
    shows that the ownership gate's refusal reaches the Reconciler as a typed
    failure.
- **Reconciler end to end:** two real Workspaces (two temporary directories)
  and `FakeCloudService` from `package:skills_cloud/testing.dart`:
  - publish on A, check on B, and B has the revision;
  - a Draft on B blocks, and resolving it lets the next check apply;
  - a Source Replacement on A reaches B.

  The fake cannot verify real packs. If needed, add a test-only option to the
  fake that accepts packs without parsing them; record it in the Decision Log.
- **State store:** restart (new instance over the same file) keeps every
  field; two accounts use separate files; a truncated file recovers as empty
  with the diagnostic; a search of the file finds no token or email.
- **M4-7, opt-in:** an integration test that drives `CloudApi` with real packs
  from the adapter against a service origin given by an environment variable.
  It is skipped without the variable. Run it once against `wrangler dev` or
  staging if the maintainer provides a test session, and record the result.
- **Gates:** the App gates from `CLAUDE.md`, and the `skills_cloud` gates, each
  with its own exit code.

### Scope fence

- **In scope:** `skilldeck-app/lib/features/cloud/data/`, the
  `SkillsWorkspaceRepository` seam and its implementations, the App's
  `pubspec.yaml` and lock, and their tests.
- **Out of scope:**
  - UI, Riverpod wiring of the sync runtime, and sign-in (T30, T31);
  - changes to `skills_workspace` or `skills_cloud` behaviour, apart from
    the test-only fake option above.

### Stop and ask if

- The ownership gate or the diagnostic decorator cannot pass a sync write
  without a new rule.
- A Source Descriptor cannot be mapped back exactly (M4-6).
- The App's `ManagedSkillId` mapping hides an ID that the Reconciler needs to
  persist.

## Maintained by Codex

### Progress

### Decision Log

### Surprises

### Follow-ups

### Outcome
