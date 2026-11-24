---
status: accepted (2026-11-23); repository follow-ups applied, ADR-0105 amendment applied
revises: ADR-0105 (decisions 1, 3, 4, 5, 6, 9, 10, 12, and the 2026-11-14 amendments); replaces Cloudflare Artifacts as the Git host
depends-on: ADR-0106 (networked Internal Revision Engine), ADR-0107 (hosting)
---

# ADR-0105 revision: one Distribution model, state-based Personal Sync, and Revision Packs

> **Status:** Proposed and accepted by the maintainer on 2026-11-23, R1–R17.
> The product decisions marked *(user decision 2026-11-23)* were agreed in
> discussion on that date, as was the vocabulary of the draft `skills_cloud`
> CONTEXT, including Upload, Device Exclusion, and Synced Origin Source. R15
> (Revision Packs instead of Git hosting) stands subject to the Revision Pack
> prototype, under the decision rule in R16. R2's Release Pack acceptance rule
> is the Phase 2 direction, to be confirmed when Phase 2 starts.
>
> Follow-up edits:
>
> - **Done (public repository, commit `bc4c9e6`, 2026-11-23):** the
>   `skills_cloud` CONTEXT carries the R15 terms and is marked accepted; the
>   CONTEXT-MAP draft marker is gone; the Skill Workspace CONTEXT, CLAUDE.md,
>   and AGENTS.md follow-ups under Consequences are applied.
> - **Done (private docs):** the Decision section below is appended to ADR-0105
>   as `## Amendments (2026-11-23)`, followed by the 2026-11-24 decisions.
>
> Where this revision conflicts with an earlier amendment, this revision applies.
> Vocabulary follows the draft `skills_cloud` CONTEXT.

## Context

The SkillDeck Cloud PRD describes four capabilities: Personal Sync, Individual
Sharing, Team Distribution, and the Public Marketplace. ADR-0105 models two of
them, Personal Sync and Distribution. It leaves the Sync model (issue 05), the
repository layout (06), Git authentication (07), and the Registry model (08)
open. Its phases do not include Individual Sharing.

The first Phase 1 implementation (branch `feat/cloud-personal-sync-20261115`)
used operation replication with exactly-once bookkeeping on the client. Every
local or remote change became a durable intent. The client also stored:

- 24-hour first-send windows;
- receipt and echo acknowledgements;
- caller-outcome proofs;
- page digests;
- a staged inbox.

The result was hard to use and hard to evolve:

- Fourteen pending reasons, of which only "Dirty Draft" had a user action. The
  others, including Divergence, metadata conflict, and reconciliation, were dead
  ends.
- Metadata conflicts kept local values indefinitely, so Devices drifted apart
  without converging.
- The sync selection could not change after the first enable.
- Skills from Local folders and Adopted Skills were excluded, although the PRD
  requires local-folder Skills.
- Change discovery was a 30-minute poll with no other trigger, so a change
  could take half an hour to reach another Device.
- `SkillsRepository` gained fifteen cloud-shaped methods (reserve, apply, and
  inspect-outcome sets), plus a one-way Workspace schema migration.

The root cause is the Sync model, not code quality. A model that never decides
leaves every uncertain case pending, so the user holds a decision with no UI
for it.

Three observations drive this revision:

1. Sharing, Teams, and the Marketplace are one operation, delivering an
   immutable version to an audience, with different audiences. Their PRD rules
   already match existing Skill Workspace concepts: Upstream Revision, Local
   Customization, Update Candidate Session, and Source Unavailable.
2. Git's own model already solves multi-writer replication of revision history:
   ancestry, fast-forward-only heads, compare-and-swap, and three-way merge from
   the real common ancestor. Reconciling state instead of replaying operations
   makes retries, crashes, and offline work safe without bookkeeping.
3. The service needs Git's data model, not a Git server. With the database
   holding every head, a Git host would only store bytes and answer ancestry
   questions. Object storage and the database already do both. Skill
   repositories are small *(maintainer assessment 2026-11-23)*, so smart-HTTP
   negotiation, which saves bandwidth on large repositories, buys little. A
   Git host would add a beta product or a server to operate, a second
   credential system, and a second network client on every Device.

## Decision

### R1. One Distribution model (refines decisions 1 and 5)

Distribution has one model with three forms. A **Channel** carries immutable
**Releases** of one Skill, is owned by one **Principal** (a Cloud Account or a
Team), and is read through **Grants**.

| Form | Channel owner | Grant | Additions |
| --- | --- | --- | --- |
| Individual Sharing | Cloud Account | Person Grant | none |
| Team Distribution | Team | Team Grant | Membership roles, audit history |
| Public Marketplace | Cloud Account or Team | Public Grant | Listing, Public Index, Reports, moderation, required signatures; later search and Ratings |

Every form shares the same parts:

- **Install and update:** recipients install a Release through the ordinary
  source-agnostic install flow with a **Cloud Release Source**. A newer Release
  becomes the next Upstream Revision through ordinary Update, which preserves
  Local Customization and turns conflicts into an Update Candidate Session.
- **Revocation:** ending a Grant or Membership makes the source **Source
  Unavailable**. Installed copies stay.
- **Withdrawal:** a withdrawn Release blocks new installs and fetches. Installed
  copies show their withdrawn state and are never deleted automatically.

Personal Sync remains a separate capability with its own lifecycle (R3–R8).
A Skill installed from a Channel can itself be synced, because its Cloud Release
Source is portable.

### R2. Private and distributed content never share storage (refines decision 4; resolves issue 06)

- **Lineage storage:** each Cloud Lineage Generation has its own Head Packs and
  Commit Graph (R15).
  - It holds Effective and Upstream history.
  - Only its owning account can read it.
  - A Generation change starts new storage. The former Generation's storage is
    deleted after the 7-day grace period (2026-11-14 amendment).
- **Channel storage:** each Channel holds only **Release Packs**. A Release Pack
  contains one Release commit and its closure. The commit's tree equals the
  chosen revision's tree, and its parent is the Channel's previous Release, if
  any.
- **Release writes:** only the service accepts a Release Pack into Channel
  storage, and accepted Release Packs are never rewritten. The publisher's
  Device builds the candidate Release commit and uploads its Release Pack. The
  service accepts it only when:
  - the commit's tree matches the Release Manifest;
  - its parent is the Channel's previous Release, if any;
  - every object in the pack is reachable from the Release commit.

  No staging repository is involved, so this works the same for unsynced
  Skills.

Any part of a Lineage's history would reveal private ancestry. Separate Release
Packs, with the reachability check, make "Notes, tags, drafts, and private
history remain personal" a property of the structure rather than of policy.

### R3. State-based Personal Sync (refines decisions 3 and 6; resolves issue 05's model)

- **Head Advance:** the service database stores one **Lineage Head** per Cloud
  Lineage: Effective commit, Upstream commit, Head Pack, Generation, Portable
  Source, and Declared Skill Name. A **Head Advance** moves the Effective commit
  only to a descendant within one Generation. It is the server-side Business
  Commit Point of the 2026-11-14 amendment, and a stale expectation is rejected
  without effect.
- **Generation change:** a separate, explicit transaction that represents
  Source Replacement.
- **Reconciliation:** a Device compares each local Effective Revision L with the
  head R:
  - L = R: nothing to do;
  - L is an ancestor of R: Fast-forward Apply;
  - R is an ancestor of L: upload a Head Pack, then Head Advance expecting R;
  - otherwise: Divergence, resolved by a Sync Merge from the real common
    ancestor.
- **No client queue:** pending work is derived from state. The client keeps no
  outbox of intents, first-send windows, receipt acknowledgements, or
  caller-outcome proofs. A lost response resolves at the next Reconciliation,
  which reads committed server state.
- **Server operation IDs:** these remain for deduplication and audit. Client
  correctness never depends on retrieving a stored receipt.
- **Upstream on Divergence:** if one Upstream commit descends from the other,
  the descendant is kept. Otherwise the Upstream commit already in the Lineage
  Head is kept, and the other Device's content survives through the Sync Merge.
  A later update check compares content hashes (ADR-0030), so no upstream change
  is lost or imported twice *(user decision 2026-11-23)*. Phase 1 acceptance
  requires qualification tests with two Devices updating the same Git Source
  while offline.

### R4. What applies without asking (resolves decision 6's open question)

Apply automatically:

- Fast-forward Apply;
- Synced Removal (a Cloud Lineage tombstone);
- Generation changes;
- a clean, valid Sync Merge, which is published locally and then Uploaded
  *(user decision 2026-11-23)*.

A conflicting Sync Merge becomes an Update Candidate Session attributed to the
other Device and uses the existing conflict review. A Dirty Draft or an Update
Candidate Session blocks incoming content for that Skill only (ADR-0088). Other
Skills keep syncing.

### R5. Metadata and tags

Every synced metadata value has a server **Field Version**, and every write is
a compare-and-set against it.

- **Favorites, Skill Tag Assignments, and tag names:** settled in server
  acceptance order. The client accepts the result without asking
  *(user decision 2026-11-23)*.
- **Notes:** two different texts written from the same Field Version form a
  **Note Conflict**. Both texts are kept until the user chooses or combines them
  *(user decision 2026-11-23)*.
- **Synced Tag Vocabulary:** with Personal Sync on, Personal Tags are account
  vocabulary.
  - The service keeps one tag per normalized name.
  - Creating an existing name returns the existing tag.
  - Renaming onto an existing name merges assignments into the existing tag
    *(user decision 2026-11-23)*.
  - Deleting a tag wins over a concurrent assignment.

### R6. Selection and lifecycle

- **Choose what to sync:** opt-in per Skill, changeable at any time.
- **Stop Syncing:** removes the Skill from the Cloud Library. Every Device keeps
  its copy as Device Only.
- **Synced Removal:** removes the Skill on every Device, with the 7-day storage
  grace and 90-day tombstone of the 2026-11-14 amendment.
- **Device Exclusion:** a device-local choice not to materialize one Cloud
  Lineage. It leaves the Cloud Library and other Devices unchanged.
- **New Device:** materializes every Cloud Lineage in the Cloud Library except
  its Device Exclusions. It creates no Activations, then offers a one-time
  activation step *(user decision 2026-11-23)*.
- **Linking:** automatic only on an exact Portable Source, Slot Key, and content
  match (unchanged from 2026-11-14).
- **Reset:** a Device returning after tombstone retention has lapsed must reset.
  Each linked Skill missing from the Cloud Library becomes Needs Attention and
  is never re-uploaded automatically.

### R7. Skills from Device-Bound Sources sync (PRD)

Local and Adopted Snapshot Sources are **Device-Bound**.

- **On the server:** Personal Sync stores them as a **Portable Source** of
  source type, Origin Device, and display label. No absolute path leaves the
  Origin Device.
- **Origin Device:** keeps its original descriptor and remains the only Device
  that can check that Source for updates.
- **Other Devices:** record a **Synced Origin Source**, which receives new
  revisions only through Personal Sync.

### R8. Change delivery (refines ADR-0107 usage; user decision 2026-11-23)

- **Account Change Feed:** the service keeps one per account, monotonically
  sequenced, holding only the latest entry per entity, with identities and
  versions but no payloads.
- **Feed Check:** a Device reads the Account Change Feed from its cursor. A
  check that finds nothing new costs one small request and returns an empty
  result.
- **Feed Check triggers:**
  - launch, returning to the foreground, reconnecting, and waking from sleep;
  - every 2 minutes while the App is running, even in the background.

  The service can lengthen the interval with `Retry-After`. Failures back off
  with jitter, up to a cap.
- **Reconciliation:** runs for each changed entry a Feed Check returns.
- **No realtime channel:** Phase 1 has no WebSockets and no Durable Objects.
  Personal Sync is not live editing. A Device that someone is looking at
  reconciles at once through the foreground trigger. Only an unattended Device
  waits, at most one interval.
- **Adding push later:** Reconciliation does not depend on what triggers it. A
  push channel can be added later, without protocol changes, if measured delays
  turn out to matter.
- **Downloading:** a Device downloads a Head Pack or Release Pack only for
  Lineage Heads and Channels whose Feed entry changed. Pack storage is never
  polled.
- **Distribution:** new Releases for a recipient's Grants appear on that
  recipient's Account Change Feed.

### R9. Content transfer authentication (resolves issue 07)

- **One credential:** packs upload and download only through the Cloud API. Each
  request is authorized by the Cloud Session, and by ownership or a current
  Grant checked at request time.
- **No content credentials:** there are no Git Access Tokens, storage
  credentials, or signed storage URLs. No credential is ever placed in a URL.
- **Engine boundary:** `skills_workspace` performs no cloud network I/O. It
  reads and writes pack files at paths its caller supplies (R11), and never sees
  the Cloud Session, cloud URLs, or cloud identifiers. No cloud traffic uses
  decision 9's per-operation credential callback.
- **Persistence and logs:** the Cloud Session lives only in platform secure
  storage. It never enters Source Descriptors, SQLite, Revision Store
  configuration, Operation Records, URLs, or logs. Transfer errors are logged by
  status class only.

### R10. Every status is resolvable

Sync Status is derived per Skill: Device Only, Synced, Waiting to Upload,
Applying, or Needs Attention. It is shown on the Skill itself, not only in
Settings. Every status other than Synced and Device Only either clears when
connectivity returns or carries a typed **Attention Reason** with defined
actions. A state with neither is a release-blocking defect.

| Attention Reason | Resolving actions |
| --- | --- |
| Incoming change waits behind a Draft | Publish the Draft (then Sync Merge); review the incoming difference; discard the Draft |
| Sync Merge conflict | Existing conflict review, with keep-this-Device and keep-other-Device shortcuts |
| Note Conflict | Keep one text or combine both |
| Skill Slot occupied by a different local Skill | Replace the local Skill; keep it and add a Device Exclusion |
| Removed on another Device while a Draft exists here | Remove here too; keep it here as Device Only |
| Source replaced on another Device while this Device has unsynced revisions | Accept the replacement; keep this Device's copy as Device Only |
| Missing from the Cloud Library after a reset | Remove here; keep it here as Device Only; Upload it as a new Cloud Lineage |

Account-level conditions are shown once per Device: sign-in required, Device
revoked, and storage limit reached.

Because the service verifies every Head Pack before a Head Advance (R15), a
Lineage Head on the server is always complete, and no Attention Reason for a
damaged cloud copy is needed. If R15's fallback is used instead, this table
gains one.

### R11. Skill Workspace seams (refines decision 9 and its 2026-11-14 amendment)

`skills_workspace` adds exactly these public operations:

1. **Export a Revision Pack:** write to a caller-supplied file a pack holding
   the complete closure of a managed Skill's named published revisions. In
   Phase 1 these are the Effective and Upstream heads.
2. **Import a Revision Pack:** index a pack file into non-authoritative staging.
   - Every object is verified, and so is the completeness of the named
     revisions' closure.
   - Importing objects the Store already holds is a no-op.
   - It reports exactly one of: imported, malformed, or incomplete.
3. **Apply remote state:** the Sync apply contract of the 2026-11-14 amendment.
   - It runs as one transaction, guarded by the expected local Effective
     Revision.
   - It covers content (fast-forward, merge, or install on a new Device),
     Skill Extra Data, Skill Tag Assignments, tag vocabulary, and Removal.
   - It reports exactly one of: no change, fast-forwarded, merged, conflicted,
     Draft resolution required, or Skill Slot occupied.
4. **Read committed changes:** the committed-change feed, reporting the Managed
   Skill IDs and change kinds since a Repository Revision.
5. **Provenance:** the Synced Origin Source descriptor variant (Phase 1) and the
   Cloud Release Source variant (Phase 2). Both are credential-free, with a
   versioned descriptor encoding.

Seams 1 and 2 are local file operations. They build on the existing Recovery
Bundle pack code (`createRecoveryPack` and `restoreRecoveryPack`), which already
writes and verifies the closure of retained roots. Importing next to a live
Store, rather than into a new one, is the new native work.

The public Workspace API must not gain any of the following:

- reservation or outcome-inspection operations;
- network transfer, URLs, or credentials;
- cloud identifiers;
- Field Versions;
- Sync Status.

Retry safety comes from state comparison under the expected-revision guard, not
from caller-outcome bookkeeping.

### R12. Individual Sharing (resolves the PRD's open sharing decisions)

- **Method:** a Share is a Person Grant on a Channel owned by a Cloud Account.
  Anonymous links are not part of the first release.
- **Recipients:** must sign in *(user decision 2026-11-23)*.
- **Future versions:** recipients receive every later Release on that Channel
  until revoked *(user decision 2026-11-23)*.
- **Before sharing:** the sender sees the chosen revision, its file manifest,
  and the Channel's current Grants.
- **Channels per Skill:** a Cloud Account owns at most one Channel per Skill.
  - If the Skill is synced, the Channel is bound to its Cloud Lineage.
  - Otherwise it is bound to the creating Device's Managed Skill ID, so only
    that Device can create Releases. Sharing does not require Personal Sync
    *(user decision 2026-11-23)*.

### R13. Phases (revises decision 12; user decision 2026-11-23)

1. **Personal Sync**, including bootstrapping a new Device.
2. **Individual Sharing:** the smallest end-to-end Distribution path. It proves
   Channels, Releases, recipient install and update, Revocation, and Withdrawal
   without a Team model.
3. **Team Distribution:** Team Principal, Membership roles, and audit history.
4. **Public Marketplace.** It starts with the Public Grant, Listings, Reports,
   moderation, required signatures, and the **Public Index**: an Agent Skills
   discovery index (`/.well-known/agent-skills/index.json`, schema 0.2.0)
   listing each public Channel's latest available Release as an archive with
   its digest *(user decision 2026-11-23)*.
   - Any Agent Skills client can install from the Public Index. SkillDeck
     installs through a Cloud Release Source, so signatures, Withdrawal, and
     updates apply.
   - An index digest proves integrity, not publisher authenticity.
   - Search and Ratings, which the PRD requires, follow in later Phase 4
     releases.
5. **Entitlement and payments.**

Decision 12's rule stands: each phase ships a complete user path, and only the
active phase is built.

Phase 1 delivers:

- Device Authorization sign-in, with email OTP and GitHub on the web (R14);
- the Cloud Library, Head Pack storage, and the Commit Graph (R15);
- Head Advance;
- the Account Change Feed and Feed Checks;
- Reconciliation, metadata, and the tag vocabulary;
- per-Skill Sync Status with every R10 Attention Reason;
- new-Device bootstrap;
- the R11 seams 1–4 and the Synced Origin Source.

### R14. Device sign-in (refines the 2026-11-14 sign-in amendment; user decision 2026-11-23)

Devices sign in only through **Device Authorization** (RFC 8628, the Better
Auth `deviceAuthorization` plugin).

- **Flow:**
  - The App requests a device code.
  - It opens the system browser at `verification_uri_complete` and also shows
    the user code.
  - The person signs in on the web with email OTP or GitHub and approves the
    Device.
  - The App polls the token endpoint at the interval the service sets, honoring
    `slow_down`. It stores the returned Cloud Session only in platform secure
    storage.
- **What the App never does:** collect a password, OTP, or third-party
  credential; open a loopback listener; register a custom URL scheme.
- **Phishing mitigation:** the approval page shows the requesting Device's name
  and platform. Codes expire quickly and can be approved once.
- **Polling:** sign-in polling uses the interval the service sets. It is
  separate from R8's Feed Checks.

### R15. Revision Packs instead of Git hosting (resolves issue 02's hosting question; user decision 2026-11-23, subject to the prototype)

The service neither rents nor runs a Git server. Skill content moves as
**Revision Packs**: standard Git pack files that Devices write and index with
the vendored libgit2, and that the Cloud API stores in Cloudflare R2.

- **Head Pack:** every Upload carries one pack holding the complete closure of
  the new Lineage Head's Effective and Upstream commits. One pack is enough to
  materialize a head, so there is no pack chain, negotiation, or compaction.
- **Upload:**
  1. The Device exports the Head Pack (R11 seam 1) and uploads it through the
     Cloud API. Uploads are addressed by the pack's SHA-256, so repeating one is
     safe.
  2. The service verifies the pack and records its commits in the Commit Graph.
  3. The Device calls Head Advance with the expected head, the new head, and
     the pack's digest. The service accepts it only when the pack is verified
     for this Generation and contains both new commits.
- **Verification:** before a pack can back a head, the service indexes it,
  recomputing every object ID, and checks that the closure of the named commits
  is complete. A head on the server is therefore always fully downloadable.
- **Commit Graph:** D1 stores each verified commit's parents per Generation.
  Head Advance's descendant check is a D1 query. The Published Revision History
  projection comes from the same rows.
- **Download:** a Device downloads a Head Pack through the Cloud API, which
  streams it from R2. The Device imports it into staging (R11 seam 2), which
  verifies it again.
- **Retention:** a pack stays while a Lineage Head references it, plus a 24-hour
  grace for downloads and Head Advances in flight. A scheduled sweep deletes
  every other pack.
- **Deletion:** Synced Removal and Generation changes delete every pack and
  Commit Graph row of the Generation after the 7-day grace. Listing the
  Generation's key prefix afterwards shows the deletion is complete (ADR-0089).
- **Layout:** private buckets only. Keys are
  `lineages/<lineage>/<generation>/<sha256>.pack`, and from Phase 2
  `channels/<channel>/<release>.pack`. Objects are never shared across accounts
  (decision 4).
- **Fallback:** if the prototype shows that verification in a Worker is too
  costly, the Device also sends the raw commit objects. The service hashes them
  to verify commit IDs and parents, and only the receiving Device's import
  checks completeness. That brings back a damaged-cloud-copy case needing an
  Attention Reason (R10), so it is a fallback, not the plan.

Effects:

- libgit2 is no longer a cloud network client. Cloud traffic uses the App's
  single HTTP stack per platform: `cupertino_http` on macOS, and on Windows
  the client R17 leaves to a later qualification.
- Retention refs, Git Access Tokens, and host garbage collection no longer
  exist.
- Exit stays simple. Packs are standard Git, and any Generation can be rebuilt
  as an ordinary repository from its Head Pack and Lineage Head, with commit IDs
  unchanged.

### R16. Decisions before development (user decision 2026-11-23)

- **Revision identity at the Workspace seam:** the R11 seams identify revisions
  with an opaque public revision identifier. Its stable string form is the
  commit ID, so `skills_cloud` can send it to the service.
  - Callers treat it as opaque. They never parse it, derive paths from it, or
    infer ancestry from it.
  - This refines the CLAUDE.md rule that keeps Git object IDs out of the public
    API. The raw object type, Store generations, and private paths stay
    internal.
- **Revision Pack prototype decision rule:**
  - If P2 and P4 pass, R15 is built as written. P2 is Worker verification
    accepting a valid pack; P4 is verifying a 1 MB pack in under 1 s of CPU.
  - Otherwise R15's fallback applies, and R10 gains an Attention Reason for a
    damaged cloud copy.
  - Either way, R11 seams 1 and 2 are the same, so Workspace work on them may
    start before the prototype reports.
- **Service origins and environments:**
  - There are three environments: dev (local `wrangler dev` with Miniflare R2
    and D1), staging, and production.
  - Each environment is a distinct service origin, selected per App build
    through the existing `--dart-define-from-file` configuration. A build
    without a configured origin keeps Cloud off.
  - The production API hostname is fixed before any Cloud Session, Cloud
    Lineage mapping, or Cloud Release Source descriptor is persisted. The
    hostname itself is still open.
- **No realtime channel in Phase 1:** WebSockets and Durable Objects are
  removed (R8). The earlier rule for authenticating a WebSocket no longer
  applies. If a push channel is added later, its authentication is decided
  then. It must still keep credentials out of URLs.
- **R2 Release Pack rule:** recorded as the Phase 2 direction. It is confirmed,
  or revised, when Phase 2 starts.

### R17. macOS first; Windows Cloud deferred (user decision 2026-11-23)

macOS is SkillDeck's primary platform. Phase 1 is built and qualified on macOS
first, with `cupertino_http` as its HTTP client.

- **Windows qualification is paused.** No Windows HTTP client is chosen yet.
- **Cloud code is unaffected.** `skills_cloud` is pure Dart and talks only to
  the `package:http` `Client` interface, and the App injects the platform
  client. Adding Windows later changes neither the Cloud code nor the protocol.
- **Windows builds keep Cloud off until a Windows client qualifies.** They
  ship without a service origin, which keeps Cloud off under R16, and every
  local operation works as before. *(user decision 2026-11-23)*

**Findings from the first Windows run** (2026-11-23):

The run was partial. It used loopback on one development machine, not the
clean VMs, the physical laptop, or staging.

- **`win_http` 0.2.3 is rejected** for technical reasons, whatever its licence:
  - it reads the whole upload into memory before sending any of it (U1);
  - cancelling a streamed download doesn't stop it (H1);
  - it reports an idle timeout while the server is still sending (U3), so slow
    links would fail large transfers.
- **`dart:io` mostly works, apart from its known flaw.**
  - It passed streaming upload on the wire, the stall and size bounds,
    download cancellation, certificate rejection, and redirect refusal.
  - A connection that stalls during the TLS handshake is never closed (T2: 0
    of 200 closed within 5 s).
  - The proxy and Windows certificate-store cases didn't run. It is expected to
    need its own proxy discovery.
- **Native WinHTTP looks promising,** from a Python spike:
  - closing the handles during the TLS handshake closed the connection 200 of
    200 times, within 7 ms;
  - 50 MB went each way through a fixed 64 KiB buffer, over plain HTTP.

  No Dart version exists yet.
- **Not yet measured for any client:** peak memory per transfer. The samples
  taken can't show it.

**Direction when Windows work resumes:**

- Write our own WinHTTP client from scratch rather than forking `win_http`, so
  no third-party GPL code enters the App.
- It implements `package:http` `BaseClient` with abortable requests, and calls
  the system `winhttp.dll` through FFI, so there is no native build and no
  bundled DLL.
- Its acceptance is the existing Windows HTTP qualification plan.
- Accepting `dart:io` with its handshake flaw as a known limitation (the plan's
  rule 4) is the fallback only if our own client fails.

## Service data model (informative)

The service lives in its own repository (ADR-0116). This sketch only fixes the
ownership of each fact.

- **Identity:** accounts, devices, and Better Auth sessions; teams and
  memberships from Phase 3.
- **Sync:**
  - `lineages`: owner, generation, head Effective and Upstream commits, head
    pack digest, Portable Source, Declared Skill Name, and tombstone;
  - `lineage_commits`: the Commit Graph (generation, commit ID, parent IDs,
    tree ID), written only from verified packs;
  - `packs`: digest, owning generation or channel, size, verification result,
    and creation time, for the sweep;
  - `lineage_revisions`: the Published Revision History projection, so a new
    Device can show history;
  - `skill_fields`: value and Field Version;
  - `tags` and `tag_assignments`;
  - `account_changes`: the latest entry per entity.
- **Distribution (Phase 2+):** `channels`, `releases` (manifest, Release Pack
  digest, signature, withdrawal actor and time), `grants`, and the audit log.
  Listings, reports, and the Public Index arrive in Phase 4, with search and
  ratings after them.

## Build and adopt (informative)

From the 2026-11-23 build-vs-adopt survey and the hosting comparison:

- **Adopt:**
  - Better Auth 1.7 (MIT) on D1, with `emailOTP`, GitHub social sign-in,
    `bearer`, `deviceAuthorization`, and per-session revocation. Its
    `organization` plugin is the Phase 3 candidate for Teams and Membership.
  - Cloudflare R2 for Revision Packs.
  - A JavaScript pack reader in the Worker for verification, with
    isomorphic-git (MIT) as the candidate. The prototype confirms it.
  - The vendored libgit2 on Devices, to write and index packs only.
  - `cupertino_http` for HTTP on macOS.
  - The Agent Skills discovery index format for the Phase 4 Public Index.
- **Build:**
  - Sync: Reconciliation, Head Advance, Field Version compare-and-set, the
    Account Change Feed with Feed Checks, and tag rules.
  - Revision Packs: the upload and download endpoints, pack verification, the
    Commit Graph, and the unreferenced-pack sweep.
  - Sync Status with Attention Reasons.
- **Rejected:**
  - Cloudflare Artifacts: open beta, priced per operation, and without hooks or
    documented garbage collection. It also needs a separate token system and
    makes libgit2 a second network client. Local tests on 2026-11-23 found it
    compatible, so compatibility was not the reason.
  - Self-hosted Git (`git-http-backend`, Soft Serve, Gitea, or Forgejo on
    Containers): we would operate a server for negotiation that small
    repositories do not need.
  - Sync engines and CRDT bindings. PowerSync's upload queue is a client
    outbox, Electric's Dart client is discontinued, Realm Device Sync reached
    end of life, and Couchbase Lite is BSL-licensed.
  - Desktop sign-in packages that lack Windows support or the App's macOS 12
    deployment target.
  - Durable Objects and WebSocket clients for Phase 1. Their only role was the
    realtime Change Ping, which R8 removes.
  - `win_http` 0.2.3 for Windows HTTP. It buffers whole uploads, can't cancel
    a streamed download, and reports false idle timeouts (R17 findings).
- **Pending:** the Worker pack reader (the Revision Pack prototype).
- **Deferred:** the Windows HTTP client (R17). The direction is our own
  WinHTTP `BaseClient` over FFI.

## Consequences

- **Skill Workspace CONTEXT:**
  - Personal Tags become account vocabulary when Personal Sync is enabled
    (R5);
  - add the Synced Origin Source and Cloud Release Source descriptor variants
    (R7, R1);
  - add Revision Pack export and import (R11);
  - the source descriptor encoding migrates.
- **`skills_cloud` CONTEXT:** add Revision Pack, Head Pack, Release Pack, and
  Commit Graph. Retire Lineage Repository, Channel Repository, retention refs,
  and Git Access Token. Then mark it as accepted, and drop the draft marker in
  CONTEXT-MAP.
- **CLAUDE.md:** the stack line "Artifacts for Git, Workers for the API, D1,
  Durable Objects, and Better Auth" becomes "R2 for Revision Packs, Workers
  for the API, D1, and Better Auth". The rule keeping cloud tokens out of the
  engine stays, and now holds by construction.
- **AGENTS.md tripwires:** add the following:
  - client-side exactly-once bookkeeping (intent outboxes, receipt windows,
    caller-outcome proofs) instead of state Reconciliation;
  - a pending state without a resolving action;
  - private history or Skill Extra Data entering Channel storage, or a Release
    Pack holding objects unreachable from its Release commit;
  - a Head Advance backed by an unverified pack;
  - cloud network I/O, cloud URLs, or credentials inside `skills_workspace`;
  - cloud identifiers, Field Versions, or Sync Status in the `skills_workspace`
    public API.
- **Prototype branch:** `feat/cloud-personal-sync-20261115` is not merged.
  - Candidates to carry over after review:
    - the secure session store;
    - HTTPS transport bounds.
  - Discarded:
    - the intent outbox, 24-hour windows, receipts and echoes, reservation and
      outcome-inspection APIs, the staged inbox, and scope incarnation fences;
    - native cloud push and fetch with per-operation headers, which Revision
      Packs replace;
    - the PKCE loopback sign-in, which Device Authorization replaces (R14).
  - Its recorded libgit2 patches (strict redirects, disabled `FETCH_HEAD`,
    Windows path bounds) are reviewed only for public Git Sources (ADR-0106).
  - Workspace schema v4 is re-derived from the R11 seams.
- **Decision 8** (server-trusted content, Privacy Policy before upload) and
  **decision 10** (device-specific state never syncs; Activation sync deferred;
  Drafts never sync) are unchanged.

## Alternatives considered

- **Operation replication with exactly-once delivery:** the prototype. Rejected
  for unresolvable pending states, client complexity, and a wide Workspace
  surface.
- **CRDTs for Skill content:** rejected. Git ancestry and three-way merge are
  already the domain's merge mechanism, and Update Candidate Sessions already
  present conflicts.
- **Distributing from a Lineage's own history:** rejected, because a download
  exposes private ancestry.
- **Separate models for Sharing, Teams, and the Marketplace:** rejected. They
  would triple install, update, and revocation semantics, which the PRD
  describes identically.
- **Realtime Change Pings over Durable Object WebSockets:** removed from
  Phase 1 *(user decision 2026-11-23)*. Personal Sync is not live editing, and
  the foreground trigger covers a Device someone is looking at. The ping
  required:
  - a Durable Object per account;
  - a WebSocket client with reconnect logic on macOS and Windows;
  - Windows WebSocket qualification;
  - its own authentication rule.

  Devices still update automatically, within one Feed Check interval when
  unattended. That is how this revision reads the PRD's "automatically updates
  other connected devices".
- **A Git host (Cloudflare Artifacts or self-hosted):** rejected in R15 and under
  Build and adopt.
- **Incremental packs and pack chains:** deferred. They save upload bandwidth
  but add pack lists, negotiation, and compaction. Reconsider only if measured
  Head Pack sizes require it.
- **Signed R2 URLs for direct transfer:** rejected. They put a credential in a
  URL, and streaming through the Worker costs little because R2 egress is free.
- **A commit graph reported by the Device without server verification:** kept
  only as the R15 fallback.

## Open questions

### Before development starts

- **Worker pack verification:** answered by the Revision Pack prototype
  (2026-11-23 brief). R16 records what each result means.
- **Production API hostname:** the value itself (R16).
- **Sign-in prerequisites:** an email delivery provider for Better Auth's
  email OTP, and the owner and callback domain of the GitHub OAuth app.
- **Service repository and accounts:** confirm that the private service
  repository (ADR-0116) and a Cloudflare account for dev and staging exist, or
  name who creates them.

### Before beta

- **Data region:** the jurisdiction of the R2 bucket and the D1 database. R2
  jurisdiction is fixed at bucket creation, and decision 8's privacy disclosure
  depends on it. Settle before any real user data is stored.
- **Quotas (issue 10):** numbers for the account-level "storage limit reached"
  condition.
- **Backup:** whether R2 durability is enough, or packs are also copied to a
  second bucket.
- **Privacy Policy text:** required before a user's first Upload (decision 8).
- **Account deletion:** whether Phase 1 includes a complete account-deletion
  flow (ADR-0089).
- **Pack size bound:** Worker request bodies have a plan limit (100 MB on paid
  plans, UNVERIFIED). Skills are far below it *(maintainer assessment
  2026-11-23)*, and the prototype records real sizes.

### Later phases

- **Windows Cloud (R17):** when to resume Windows qualification, with our own
  WinHTTP client as the candidate. The `win_http` licence question no longer
  arises, because `win_http` is rejected and our own client is first-party
  code.
- **Release details (Phase 2):** fixed author, committer, and time fields for
  Release commits, and how a publisher's Device obtains the previous Release
  to use as the parent.
- **Withdrawn Releases already installed (issue 09):** proposal is to notify and
  offer one-click deactivation, never to delete automatically. Severity tiers
  for moderator withdrawal are still open.
- **Release signing (issue 09):** the survey recommends Ed25519 signatures over
  the canonical Release Manifest. Still open: publisher key custody, and
  whether Sharing and Team Releases also sign or only record the manifest
  digest.
- **Team model (issue 03):** invitations, ownership transfer, and the last-Owner
  rule.
- **Recipient notification:** whether a new Share or Release also sends email,
  or appears only in the App.
- **Unchanged open issues:** 08, the Listing schema; and the retention and
  pricing parts of 10. Issue 02, hosting region, is now "Data region" above.
- **Out of scope for now:** mainland China reachability *(user decision
  2026-11-23)*.

## Accepted costs

- **Background delay:** an unattended Device sees another Device's change up to
  one Feed Check interval (2 minutes) late.
- **Request volume:** Feed Checks grow with the number of running Devices. For
  10,000 Devices running all day, that is about 216 million requests a month,
  roughly $60 at $0.30 per million Workers requests (UNVERIFIED). The service
  can lengthen the interval with `Retry-After` if load requires.
- **Full-closure uploads:** every Upload sends the Skill's whole history again.
  This is acceptable while Skills stay small. Incremental packs are the planned
  optimization if measurements call for one.
- **Our own transfer protocol:** we maintain pack upload, verification, and the
  sweep instead of renting a Git host.
- **Durability:** content relies on R2's durability until the backup question is
  settled.
- **Storage:** Release Packs duplicate objects that also exist in the
  publisher's Lineage storage. Deduplication never crosses accounts, by
  decision 4.
- **Server-side merge settlement:** last-writer-wins on Favorites, tag
  assignments, and tag names can silently replace a value edited on another
  Device. This was accepted for low-stakes fields, with Notes as the exception.
- **Windows later:** Windows users get Cloud after macOS users, once a
  Windows client qualifies (R17).
- **Automatic Sync Merges:** clean Sync Merges publish without a review step, so
  a merged result is visible to Agents before the user looks at it. Local
  Published Revision History and Restore Publish remain the recovery path.
