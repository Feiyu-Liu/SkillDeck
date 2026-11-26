# ExecPlan: T15 Cleanup of the T09 and T14 Nits

Milestone M5 follow-up. Fixes items T09-1, T09-2, T09-3, and T14-1 of
`../reviews/2026-11-24-m5-review.md`. Item T09-4 (size) was accepted and needs
no change. Simplicity rules: see `../execplan-template.md`.

## Set by the planner

### Goal

M5 leaves no stray public surface or dead code, and two behaviours that the
code already has gain a test: an unknown Skill in `RemoteSkillMetadata`, and a
Recovery Bundle build failure that must not fall back.

### Context

- **T09-1:** T09 added `PersonalTag.validateColor` as a public static method in
  `lib/src/domain/public_models.dart`. That file is exported whole from
  `lib/skills_workspace.dart`, so the method is public API. The contract does
  not list it. It is called from `PersonalTag`'s constructor and from
  `RemoteTagEnsure` and `RemoteTagUpdate` in `lib/src/api/requests.dart`.
  Nothing outside the package uses it. It has not been released.
- **T09-2:** `DraftSnapshotCoordinator.inspectDirty` in
  `lib/src/application/drafts/draft_snapshot_coordinator.dart` is now used only
  by its own test in `test/application/drafts/draft_snapshot_coordinator_test.dart`.
  `inspectForCleanup` does the same scan and comparison and also returns the
  clean fingerprint.
- **T09-3:** for an unknown or removed Skill, `RemoteSkillMetadata` returns
  `skillNotFound`, but no public test sends it. Public remote Library tests are
  in `test/api/remote_library_apply_e2e_test.dart`.
- **T14-1:** `RevisionRecoveryBundlePublisher.publish` in
  `lib/src/composition/revision_recovery_bundle_publisher.dart` retries
  roots-only only on `RevisionEngineFailureCode.objectUnavailable` and rethrows
  every other code. No test shows the rethrow.

### Contract

No behaviour change. The only public change is a removal:

- `PersonalTag.validateColor` is no longer reachable from
  `package:skills_workspace/skills_workspace.dart`.
- `PersonalTag`, `RemoteTagVocabulary.ensure`, and `RemoteTagVocabulary.update`
  reject the same colors as today, with the same `ArgumentError`.

Where the shared check lives is your call. It must not be exported.

### Acceptance

- **T09-1:**
  - a search of the exported libraries finds no `validateColor`;
  - the existing color validation tests pass unchanged. If none of them covers
    a bad color for each of the three constructors, add the missing cases.
- **T09-2:**
  - `inspectDirty` and its test are gone;
  - if that test checked something no `inspectForCleanup` test checks, the case
    moves to an `inspectForCleanup` test. Say so in the Decision Log.
- **T09-3:** one public test each for `RemoteSkillMetadata` with:
  - a Skill ID that the Workspace never had;
  - a Skill that a Synced Removal removed.

  Each returns `skillNotFound`. The operation history, the committed-change
  feed, and the Skill's tag assignments and note stay unchanged.
- **T14-1 (may use internal types and fakes):** when the history build fails
  with a code other than `objectUnavailable`:
  - `publish` fails with that same code;
  - the publisher makes exactly one build attempt.

  Cover the direct engine path. Cover the worker path too if a fake for it is
  cheap; otherwise say why in the Decision Log.
- All existing tests pass unchanged, except the removed `inspectDirty` test.
- **Gates:** the T01 gates. Native code and the schema must not change. Report
  each command's own exit code.

### Scope fence

- **In scope:** `packages/skills_workspace/`.
- **Out of scope:**
  - any change to how remote apply, tags, Drafts, or Recovery Bundles behave;
  - other cleanups found on the way. List them under Follow-ups;
  - the M3, M4, and M6 work;
  - the private ADR-0105 R5 amendment for tag colors.
- **Expected size:** about 4–7 files, 100–250 lines including tests.

### Stop and ask if

- Something outside `skills_workspace`, or an exported test helper, uses
  `validateColor` or `inspectDirty`.
- A T09-3 test finds that the result is not `skillNotFound`, or that it writes
  an Operation Record or a feed entry.
- A fake for the T14-1 test needs a production change beyond a constructor
  parameter that already exists.

## Maintained by Codex

### Progress

### Decision Log

### Surprises

### Follow-ups

### Outcome
