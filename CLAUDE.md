# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`SkillsFlutter` is a Dart and Flutter monorepo for the local Agent Skill
Workspace. The shipped desktop product is named **SkillDeck**; `skills_manager`
is its package name. Current production components are:

| Path | Responsibility |
| --- | --- |
| `packages/skills_workspace/` | Transactional Skill Workspace backend and sole authority for managed Skill lifecycle, revision history, activation, recovery, and Library metadata. Pure Dart plus a native FFI layer. |
| `packages/skills_translation/` | Independent Markdown translation context and disposable content-addressed cache. Flutter package, held to a lower minimum SDK than the rest of the repo. |
| `packages/skilldeck_cli/` | The `skilldeck` CLI and the Local Command Host protocol (NDJSON). A thin client that never opens the Workspace; it drives the running App (ADR-0111). Pure Dart. |
| `skills_manager/` | Flutter desktop App that composes Workspace and Translation through App-owned repository seams and Riverpod. |
| `landing_page/` | Marketing site: Vite + React + Tailwind, prerendered and deployed to Cloudflare Pages (`npm run lint`, `npm test`, `npm run pages:deploy`). |
| `release/`, `tool/release.py` | Desktop release orchestration (sign, notarize, publish updater feeds). See `release/README.md`. |

Read `CONTEXT-MAP.md`, then the owning context's `CONTEXT.md`, before changing
domain behavior. The entire private `docs/` directory is excluded from this
snapshot and its Git history; ADR identifiers below are historical references,
not available documents. Ask the maintainer to clarify architectural requirements.
The sibling `../skills/` TypeScript CLI is a read-only
compatibility reference; this repository never delegates its runtime to it.

## Toolchain

Development and release evidence use **Dart 3.13.4 and Flutter 3.47.5**, and all
lockfiles are release input because generated Drift, ffigen, Native Assets,
SQLite, and native-link output are version sensitive. Resolve with
`--enforce-lockfile`.

`skills_translation` is the exception: it must also build, analyze, and test on
**Flutter 3.29.3**, which CI enforces as a separate job. Do not use APIs newer
than that in this package or its `example/`.

Building `skills_workspace` compiles pinned libgit2 through a Native Assets
hook, so the host needs `clang`, `cmake`, `ninja`, and `pkg-config`. The `-j 1`
in every test command is deliberate — native compilation and parallel test
workers otherwise compete for memory.

## Commands

Workspace gates, from `packages/skills_workspace/` (pure Dart — use `dart`, not
`flutter`):

```bash
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test -j 1                                    # unit + child-process suite
dart test -j 1 integration_test                   # native integration suite
dart test -j 1 test/application/install/foo_test.dart          # single file
dart test -j 1 --name 'rolls back on write failure'            # single test
```

Coverage is a four-step pipeline, not a single flag; the gate is 85% lines:

```bash
dart test -j 1 --coverage=coverage
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.raw.info --package=. --report-on=lib
dart run tool/filter_coverage.dart coverage/lcov.raw.info coverage/lcov.info
dart run tool/check_coverage.dart coverage/lcov.info 85
```

CLI gates, from `packages/skilldeck_cli/` (pure Dart, no native build):

```bash
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

Translation gates, from `packages/skills_translation/` (Flutter package — `dart
test` will not work):

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
flutter test test/translation_protocol_test.dart               # single file
```

App gates, from `skills_manager/`:

```bash
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos --no-pub
flutter test --no-pub
flutter test --no-pub test/features/skills/foo_test.dart       # single file
flutter test --no-pub -d macos integration_test/skills_manager_desktop_e2e_test.dart
```

Use `windows` or `linux` on those hosts; headless Linux desktop tests require
`xvfb-run`. Linux is a supported `skills_workspace` platform but is **not** a
SkillDeck App release target.

Run the App with a define file — self-update stays offline when no feed URL is
supplied:

```bash
flutter run -d macos --dart-define-from-file=debug.json
flutter build macos --release --dart-define-from-file=staging.json
```

`skills_manager/pubspec_overrides.yaml` is gitignored and machine-local (it
path-overrides `my_ui`); never commit it or rely on it in CI reasoning.

## Generated code

`dart run tool/regenerate.dart` (from `packages/skills_workspace/`) runs four
generators in order: `build_runner build`, `drift_dev schema dump`, `drift_dev
schema generate`, and `ffigen`. Generated files are **committed and must never
be hand-edited**, and CI fails the build unless `git diff --exit-code` plus
`git status --porcelain --untracked-files=all` are both clean afterwards. So
regenerate and commit whenever you touch the Drift database definition or the
native headers.

`.gitignore` excludes `*.g.dart` repo-wide with one deliberate exception,
`workspace_database.g.dart` — do not "fix" that by ignoring it.

App user-facing strings live in `skills_manager/lib/l10n/app_en.arb` and
`app_zh.arb` and generate into `lib/l10n/generated/`; both locales must stay in
sync.

## CI tiers

- Pull requests run Linux quick gates: generated-code cleanliness, strict
  analysis, complete unit tests, and focused package integration where defined.
- Pushes to `main` run active-platform merge gates on macOS arm64, Windows x64,
  and Linux x64, including desktop E2E but excluding Release packaging.
- Version tags and manually dispatched `release` tiers add clean Release builds,
  native-artifact inspection, ABI, signing, size, ASAN/UBSAN, and evidence upload.
- macOS x64 remains an explicit deferred release gate until its runner is
  restored. Never present active-platform evidence as macOS x64 evidence.

Workflows are path-filtered per component, so a change confined to one package
only triggers that package's workflow. Use manual release verification for an
exact feature-branch SHA when a delivery plan requires release evidence before
merge:

```bash
gh workflow run skills-workspace-ci.yml --ref <branch-or-tag> -f tier=release
gh workflow run skills-manager-ci.yml --ref <branch-or-tag> -f tier=release
```

## Architecture

### skills_workspace

`packages/skills_workspace/lib/skills_workspace.dart` is the public package
entry point. Do not import `lib/src/` from the App. The package follows an
inward-facing layered architecture under `lib/src/`:

- `api/` and public domain models define `SkillsRepository`, requests, typed
  terminal outcomes, cancellation, configuration, and stable identifiers.
- `application/` coordinates use cases, one directory per capability: install,
  update, source, drafts, history, activation, library, agents, project_roots,
  revision_store, destructive, discovery, backup, operations, runtime, ports.
- `domain/` owns immutable rules and vocabulary without infrastructure types.
- `infrastructure/` implements the SQLite control plane (`database/`), source
  acquisition, activation materialization, discovery, git transport, and
  operation records.
- `platform/` isolates OS-specific filesystem, activation, and operation
  behavior — the seam where Windows/macOS/Linux differences belong.
- `native/` owns the pinned libgit2 Native Asset, generated FFI bindings, the
  internal Git-backed revision engine/worker, and the HTTPS Source transport.
  Internal revision history never uses system Git; only SSH and local Git
  Sources and the fallback path do.
- `composition/` wires command handlers into the production facade and owns
  runtime resource assembly.

SQLite is authoritative for relational control-plane state and user Library
metadata. Immutable revision bytes and ancestry live in isolated internal Git
Stores. Agent-visible Activations are rebuildable filesystem projections. The
App accesses effective files through public lease-safe content APIs, never by
inferring private Workspace paths or reading SQLite directly.

### skills_manager

Feature-first under `lib/features/<feature>/{data,models,presentation}`, with
cross-cutting concerns in `lib/shared/` and composition in `lib/app/`. Views
call Riverpod ViewModels (`presentation/view_models/`); ViewModels call App
repositories rather than performing direct platform I/O.

The anti-corruption seam is `SkillsWorkspaceRepository`
(`features/skills/data/repositories/`), implemented by
`PackageSkillsWorkspaceRepository` and wrapped by decorators —
`DiagnosticSkillsWorkspaceRepository` for observability, then
`OwnershipGatedSkillsWorkspaceRepository` at the provider override in
`main.dart`. Package identifiers are mapped to opaque App `WorkspaceSkillId`
values at this boundary.

`SkillsManagerRuntime` (`features/settings/data/skills_manager_runtime.dart`) is
the single process-lifetime owner of the Workspace facade; it reconfigures the
agent catalog in place rather than replacing the repository, so active readers
keep their subscriptions. All reads flow through one root-scoped Snapshot
pipeline in `features/skills/workspace_snapshot_providers.dart`.

### skilldeck CLI and the Command Host

The App holds the Workspace's process-lifetime ownership lock (ADR-0093/0094),
so a second process can never open it. `skilldeck` therefore only discovers the
running App (launching it if needed), sends a command over the local protocol in
`skilldeck_cli/lib/src/protocol/`, and renders the typed result. The App side
lives in `skills_manager/lib/features/command_host/` and executes every command
through the same `SkillsWorkspaceRepository` decorator chain as the GUI.
Destructive CLI requests are approved in the App, never by a flag an Agent can
pass. The App depends on `skilldeck_cli` for the shared protocol types
(`skilldeck_protocol.dart`).

## Invariants

- Never execute Skill content.
- Never leak credentials, environment variables, raw process output, or URL
  userinfo into logs or durable Workspace state.
- Mutations must preserve the Workspace lock, operation-record, SQLite, revision
  Store, filesystem transaction, recovery, and committed-finalization semantics
  of the existing implementation and its tests.
- Expected failures use typed outcomes and stable error codes rather than
  exceptions.
- Managed identity is `ManagedSkillId` in the package and `WorkspaceSkillId` in
  the App. Slot Key is not managed identity.
- Translation remains outside Skill Workspace and never mutates Skill content.
- Keep Drift rows, SQLite handles, Git object IDs, Store generations, FFI
  bindings, and private paths out of public API.

SkillDeck Cloud (Personal Sync, Teams, and the Marketplace) is accepted and
built in phases (M6; ADR-0105, ADR-0106, ADR-0107). It runs on Cloudflare:
Artifacts for Git, Workers for the API, D1, Durable Objects, and Better Auth.
Its client context is `skills_cloud`.

Keep these rules:
- keep install source-agnostic;
- preserve `SourceDescriptor` provenance instead of flattening it to a path;
- branch update detection on content hash rather than source type (ADR-0030);
- keep cloud tokens out of the engine, SQLite, the revision Store, operation
  records, URLs, and logs;
- apply remote state only through local Workspace transactions;
- build only the active phase.

Public HTTPS Git Sources fetch through the networked embedded `libgit2`
(ADR-0106). System Git serves SSH and local locators and is the fallback. See
`AGENTS.md` for the full tripwire list.

## Repository conventions

- Dart formatting and strict analysis are mandatory.
- Production code lives under `lib/src/`; expose only reviewed public contracts
  through top-level library files.
- Tests mirror production paths, fixtures live in `test/fixtures/`, and fakes
  live in `test/support/`.
- Cover transaction boundaries, rollback, recovery, stale-state handling,
  cancellation, and platform-specific filesystem behavior explicitly.
- Preserve unrelated dirty-worktree changes and stage logical commits by
  explicit path.
- Use concise Conventional Commits such as `feat(workspace): add revision read`.
- Private issue notes are excluded; see `CONTRIBUTING.md` for contribution status.

Before changing accepted behavior, agree on the requirements with the maintainer.
Private ADRs are not included; do not silently diverge from existing contracts.
