# Context Map

This repository spans more than one bounded context. Each context owns its own
ubiquitous language; this map lists them and how they relate. Add a context here
only when it has real, modeled terms of its own.

## Contexts

- [Skill Workspace](./CONTEXT.md) — the local Workspace for durable Repository
  Copies, Activations, Skill Slots, Source Lineages, Draft and published revision
  history, Favorite, Note, Personal Tags, and the transactional lifecycle that
  installs, organizes, edits, publishes, activates, updates, adopts, and removes
  Skills. SQLite owns the relational control plane and Operation Records/Subjects;
  isolated Git Stores own immutable revision bytes and ancestry. The production
  implementation is `packages/skills_workspace/`. It supersedes the former Core
  and Library package split and is the App's sole Skill Workspace authority.
- [Translation](./packages/skills_translation/CONTEXT.md) — first-class,
  cross-platform translation of selected Markdown content in
  `packages/skills_translation/`. One selected `.md` document and Translation
  Scope form one Translation Job; a Provider may segment prose internally, but
  only a successful scoped Job produces a cacheable Completed Translation.
  OpenAI-compatible Chat Completions and
  Anthropic Messages are the cross-platform Provider baseline. Translation owns a
  **content-addressed, disposable** cache keyed on `(slotKey, contentHash,
  documentIdentifier, targetLanguage, scope)`, with provider/model stored as
  provenance rather than cache identity. It retains no parallel Provider/model
  history for the same Source Document, Target Language, and Scope. A content-hash
  change makes stale translations immediately unavailable and deletes them.
  A successful new Job atomically replaces
  the old result; failure or cancellation leaves the old result available as fallback.
  Offline mode may read a matching Completed Translation but never queues a Job or sends
  content when the network returns. Network Jobs require an explicit user action and
  user-configured Endpoint under ADR-0062; the package adapters are implemented, while
  App consent, credentials, settings, and UI composition are owned by the App. The App
  stores non-secret Provider configuration as one versioned SharedPreferences snapshot
  and keeps credential values exclusively in platform secure storage.
  Translation and rendering share source-anchored Markdown block identities so
  live Drafts can replace completed blocks in place without mutating source.
## Relationships

- **Skill Workspace → Translation:** Translation consumes one selected Markdown
  document from a Repository Copy plus the published Slot Key and content hash. It is
  strictly read-only with respect to skill content and never mutates the repository or
  any Activation.
- **App composition:** `skilldeck-app/` (Dart package `skills_manager`, the desktop app) is the single front end and
  composes Skill Workspace and Translation; the contexts do not depend on each other
  directly.
- **`skilldeck` CLI → App:** the CLI is a client of the running App's local
  **Command Host** and never opens the Workspace (ADR-0111). It is a remote control
  for the one front end, not a second one, and carries no caller identity.
  Destructive requests become **Approval Requests** that the user confirms in the
  App.

## Notes

- Translation deliberately lives **outside** Skill Workspace. Translation is network-
  and LLM-facing and is therefore a separate context with a separate disposable cache.
- The upstream TypeScript/npm `skills` CLI is a read-only compatibility reference
  for Skill Workspace source/discovery behavior, not a context in this repository.
- **Planned:** a fourth context, **SkillDeck Cloud** (`packages/skills_cloud/`), is
  accepted and scheduled (PRD §6 M6, ADR-0105, ADR-0107). It replaces the earlier
  planned Skill Marketplace context. It covers Personal Sync and Distribution: Team
  packages and the public Marketplace.

  It is **not listed under Contexts yet** because its terms are still being modeled
  in `.scratch/skilldeck-cloud/`. Add it here when they are defined.

  It lives **outside** Skill Workspace, consuming it through the seams in ADR-0105
  decision 9. Skill content travels over Git through the networked Internal Revision
  Engine (ADR-0106).
