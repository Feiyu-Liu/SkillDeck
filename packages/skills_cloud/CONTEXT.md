# SkillDeck Cloud

This context connects one person's Skill Workspaces across their Devices and
delivers immutable Skill versions to other people through a SkillDeck-operated
service. It owns accounts, Devices, Teams, Cloud Sessions, the HTTPS API
client, Personal Sync, and Distribution (Individual Sharing, Team Distribution,
and the Marketplace). It lives in `packages/skills_cloud/` and reaches Skill
Workspace only through the public seams listed under
[Boundary with Skill Workspace](#boundary-with-skill-workspace). It never opens
Workspace SQLite, Revision Stores, Operation Journals, or private paths.

> **Status:** accepted on 2026-11-23 with the ADR-0105 revision. The Revision
> Pack terms replace Git hosting, subject to a prototype that has not yet
> reported. If verifying packs in the service proves too costly, a fallback
> adds a damaged-cloud-copy Attention Reason. Only Personal Sync (Phase 1) is
> buildable now, on macOS first: Windows builds keep Cloud off until a Windows
> HTTP client qualifies. Distribution terms
> are defined so that Phase 1 does not preclude them, not so that they are built
> early.

## Language

### Identity

**Cloud Account**:
The SkillDeck service identity of one person, used for sign-in, Personal Sync,
Grants, and Team Membership.
_Avoid_: User profile, Workspace, local account

**Device**:
One App installation registered to a Cloud Account with its own Cloud Session.
Each Device can be revoked independently.
_Avoid_: Machine, Workspace, Agent

**Cloud Session**:
The verified, server-backed bearer session of one Device, and the only
credential a Device holds for the service. It is stored only in platform secure
storage and sent only to the HTTPS API.
_Avoid_: Git credential, API key, access token, signed URL

**Device Authorization**:
The sign-in by which a Device obtains its Cloud Session (RFC 8628). The App
shows a user code and opens the system browser. The person signs in on the web
and approves that Device, and the App then receives the session.
_Avoid_: Login form, loopback redirect, OAuth callback

**Principal**:
An owner of cloud content: a Cloud Account or a Team.
_Avoid_: User, actor

**Team**:
A Principal whose Channels are readable by its Members and managed by its
Owners and Publishers.
_Avoid_: Organization, workspace, group chat

**Membership**:
One Cloud Account's role in one Team: Owner, Publisher, or Member. Owners manage
Membership. Owners and Publishers create and withdraw Releases. Members install
and update.
_Avoid_: Seat, permission

### Personal Sync

**Personal Sync**:
Replication of one Cloud Account's selected Skills between that account's
Devices. It covers Published Revision History, Skill Extra Data, Skill Tag
Assignments, and the Synced Tag Vocabulary, including deletions and mistakes.
_Avoid_: Backup, sharing, publish, upload

**Cloud Library**:
The set of live Cloud Lineages in one Cloud Account. A Skill on a Device is
synced exactly when its Managed Skill ID is linked to a Cloud Lineage in the
Cloud Library.
_Avoid_: Marketplace catalog, team catalog, cloud drive

**Cloud Lineage**:
The server-minted, account-scoped identity of one synced Skill. It is mapped to
one Managed Skill ID per Device, and that mapping exists only inside
`skills_cloud`. It survives Source Replacement, which advances its Lineage
Generation.
_Avoid_: Managed Skill ID, Source Lineage, Slot Key, Git object ID

**Lineage Generation**:
The ordinal of a Cloud Lineage's current history root. Source Replacement starts
a new Generation. Publish, Update, Restore Publish, and Sync Merge do not.
_Avoid_: Version, revision number

**Lineage Head**:
The server-authoritative selection for one Cloud Lineage Generation: its
Effective commit, Upstream commit, Head Pack, Portable Source, and Declared
Skill Name. Within a Generation, the Effective commit only moves to its own
descendants.
_Avoid_: Git branch, ref, latest version

**Revision Pack**:
A standard Git pack file that carries revision objects between a Device and the
service. A Device writes and indexes it locally. The service stores it in object
storage, accessible only through the HTTPS API. The service runs no Git server.
_Avoid_: Revision Recovery Bundle, Git push, archive, repository

**Head Pack**:
The Revision Pack that backs one Lineage Head. It holds the complete closure of
the head's Effective and Upstream commits, so one Head Pack alone materializes
the head. Every Upload sends a new one.
_Avoid_: Incremental pack, delta, backup

**Commit Graph**:
The service's record of each verified commit and its parents within one Cloud
Lineage Generation. Rows come only from verified Revision Packs, and Head
Advance checks ancestry against them.
_Avoid_: Git refs, Published Revision History, Revision Store

**Pack Verification**:
The service-side check that indexes a Revision Pack, recomputes every object ID,
and confirms that the closure of the named commits is complete. A pack backs a
Lineage Head or a Release only after it passes.
_Avoid_: Virus scan, content review, checksum only

**Head Advance**:
The guarded API transaction that moves a Lineage Head from an expected Effective
commit to a descendant. It names the verified Head Pack that contains the new
head. Head Advance is the server-side Business Commit Point, and a stale
expectation is rejected without effect.
_Avoid_: Git push, force push, upload

**Upload**:
The Device-side work of exporting a Head Pack, sending it to the HTTPS API, and
then requesting a Head Advance.
_Avoid_: Publish, Release, sync, push

**Reconciliation**:
The repeatable comparison of a Device's committed local state with the server's
committed state. It decides what to fetch, apply, merge, or Upload without
consulting stored operation history, and running it again is always safe.
_Avoid_: Replay, retry queue, exactly-once delivery, outbox

**Fast-forward Apply**:
The Reconciliation outcome in which the local Effective Revision is an ancestor
of the Lineage Head. The Device applies the head without asking and without
creating a commit.
_Avoid_: Update, merge, download

**Divergence**:
A Lineage Head and a local Effective Revision that share a common ancestor
while neither contains the other, for example after two Devices published while
offline.
_Avoid_: Conflict, Drift, Update Conflict

**Sync Merge**:
The three-way merge from the real common ancestor that resolves a Divergence.
A clean, valid Sync Merge publishes automatically and is Uploaded. A conflicting
Sync Merge becomes an Update Candidate Session attributed to the other Device.
_Avoid_: Update, rebase, last-writer-wins content

**Field Version**:
The server-assigned version of one synced metadata value: a Favorite, a Note, a
Skill Tag Assignment, or a tag name. Writes compare and set against it.
_Avoid_: Timestamp, Repository Revision

**Note Conflict**:
Two different Note texts written from the same Field Version. Both texts are
kept until the user chooses one or combines them.
_Avoid_: Metadata conflict, merge

**Synced Tag Vocabulary**:
The account-wide set of Personal Tags shared by every Device with Personal Sync
enabled. It holds at most one tag per normalized name.
_Avoid_: Marketplace Tag, category, device-local tag list

**Portable Source**:
The device-independent form of a Source Descriptor that Personal Sync stores.
Git, Well-known, and Cloud Release Sources are portable unchanged. Device-Bound
Sources are reduced to their source type, their Origin Device, and a display
label, without any path.
_Avoid_: Source locator, absolute path

**Device-Bound Source**:
A Local or Adopted Snapshot Source, whose locator exists only on one Device's
filesystem.
_Avoid_: Unsupported source, local-only Skill

**Origin Device**:
The Device whose filesystem holds a Device-Bound Source. Only the Origin Device
can check that Source for updates.
_Avoid_: Primary device, owner device

**Synced Origin Source**:
The Workspace provenance that non-origin Devices record for a Skill with a
Device-Bound Source. It explains where the Skill came from, and the Skill
receives new revisions only through Personal Sync.
_Avoid_: Local Source, Adopted Snapshot Source

**Account Change Feed**:
The per-account, monotonically sequenced list of entities whose committed state
changed. It carries entity identities and versions, not payloads, and keeps
only the latest entry per entity.
_Avoid_: Event log, operation history, inbox

**Feed Check**:
One read of the Account Change Feed from a Device's cursor. A check that finds
nothing new returns an empty result. A Feed Check only triggers Reconciliation
for the entries it returns and is never applied as state.
_Avoid_: Push notification, realtime update, Git poll, sync event

**Device Exclusion**:
A device-local choice not to materialize one Cloud Lineage on that Device. It
leaves the Cloud Library and every other Device unchanged.
_Avoid_: Stop Syncing, Removal, unsync

**Stop Syncing**:
The explicit removal of a Cloud Lineage from the Cloud Library. Every Device
keeps its local Skill as Device Only, and the server deletes the Lineage's
Revision Packs and Commit Graph after its grace period.
_Avoid_: Removal, Device Exclusion, Revocation

**Synced Removal**:
A Skill Workspace Removal of a synced Skill, replicated as a Cloud Lineage
tombstone so that every Device performs Removal.
_Avoid_: Stop Syncing, delete from cloud only

**Sync Status**:
The per-Skill status derived from local and server state: Device Only, Synced,
Waiting to Upload, Applying, or Needs Attention. It is never stored as
authority.
_Avoid_: Sync state machine, pending flag

**Attention Reason**:
The typed cause of a Needs Attention status. Each reason defines the user
actions that resolve it.
_Avoid_: Pending reason, error code, warning

### Distribution

**Distribution**:
The explicit delivery of immutable Skill versions from a Principal to an
audience. Individual Sharing, Team Distribution, and the Marketplace are its
three forms.
_Avoid_: Sync, visibility toggle, publish

**Channel**:
A stream of Releases of one Skill. It is owned by one Principal and readable by
its Grants.
_Avoid_: Cloud Lineage, repository, Listing, package

**Release Pack**:
The Revision Pack of one Release: its Release commit and that commit's closure,
which reaches only earlier Releases of the same Channel. Every object in it is
reachable from the Release commit. It never holds Effective, Upstream, Draft,
or Local Customization history.
_Avoid_: Head Pack, mirror, fork, archive

**Release**:
An immutable, versioned commit in a Channel, created by a deliberate Release
action from one chosen revision. Its tree equals the chosen revision's tree, and
its ancestry contains only earlier Releases of the same Channel.
_Avoid_: Publish, Effective Revision, Git tag, upload

**Version Label**:
The publisher-chosen name of a Release, unique within its Channel, such as
`1.2.0`.
_Avoid_: Release identity, Repository Revision

**Release Manifest**:
The canonical description of one Release: Channel, Release, Version Label,
tree, content hash, publisher, and creation time. A publisher signature covers
it, and a signature is required before a Public Grant.
_Avoid_: Changelog, Listing

**Grant**:
Permission for an audience to read a Channel's available Releases. A Grant is a
Person Grant, a Team Grant, or the Public Grant.
_Avoid_: Visibility, share link, ACL entry

**Share**:
A Person Grant on a Channel owned by a Cloud Account. The recipient signs in and
receives every Release the owner makes on that Channel until the Grant is
revoked.
_Avoid_: Link, send, copy

**Revocation**:
Ending a Grant or a Membership. It stops future fetches and update checks but
cannot recall delivered content.
_Avoid_: Withdrawal, Removal, deletion

**Withdrawal**:
Marking one Release unavailable for new installs and fetches. Owners and
Publishers withdraw their own Channel's Releases. Marketplace Moderators
withdraw any public Release.
_Avoid_: Revocation, Removal, unpublish

**Cloud Release Source**:
The credential-free Source Descriptor variant that identifies one Channel by
service origin and Channel ID. Its Upstream Revisions are Releases.
_Avoid_: Git Source, Marketplace catalog entry, Share

**Listing**:
The public catalog presentation of a Channel that has the Public Grant: purpose,
publisher, Version Labels, and Ratings.
_Avoid_: Channel, Release, search result

**Public Index**:
The Agent Skills discovery index (`/.well-known/agent-skills/index.json`,
schema 0.2.0) that the service publishes for Channels with the Public Grant. It
lists each Channel's latest available Release as an archive with its digest, so
any Agent Skills client can install it.
_Avoid_: Listing, catalog, `marketplace.json`

**Report**:
A user's complaint about a Listing or a Release, which a Moderator reviews and
which can lead to Withdrawal.
_Avoid_: Rating, issue, flag

## Relationships

### Identity

- A Cloud Account has zero or more Devices. A Device holds at most one Cloud
  Session per service origin.
- A Device obtains its Cloud Session only through Device Authorization. The App
  never collects a password, OTP, or third-party credential, opens no loopback
  listener, and registers no custom URL scheme. While waiting for approval it
  polls only the authorization endpoint, at the interval the service sets.
- A Cloud Session is sent only to the HTTPS API. Revision Packs upload and
  download only through that API, authorized by the session plus ownership or a
  current Grant at request time. There are no content tokens or signed storage
  URLs.
- A Cloud Session never enters Source Descriptors, SQLite, Revision Store
  configuration, Operation Records, URLs, or logs.
- A Team has at least one Owner. Access to a Team's Channels follows Membership
  at request time.

### Personal Sync

- A Cloud Lineage belongs to exactly one Cloud Account and maps to at most one
  Managed Skill ID per Device.
- Linking an existing local Skill to a Cloud Lineage happens automatically only
  on an exact Portable Source, Slot Key, and content match.
- Each Cloud Lineage Generation has its own Revision Packs and Commit Graph,
  readable only by the owning account. A new Generation starts empty, and the
  former Generation's packs and Commit Graph are deleted after its grace period.
- The service database is authoritative for Lineage Heads and the Commit Graph,
  and Revision Packs are authoritative for bytes. An Upload sends a Head Pack
  before the Head Advance. Sending the same pack again is safe, because packs
  are addressed by digest.
- A Revision Pack is kept while a Lineage Head references it, plus a short grace
  for transfers in flight. Every other pack is deleted.
- Head Advance accepts only a descendant within one Generation, and only with a
  verified Head Pack that contains the new head. A Generation change is a
  separate explicit transaction that represents Source Replacement.
- Reconciliation compares each local Effective Revision L with its Lineage Head
  R:
  - L equals R: nothing to do;
  - L is an ancestor of R: Fast-forward Apply;
  - R is an ancestor of L: Upload, with a Head Advance that expects R;
  - otherwise: Divergence, resolved by a Sync Merge.
- Pending local work is derived, never queued: a local revision is waiting
  exactly when its Lineage Head does not contain it, and a field is waiting
  exactly when its local value differs from the value at its Field Version.
- A lost response resolves at the next Reconciliation, which reads the committed
  server state. Client correctness never depends on retrieving a stored receipt.
- Remote state changes an Effective Revision, Skill Extra Data, a Skill Tag
  Assignment, or a Skill's existence only through a local Skill Workspace
  transaction.
- A Dirty Draft or an Update Candidate Session blocks incoming content for that
  Skill only. Other Skills keep syncing.
- Fast-forward Apply and a clean, valid Sync Merge apply without asking. A
  conflicting Sync Merge uses the existing conflict review.
- If one Upstream commit descends from the other during Divergence, the
  descendant is kept. Otherwise the Upstream commit already in the Lineage Head
  is kept, and the other Device's content survives through the Sync Merge.
- Synced Removal and Generation changes apply automatically unless a Dirty Draft
  or an Update Candidate Session exists.
- Favorites, Skill Tag Assignments, and tag names are written by compare-and-set
  on their Field Version and settled in server acceptance order without asking
  the user. Notes settle the same way unless the result is a Note Conflict.
- Creating a tag whose normalized name already exists returns the existing tag.
  Renaming a tag onto an existing name merges its assignments into the existing
  tag. Deleting a tag wins over a concurrent assignment.
- Drafts, Activations, Project Roots, Agent Detection evidence, Repository
  Copies, Translation Cache, operation recovery artifacts, and credentials never
  sync. Activation sync is deferred.
- A newly signed-in Device materializes every Cloud Lineage in the Cloud
  Library except its Device Exclusions. It creates no Activations, then offers a
  one-time activation step.
- The Origin Device keeps its original Device-Bound Source. Other Devices record
  a Synced Origin Source. No absolute path leaves the Origin Device.
- A Device runs a Feed Check on launch, on returning to the foreground, on
  reconnecting, on waking from sleep, and every 2 minutes while the App runs.
  The service can lengthen that interval, and failures back off. A Device that
  someone is looking at therefore reconciles at once. An unattended Device
  waits at most one interval.
- Personal Sync has no realtime channel. It is not live editing, and
  Reconciliation is the same whatever triggers it.
- A Device downloads a Head Pack only for Lineage Heads whose Account Change
  Feed entry changed. Pack storage is never polled.
- Pack Verification means every Lineage Head on the server can be downloaded
  completely, so a damaged cloud copy is not an Attention Reason.
- A Device that returns after its tombstone retention has lapsed must reset:
  each linked Skill missing from the Cloud Library becomes Needs Attention
  instead of being re-uploaded automatically.

### Attention Reasons

Every Sync Status other than Synced and Device Only either clears by itself
when connectivity returns or carries an Attention Reason with defined actions. A
state with neither is a defect.

| Attention Reason | Resolving actions |
| --- | --- |
| Incoming change waits behind a Draft | Publish the Draft, which then Sync Merges; review the incoming difference; discard the Draft |
| Sync Merge conflict | Resolve in the existing conflict review, including keep-this-Device and keep-other-Device shortcuts |
| Note Conflict | Keep one text or combine both |
| Skill Slot occupied by a different local Skill | Replace the local Skill with the synced one; keep the local Skill and add a Device Exclusion |
| Removed on another Device while a Draft exists here | Remove here too; keep it here as Device Only |
| Source replaced on another Device while this Device has unsynced revisions | Accept the replacement; keep this Device's copy as Device Only |
| Missing from the Cloud Library after a reset | Remove here; keep it here as Device Only; Upload it as a new Cloud Lineage |

Account-level conditions are separate from Attention Reasons and are shown once
for the Device: sign-in required, Device revoked, and storage limit reached.

### Distribution

- A Channel is owned by exactly one Principal and has zero or more Grants. A
  Release reaches every current Grant of its Channel.
- A Cloud Account owns at most one Channel per Skill. When that Skill is synced,
  the Channel is bound to its Cloud Lineage, so any of the owner's Devices can
  create Releases. Otherwise the Channel is bound to the creating Device's
  Managed Skill ID.
- Before creating a Release, the publisher sees the chosen revision, its file
  manifest, and the Channel's current Grants.
- The publisher's Device builds the candidate Release commit and uploads its
  Release Pack. The service accepts the pack only when it passes Pack
  Verification, its tree matches the Release Manifest, its parent is the
  Channel's previous Release (if any), and every object is reachable from the
  Release commit. This works the same whether or not the Skill is synced.
- Accepted Release Packs are never rewritten. Only the service decides what
  enters a Channel.
- Notes, Personal Tags, Drafts, and private revision history never enter a
  Release Pack.
- A recipient installs a Release through the ordinary source-agnostic install
  flow with a Cloud Release Source. The flow reviews purpose, publisher,
  Channel, and Version Label first. Existing Skill Slot occupants follow the
  existing takeover and replacement rules.
- A newer Release becomes the next Upstream Revision through ordinary Update, so
  the recipient's Local Customization is preserved and conflicts become an
  Update Candidate Session.
- New Releases appear on the recipient's Account Change Feed. Update checks
  compare the content hash of the Channel's latest available Release.
- After Revocation or leaving a Team, installed copies remain and their Cloud
  Release Source becomes Source Unavailable.
- A Withdrawn Release accepts no new installs or fetches. Installed copies show
  their withdrawn state and are never deleted automatically. The update target
  becomes the latest available Release.
- Every Team Release, Withdrawal, Grant change, and Membership change is
  attributed to its actor in the Team's audit history.
- Only Channels with the Public Grant enter the Public Index, search, Listings,
  Ratings, Reports, and moderation. A Public Grant requires signed Release
  Manifests. Private synced content never enters any of them.
- The Public Index has one entry per public Channel, for its latest available
  Release, and a Withdrawn Release leaves it at once. An index digest proves
  integrity, not publisher authenticity, so SkillDeck installs public Releases
  through a Cloud Release Source, where signatures, Withdrawal, and updates
  apply.
- A Skill installed from a Channel can itself be synced. Its Head Packs hold the
  recipient's own copy, which Revocation does not delete.

### Boundary with Skill Workspace

- `skills_cloud` uses only these Workspace seams:
  - exporting a Revision Pack of a managed Skill's named revisions to a file
    that `skills_cloud` supplies;
  - importing a Revision Pack file into non-authoritative staging, which
    verifies every object and the completeness of the named revisions, and
    reports imported, malformed, or incomplete;
  - applying staged remote state in one Workspace transaction (the Sync apply
    contract);
  - a committed-change feed;
  - Cloud Release Source and Synced Origin Source provenance.
- The Sync apply contract is guarded by the expected local Effective Revision.
  It reports no change, fast-forwarded, merged, conflicted, Draft resolution
  required, or Skill Slot occupied.
- Skill Workspace knows nothing of Cloud Accounts, Cloud Lineages, Channels,
  Grants, Field Versions, Sync Status, or credentials. It performs no cloud
  network I/O and never sees a cloud URL. `skills_cloud` moves every Revision
  Pack over HTTPS itself.
- `skills_cloud` keeps its own credential-free store of the Cloud Lineage to
  Managed Skill ID mapping, Device Exclusions, the Account Change Feed cursor,
  Field Versions with their last agreed values, and unresolved Note Conflicts.

## Example dialogue

> **Dev:** "I published a Skill on my laptop while offline. Where is the
> pending change stored?"
> **Domain expert:** "Nowhere extra. The Publish created an Effective Revision
> that the Lineage Head doesn't contain yet. The next Reconciliation sees that
> and Uploads it."

> **Dev:** "When I share that Skill with a colleague, do they get my history
> and Notes?"
> **Domain expert:** "No. Sharing creates a Release in your Channel. Its Release
> Pack holds only Release commits, and the service rejects any object that the
> Release commit can't reach. Your history, Notes, and Drafts stay in your own
> Head Packs."

> **Dev:** "So the service hosts Git repositories?"
> **Domain expert:** "No. It stores Revision Packs and a Commit Graph. Devices
> build and index the packs locally, and the database decides which commit is
> the head."

> **Dev:** "What happens to their copy if I revoke the Share?"
> **Domain expert:** "They keep it. Its Cloud Release Source becomes Source
> Unavailable, so they get no further Releases."

## Flagged ambiguities

- **Publish** keeps its Skill Workspace meaning: a local transition that creates
  an Effective Revision. Sending revisions to the service is an **Upload**, and
  making a version available to other people is a **Release**. Never say
  "publish to the cloud".
- **Revision Pack** is not a **Revision Recovery Bundle**. Both use Git packs. A
  Revision Recovery Bundle is device-local recovery evidence in the Skill
  Workspace. A Revision Pack is cloud transfer content, and it never stands in
  for a Device's recovery material.
- **Retention Ref** keeps its Skill Workspace meaning, a local derived ref.
  The service has no refs.
- **Personal Sync is not Backup.** It replicates deletions and mistakes.
  Recovery relies on local Published Revision History, Restore Publish, and the
  tombstone window.
- Five different "stop" actions:
  - **Stop Syncing** leaves local copies everywhere;
  - **Synced Removal** removes the Skill on every Device;
  - **Device Exclusion** affects one Device only;
  - **Revocation** ends access for other people;
  - **Withdrawal** retires one Release.
- **Cloud Lineage** and **Source Lineage** differ. A Source Lineage is device
  local and ends at Source Replacement. A Cloud Lineage spans Devices and
  survives Source Replacement by advancing its Lineage Generation.
- **Personal Tag** is device-local in the Skill Workspace context until
  Personal Sync is enabled. From then on, tags belong to the Synced Tag
  Vocabulary.
- **Conflict** has several meanings: an Update Conflict (Skill Workspace), a
  conflicting Sync Merge (presented as an Update Candidate Session), a Note
  Conflict, and an occupied Skill Slot. Name the specific one.
- **Divergence** is not **Unresolved Drift**. Drift is a local projection
  mismatch and never syncs, because Upload reads only Effective Revisions.
- **Share** means a Person Grant. Anonymous share links are not part of the
  first Sharing release.
- **Device** is never an **Agent**. Activations stay per Device even when every
  Skill syncs.
