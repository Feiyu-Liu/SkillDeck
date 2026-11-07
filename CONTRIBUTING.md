# Contributing to SkillDeck

Thank you for your interest. This file states the terms under which
contributions are accepted; the engineering gates live in `AGENTS.md` and
`CLAUDE.md`.

## License and contributor agreement

All first-party code in this repository is licensed under GPL-3.0-or-later
(`LICENSE`). By submitting a contribution you agree that:

1. your contribution is licensed under GPL-3.0-or-later;
2. you have the right to submit it, including any employer permission you
   need;
3. you sign the SkillDeck Contributor License Agreement in `CLA.md`, which
   additionally lets the copyright holder distribute your contribution under
   other terms, for example through app stores whose terms conflict with the
   GPL or under a commercial license, while committing to keep it available
   under a free software license.

This is a local publication candidate, not yet an open contribution endpoint.
CLA automation and its signature store are not configured in this snapshot.
Before accepting outside pull requests, the maintainer must configure the
signing workflow for the new repository. Pull requests from unsigned authors
must not be merged. If you contribute on behalf of a company, see section 5
of `CLA.md`.

Third-party code you bring in keeps its own license and must be listed in the
notices with its copyright and license text; copyleft code that is not
GPL-3.0-compatible is not accepted.

## Before you open a pull request

- Read `CONTEXT-MAP.md`, then the owning context's `CONTEXT.md`, before
  changing domain behavior. Private architecture documents and ADRs are not
  included in this snapshot; ask the maintainer to clarify requirements and
  agree on behavior changes rather than silently diverging.
- Run the package's gates listed in `CLAUDE.md`: format, strict analysis,
  tests, and the 85% line-coverage check for `skills_workspace`. Regenerate
  and commit generated code when you touch the Drift schema or native
  headers; never hand-edit generated files.
- Keep the invariants in `AGENTS.md`: never execute Skill content; never log
  credentials, environment variables, raw process output, or URL userinfo;
  preserve the Workspace transaction and recovery semantics.
- Use Conventional Commits with a scope, for example
  `fix(workspace): preserve lease on cancelled install`, and keep each pull
  request to one logical change.

## Reporting a security issue

Do not open a public issue for a vulnerability. Contact the maintainer
privately; the address is published together with the repository.

## Trademark

The SkillDeck name and logo are not part of the license grant; see
`TRADEMARK.md`.
