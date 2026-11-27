# M4 client and Workspace validation — 2026-11-27

## Result and scope

Implemented T22–T26 on `claude/amazing-keller-unt4dd`, based on `1d97987`.
T19 was already present. The corresponding T18/T20/T21 implementation and
service/native qualification are in the private service repository.

The approved contract additions are recorded in cloud-api-contract-v0.1.md:
24-hour unadvanced-Lineage cleanup releases the creation key; malformed
cursors return 400, while parseable unusable cursors return 410/reset.

No App UI, real SkillsRepository-to-Reconciler adapter, durable client sync
state, deployment, commit or push was included. Existing unrelated App locks,
.gitignore, CLAUDE.md and local qualification artifacts were preserved.

## Commands and outcomes

macOS arm64, Dart 3.14.0. Commands ran from the package named below; each exited 0.

| Package | Command | Result |
| --- | --- | --- |
| skills_cloud | `PUB_HOSTED_URL=https://pub.dev dart pub get --enforce-lockfile` | Locked dependencies; only the approved crypto 3.0.7 dependency changed |
| skills_cloud | `dart format --output=none --set-exit-if-changed .` | Clean |
| skills_cloud | `dart analyze --fatal-infos` | No issues |
| skills_cloud | `dart test --coverage=coverage` | 76 passed |
| skills_cloud | `dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --package=. --report-on=lib` | LCOV generated |
| skills_workspace | `PUB_HOSTED_URL=https://pub.dev dart pub get --enforce-lockfile` | Lockfile unchanged |
| skills_workspace | `dart format --output=none --set-exit-if-changed .` | Clean |
| skills_workspace | `dart analyze --fatal-infos` | No issues |
| skills_workspace | `dart test -j 1 --coverage=coverage` | 1,682 passed; one existing opt-in network test skipped |
| skills_workspace | `dart test -j 1 integration_test` | 2 passed |
| skills_workspace | T25 focused suite with coverage | 6 passed, including the added real Update Candidate Session guard assertion |
| skills_workspace | Four-step coverage pipeline from CLAUDE.md | 89.28% (21,134/23,671), above 85% |
| skills_workspace | `dart run tool/regenerate.dart` | No generated-code or schema changes |
| repository | `git diff --check` | Clean |

The Workspace full test command also collects coverage, so it covers the
required `dart test -j 1` gate. The final T25 focused run additionally checks
the real open-session blocker and both process-crash boundaries. Regeneration
was compared against pre-run file hashes and Git's generated-file diff.

## New client-file line coverage

Total new files: **1160/1298 (89.37%)**. The testing-library fakes are included and listed separately below.

| File | Covered/total | Coverage |
| --- | ---: | ---: |
| `src/api/cloud_api.dart` | 183/200 | 91.50% |
| `src/api/cloud_result.dart` | 17/17 | 100.00% |
| `src/api/cloud_values.dart` | 86/89 | 96.63% |
| `src/sync/portable_source.dart` | 55/60 | 91.67% |
| `src/sync/sync_workspace.dart` | 15/17 | 88.24% |
| `src/sync/sync_state_store.dart` | 16/20 | 80.00% |
| `src/sync/sync_outcome.dart` | 6/7 | 85.71% |
| `src/sync/reconciler.dart` | 308/364 | 84.62% |
| `src/testing/fake_cloud_service.dart` | 256/294 | 87.07% |
| `src/testing/fake_pack.dart` | 45/45 | 100.00% |
| `src/testing/fake_sync_workspace.dart` | 173/185 | 93.51% |

## Behavioral evidence

- API methods use the injected package:http Client, retain credentials only
  in origin-bound Authorization headers, reject unexpected endpoint errors,
  and keep server text out of result objects. File uploads preserve chunked
  consumption; refusal before request consumption cannot strand a producer.
- Fake conformance covers ordered Head Advance rules, both ends, generation
  repeat rules, creation keys, account isolation, compacted Feed and cursor
  reset. Fake packs are test-only JSON, not a replacement Git implementation.
- Two-Device tests cover fast-forward, local-ahead upload, clean merge,
  attributed conflicts, Draft blockers, lost write responses and size limits.
- Bootstrap installs with no Activations, links only exact portable-source/
  Workspace-derived-slot/content matches, and recovers lost reads without a
  duplicate install. Exclusion removal forces a re-list without needing a
  new server version. Missing-after-reset copies are never auto-uploaded.
- Concurrent Source Replacements leave one winning Generation; the losing
  Device keeps its unpublished-to-Cloud history until an explicit action.
  Lost successful Generation responses do not create a third Generation.
- Real Workspace replacement preserves ID, Activations, Favorite, Note and
  tags, relocates free slots and rejects occupied ones, and exports only the
  replacement history. Constructor mismatches throw before starting a request.
- The real Store crash harness proves rollback before the Business Commit
  Point and roll-forward after it. No new journal phase, schema or native code
  was added. Generic coordinator/control-plane layers still contain no
  WorkspaceOperationKind references.

## Limits

These are local backend/package results, not App UI or release acceptance.
No running DTD/debug application was available for hot reload; no GUI was
started or modified. Windows and Linux release verification remain separate.
The next App phase owns the real Workspace adapter, secure session storage,
durable per-account/device state, serialized scheduling and user prompts.
