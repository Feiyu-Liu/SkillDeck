# Handover: Phase 1 Git hosting — Cloudflare Artifacts vs. self-hosted Git

**Date:** 2026-11-23
**From:** the SkillDeck Cloud architecture session
**To:** the agent comparing Git hosting options for Phase 1 (Personal Sync)
**Decision owner:** the maintainer. Your job is to recommend; the decision is still open.

## 1. Your task

Compare **Cloudflare Artifacts** with **self-hosted Git** as the Git host for
SkillDeck Cloud Phase 1 (Personal Sync). Recommend one, with evidence. Name
the exit path from whichever one you recommend, and list the qualification
tests that would confirm the choice before implementation starts.

Judge both options against what **Phase 1 actually needs** (section 4). Check
Phase 2–4 compatibility (section 5), but don't optimize for it. The project
rule is to build only the active phase.

## 2. Material to read first

| Document | Where | Notes |
| --- | --- | --- |
| `skills_cloud` CONTEXT (draft vocabulary and rules) | `packages/skills_cloud/CONTEXT.md` on branch `claude/amazing-keller-unt4dd` of `Feiyu-Liu/SkillDeck` | Public. It's the authority for terms used here. |
| ADR-0105 revision proposal (R1–R14) | `0105-revision-2026-11-23-proposal.md`, supplied by the maintainer | **Private.** Never commit it to the public repository. |
| Original ADR-0105 with the 2026-11-14 amendments | Supplied by the maintainer | **Private.** |
| Build-vs-adopt survey | `cloud-build-vs-adopt-survey.md`, supplied by the maintainer, especially §2.6 and §4 | Read Cloudflare docs from the `cloudflare-docs` GitHub source at 2026-11-22. `developers.cloudflare.com` was unreachable from that session. |
| Repository guide | `CLAUDE.md`, `AGENTS.md`, `CONTEXT.md`, `CONTEXT-MAP.md` at the repository root | Invariants and tripwires. |
| Prototype branch (not merged) | `feat/cloud-personal-sync-20261115` | It contains a working libgit2 **push** with per-operation headers, plus integration tooling against a local service. It's useful for qualification tests. Its sync model was rejected, so don't evaluate it. |

## 3. Settled decisions (don't reopen)

- **Two channels:** Skill content travels over Git smart HTTPS. Everything else
  goes over an HTTPS API on Cloudflare Workers + D1. Realtime pings use Durable
  Objects.
- **Database authority:** the service database is authoritative for which
  commit is selected (the **Lineage Head**). Git repositories are authoritative
  for bytes and ancestry only. Business state never lives in Git refs.
- **Repository layout:** one **private Lineage Repository per Cloud Lineage
  Generation**. Objects are never shared across accounts (decision 4). A
  Generation change, meaning Source Replacement, creates a new repository. The
  old one is deleted after a 7-day grace period, and deletion must be complete
  (ADR-0089).
- **Upload protocol:**
  - The Device pushes objects to `refs/retain/<commit-id>`.
  - It then calls the API, which runs a **Head Advance**: a compare-and-swap
    that accepts only a descendant of the current head.
  - The API validates the object ID it is given, never a movable ref.
  - Unreferenced retention refs are collectable.
- **Client Git:** the client is the vendored, pinned libgit2 inside
  `skills_workspace`, over HTTPS through the platform TLS stack.
  - No SSH and no system Git for cloud traffic.
  - Credentials are per-operation headers supplied by a callback and never
    persisted.
  - Redirects are rejected.
- **Git Access Tokens:** short-lived, one repository, one direction (read or
  write), minted by the service per operation. The Cloud Session token must
  never reach Git hosting.
- **Change discovery:** Git is never polled. Pings and the change feed come
  from the API.
- **Channel Repositories (Phase 2+):** only the service writes to them, and
  Devices never hold Channel write tokens. Release immutability must not depend
  on the host offering protected refs.
- **Out of scope:** mainland China reachability *(maintainer decision
  2026-11-23)*. Don't weigh it.
- **Sign-in:** Device Authorization (RFC 8628) through Better Auth. This
  doesn't affect Git hosting, except that Git tokens are separate from the
  session.

## 4. Phase 1 requirements for the Git host

| # | Requirement | Why |
| --- | --- | --- |
| H1 | Create and delete private repositories programmatically from a Worker or API, at scale: one per synced Skill per Generation, across all accounts. | Lineage Repositories, Generation changes, Synced Removal, Stop Syncing |
| H2 | Smart-HTTP push and fetch that the pinned libgit2 can use. libgit2 pushes over receive-pack protocol v0/v1. | The only client is libgit2 |
| H3 | Per-repository, per-direction, short-lived, revocable credentials sent as an HTTP header, minted by our service. | Git Access Tokens (R9) |
| H4 | Many `refs/retain/<commit-id>` ref updates in one push. A first Upload can carry a Skill's whole Published Revision History. | Upload protocol |
| H5 | A server-side way to confirm that a pushed commit exists and to walk its parents, from a Worker, before Head Advance. | Head Advance checks ancestry |
| H6 | Fetch of committed heads. A head the database references must stay fetchable through a ref; check whether fetch by unadvertised SHA is allowed. | New-Device bootstrap, Fast-forward Apply |
| H7 | Deleting unreferenced retention refs, and eventually reclaiming their objects. | Storage hygiene, ADR-0089 complete deletion |
| H8 | Size limits that fit Skills. The Workspace caps one Skill at **50 MiB and 1,000 files** (`maximumNormalizedSkillByteSize`, `maximumNormalizedSkillFileCount`), and history adds to that per repository. | Every Skill the App accepts must sync |
| H9 | Durability and backup of hosted repositories, which ADR-0105 lists as an accepted cost. | Sync is not Backup, but the host must not lose data |
| H10 | A local or emulated host for development and CI integration tests. | Qualification and regression tests |
| H11 | Cost at realistic scale: repositories, storage, and Git operations per sync. | Product viability |
| H12 | Data export and exit: every repository must be cloneable out with full history. | Lock-in |
| H13 | Deployment-region control, if available. | Privacy disclosure (decision 8) |

## 5. Forward compatibility to check (Phases 2–4), but not to optimize for

- **Phase 2, Channel Repositories:** one per Channel. The service must be able to
  write Release commits server-side, for example by copying a verified staged
  commit, with no client write token.
- **Phase 2, Release staging:** where a publisher Device stages a candidate
  Release for an **unsynced** Skill, which has no Lineage Repository. This is an
  open question.
- **Phase 4, Public Index:** each public Channel's latest Release is exported as
  an archive with a `sha256` digest. Public Git read is **not** required; a
  Worker can serve archives.
- **Phase 3, Teams:** read access follows Membership at request time, which
  token minting can enforce.

## 6. Known facts and gaps (from the survey; re-verify)

**Cloudflare Artifacts** (sources: `cloudflare-docs` at 2026-11-22):

- **Status:** open beta since 2026-10-01, Workers Paid plan only. The billing
  start date is inconsistent in the docs (Oct 14 vs Nov 19).
- **Interfaces:**
  - a Workers binding with `create`, `get`, `list`, `import`, `delete`, `fork`;
  - per-repository `createToken(scope, ttl)`, `listTokens`, `revokeToken`;
  - `log`, `readCommit`, `readTree`, `readBlob`, `readFile`;
  - a REST API, and a local simulator since 2026-11-16.
- **Git protocol:** smart HTTP. Fetch uses protocol v1 or v2. **Push uses
  receive-pack v1 only.** No SSH and no LFS.
- **Remote URL:** `https://<account>.artifacts.cloudflare.net/git/<ns>/<repo>.git`.
  The format has changed once, so always use the server-returned remote.
- **Tokens:** scoped to one repository, `read` or `write`, TTL from 60 s to
  1 year, revocable.
- **Events:** Queue events for `pushed`, `fetched`, `repo.created`, and so on.
- **Limits:**
  - 1 GB per repository;
  - 64 MiB and 50,000 objects per push;
  - **32 MiB per file**;
  - 1 MiB of ref updates per push;
  - 2,000 Git requests per 10 s per repository.

  32 MiB per file is below the Workspace's 50 MiB per-Skill cap, so a single
  large file could fail. A first Upload of long history may also need to be
  split into several pushes.
- **Pricing:** 10k operations/month included, then $0.15 per 1k. Content reads
  are weighted 100:1 and token operations 5:1. 1 GB-month included, then $0.50
  per GB-month. Per-repository charges are "coming soon".
- **Jurisdiction:** `eu` or `us`, chosen per namespace and **immutable**.
- **Not documented, so treat as absent:**
  - protected refs, hooks, or an authorization callback;
  - public read;
  - a custom domain;
  - object garbage collection;
  - an SLA.

**Self-hosted Git:**

- **Candidates:**
  - Cloudflare Containers (GA 2026-04-13) running `git-http-backend`, Soft
    Serve (MIT), Gitea (MIT), or Forgejo (GPL-3.0-or-later);
  - a GitHub App with org-owned private repositories as a fallback. Check its
    acceptable-use terms for storage-backend use.
- **Gains:** real hooks, so ref protection and server-side checks are possible.
- **Costs:** we own durable storage, scaling, backups, upgrades, and security
  patching. Check what persistent storage Containers actually provide.
- **Building a Git server on R2 ourselves:** rejected, because it means
  reimplementing pack negotiation.
- **isomorphic-git (MIT) in a Worker:** a Git *client*. Useful for
  server-side writes and ref cleanup on either host.

## 7. Questions the comparison must answer

1. **Can each host meet H1–H13 today?** For each requirement, state whether it
   is met, how, and the workaround or blocker.
2. **libgit2 interoperability:**
   - push over receive-pack v1 with hundreds of `refs/retain/*` updates;
   - fetch without `filter` or `include-tag`;
   - header-based authentication;
   - error classes when a token is expired or revoked.
3. **Retention cleanup (H7):** delete refs by client push, by server push
   (isomorphic-git), or through a host API? Is object GC observable?
4. **Large Skills (H8):** behavior for a file over 32 MiB and for history over
   64 MiB per push. Propose either push splitting or an App-side limit, and say
   which is less harmful.
5. **Head Advance checks (H5):** can a Worker read commit parents with low
   enough latency to check ancestry inside the API request?
6. **Operational burden:** for self-hosting, who runs backups, upgrades,
   incident response, and capacity planning, and roughly how much effort that
   takes each month?
7. **Cost:** give a model for 1k, 10k, and 100k active users, assuming roughly
   20 synced Skills each and a few Uploads per user per day. State your
   assumptions.
8. **Exit path:** how to migrate every repository from one host to the other
   without changing Cloud Lineage IDs or database-held commit IDs. Commit IDs
   must be preserved byte-for-byte.
9. **Beta risk:** what happens to SkillDeck users if Artifacts changes its API
   or pricing, and how much of that the exit path absorbs.

## 8. Deliverable

A Markdown report containing:

- an executive summary;
- the H1–H13 matrix for each option;
- answers to section 7;
- a recommendation with its exit path;
- the qualification tests to run before implementation, each with pass
  criteria, for example "libgit2 pushes 500 retention refs to the recommended
  host and they are fetchable within N s";
- the decisions left for the maintainer.

Cite primary sources and mark anything unverified as **UNVERIFIED**.

## 9. Constraints

- **Repository changes:** don't modify `main` or other people's branches. If you
  write qualification code, use your own branch and keep it out of
  `skills_workspace`'s public API.
- **Private documents:** never commit the ADRs, the ADR revision proposal, or
  the survey to the public GPL repository. The Cloud service lives in a
  separate private repository (ADR-0116).
- **Secrets and outbound data:** use no real credentials, user data, or
  production accounts. Don't put personal or project details in requests to
  outside services.
- **Invariants:** see CLAUDE.md, section "Invariants", and the AGENTS.md
  tripwires.
  - Tokens never enter SQLite, Revision Store configuration, Operation Records,
    URLs, or logs.
  - Remote state changes a Device only through a local Workspace transaction.

## 10. Context on how we got here (brief)

- **Prototype rejected:** it replicated operations with exactly-once
  bookkeeping, which left users in unresolvable pending states. Its sync model
  was replaced by state Reconciliation with fast-forward-only heads (R3).
- **Survey (2026-11-23) verdicts:**
  - Adopt Better Auth on D1, plain Durable Object WebSockets, and
    `cupertino_http` on macOS.
  - Reject sync engines and CRDT bindings.
  - Keep the vendored libgit2.
  - Windows HTTP: decided after real-world testing.
  - Git hosting: still under discussion. That's your task.
