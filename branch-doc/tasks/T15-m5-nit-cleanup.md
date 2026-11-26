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

- [x] Moved shared color validation out of the exported model.
- [x] Removed `inspectDirty` and migrated its byte-comparison regression.
- [x] Added public unknown/removed Skill metadata rejection tests.
- [x] Added direct-engine and worker non-fallback failure tests.
- [x] Run the full T01 gates and record each exit code.

### Decision Log

- Shared color validation lives in an unexported domain file, used by the model and requests. The rule and ArgumentError are unchanged.
- Migrated the same-hash/different-bytes case to `inspectForCleanup`, also checking the absent dirty cleanup fingerprint and staging discard. No existing cleanup test covered this case.
- Both bundle paths use existing constructor injection and small test-local fakes. Each non-objectUnavailable code must escape after exactly one history build.

### Surprises

- Initial lockfile resolution used a configured mirror and exited 65. Retrying with `PUB_HOSTED_URL=https://pub.dev`, matching the lockfile, exited 0 without lockfile changes.

- The initial single-process full suite exited 255 after the disk filled (errno 28). Removed only that run's abandoned kernel directory, then ran all 191 test files in ten batches of at most 20, preserving `-j 1`. This bounds temporary compiler storage. Coverage uses the same batches and one fresh output directory.

- Coverage batch 9 exited 1 with two 30-second timeouts, in Workspace file-lock contention and Git-path independence tests. Its log also shows multi-minute scheduling gaps. Both files passed a separate coverage retry with the original timeout (exit 0, four tests in 13 seconds). No production or test timeout changes were made.

### Follow-ups

- Windows and Linux gates have not been run for this card.

### Outcome

Implemented on macOS arm64 with Dart 3.14.0. Seven package files changed,
including two new files. Public color validation is removed, Draft inspection
uses the existing cleanup path, and both missing-Skill cases and both bundle
failure paths are covered. No native, schema, dependency, or runtime behavior
change. `inspectDirty` has no remaining code or test references, and the
internal color helper is not exported.

| Command / run | Exit code | Result |
| --- | --- | --- |
| `dart pub get --enforce-lockfile` | 65 | Configured mirror disagreed with lockfile |
| `PUB_HOSTED_URL=https://pub.dev dart pub get --enforce-lockfile` | 0 | Lockfile preserved |
| `dart format --output=none --set-exit-if-changed .` | 0 | Passed |
| `dart analyze --fatal-infos` | 0 | No issues |
| Focused `dart test -j 1` on the three changed test files | 0 | 30 passed |
| Initial `dart test -j 1` | 255 | Disk exhausted, not a passing run |
| Full suite, `dart test -j 1` with explicit batches of 20 sorted test files | Each batch 1–10 exited 0 | 1,676 passed, one network suite skipped by default |
| Coverage, same file batches with `--coverage=/tmp/t15-run/coverage` | Batches 1–8 and 10 each exited 0; batch 9 exited 1 | Two timeouts in batch 9 |
| Coverage retry of both timed-out files | 0 | Four tests passed with original timeout |
| `dart test -j 1 integration_test` | 0 | Two passed |
| `dart run coverage:format_coverage --lcov --in=/tmp/t15-run/coverage --out=/tmp/t15-run/lcov.raw.info --package=. --report-on=lib` | 0 | Combined fresh batch coverage |
| `dart run tool/filter_coverage.dart /tmp/t15-run/lcov.raw.info /tmp/t15-run/lcov.info` | 0 | 225 retained records, two generated records excluded |
| `dart run tool/check_coverage.dart /tmp/t15-run/lcov.info 85` | 0 | 89.25%, 21,012 / 23,544 lines |
| `git diff --check` | 0 | Passed |

Raw gate logs and per-command statuses are in `/tmp/t15-run/`; focused output
is `/tmp/t15-focused.log`. Regeneration was not required because neither
native headers nor database definitions changed. Windows and Linux were not
validated in this run.
