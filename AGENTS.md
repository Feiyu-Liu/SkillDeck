# Repository Guidelines

## Project Structure & Module Organization

`CONTEXT-MAP.md` identifies bounded contexts and `CONTEXT.md` defines Skill Workspace vocabulary. Private architecture documents, ADRs, and agent guides are excluded from this snapshot; remaining ADR identifiers are historical references. Ask the maintainer for clarification before changing domain behavior. The monorepo contains `packages/skills_workspace/`, `packages/skills_translation/`, and the desktop app in `skilldeck-app/`. Keep package production code in `lib/src/`, public exports in each package's top-level library file, and tests in `test/`. Treat the sibling `../skills/` checkout as a read-only CLI reference.

## Build, Test, and Development Commands

Run these from the package or App being changed. Skill Workspace backend work
belongs in `packages/skills_workspace/`; Flutter composition and presentation
work belongs in `skilldeck-app/`:

- `dart format --output=none --set-exit-if-changed .` checks formatting.
- `dart analyze --fatal-infos` runs strict static analysis.
- `dart test` runs the complete test suite.
- `dart test --coverage=coverage` produces coverage input for the 85% line-coverage gate.

## Coding Style & Naming Conventions

Use Dart's standard two-space indentation and formatter. Name files `snake_case.dart`, types `UpperCamelCase`, and members `lowerCamelCase`. Keep the normal public surface behind `SkillsRepository`; prefer immutable models, typed results, and stable error codes. Do not execute Skill content or leak credentials, environment variables, raw process output, or URL userinfo into logs.

## Testing Guidelines

Name tests `*_test.dart`, place fixtures in `test/fixtures/`, and fakes in `test/support/`. Cover each transaction step and every pre/post-mutation failure boundary explicitly. Platform behavior must eventually pass on macOS, Windows, and Linux; a macOS-only result is not release evidence.

## Commit & Pull Request Guidelines

Use concise Conventional Commits such as `feat(core): add repository locking`. Keep package and app changes independently scoped unless one contract change requires an atomic cross-component commit. Pull requests should describe behavior and recovery implications, link the relevant issue when available, list verification commands, and call out architecture changes. Include screenshots only for UI changes.

## Agent skills

### Issue tracking and triage

Private issue notes and triage guides are not included. Contribution setup is
pending as described in `CONTRIBUTING.md`; confirm the process with the maintainer.

### Domain context

This is a multi-context monorepo rooted at `CONTEXT-MAP.md`; Skill Workspace uses
`CONTEXT.md`, while independent contexts may own package-level context files.

### SkillDeck Cloud tripwires

SkillDeck Cloud (Personal Sync, Teams, and the Marketplace) is accepted and built in phases (M6; ADR-0105, ADR-0106, ADR-0107). Watch for these in review; each one, if merged, forces a later refactor or breaks a boundary:

- Git-specific assumptions leaking into the app's install/activate UI or the engine's non-source layers (the install flow must stay source-agnostic).
- Losing source provenance — flattening a `SourceDescriptor` to a bare path.
- Entangling the well-known byte fetch/verify/extract with well-known index parsing.
- Branching update detection on source type instead of content hash (ADR-0030).
- Credentials or auth tokens entering the engine, SQLite control plane, revision Store, or operation records (ADR-0013 delegates auth outward).
- Cloud concerns (accounts, sessions, catalog, ratings, signing, sync conflict policy) added to `skills_workspace` or `skills_translation` instead of `skills_cloud`. The engine gains only the seams in ADR-0105 decision 9.
- Cloud tokens persisted anywhere outside platform secure storage, or placed in URLs, Revision Store configuration, SQLite, Operation Records, or logs (ADR-0106, ADR-0107).
- Remote state changing an Effective Revision or Activations without a local Workspace transaction (ADR-0105 decision 6).
- Polling Git for change discovery or update checks (ADR-0107).

Build cloud code only for the active phase (ADR-0105 decision 12); do not pre-build later phases.
