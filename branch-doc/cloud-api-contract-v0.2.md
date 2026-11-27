# SkillDeck Cloud API contract v0.2: Personal Sync metadata

Status: Accepted for M6 implementation on 2026-11-27, following the maintainer's
plan approval. Implements T33 (service) and T34 (client and App). This replaces
the earlier draft's Note history proposal. v0 and v0.1 remain supported.

## Decisions and boundaries

- Favorites, tag assignments, tag names and colors use Field Version CAS and
  converge in server acceptance order. This includes recovery retries, not
  device wall-clock ordering.
- Notes compare current text with incoming text. Equal values converge. A
  differing concurrent value is retained alongside the current value for an
  explicit choice. No indefinite Note history or processed-edit ledger exists.
  Rare delayed/lost responses may require another conflict review.
- Vocabulary is global to the Workspace. A synced tag rename, recolor or delete
  also changes references on Device Only Skills. Account mappings remain separate.
- At first association, cloud-edited Favorite/Assignments win; untouched cloud
  fields accept existing local values. New installs use cloud metadata.
- Old local tags enter the account vocabulary when used by synced Skills.
  Tags created after connection enter the current account vocabulary. An explicit
  login/account switch treats previously unknown unmapped tags as old tags;
  this account's already-eligible pending tags and a resumed session keep their
  offline changes. Other accounts' new tags are not silently
  imported on switching back.
- Note maximum: 4 KiB of UTF-8 after normalization. Tag display name maximum:
  64 Unicode scalar values. Maximum 256 live tags per account.
- Tokens, server IDs, Field Versions and conflict policy stay outside Workspace.
  Workspace receives only local identifiers, values and a local revision guard.

## Common rules

Paths are under `/v0/`. Existing bearer-only authorization, origin restriction,
`Cache-Control: no-store`, JSON content type, error redaction and Retry-After
handling apply. Metadata requests have a 32 KiB encoded-body cap; this permits
JSON escaping of a valid 4 KiB Note. Oversized/malformed bodies are invalidRequest.
Metadata-inclusive library pages have a 2 MiB encoded JSON response cap, below
the existing client's 4 MiB cap. Count limits are upper bounds, not exact sizes.

IDs use `[A-Za-z0-9_-]{1,64}`. Field Versions and aggregate versions are
nonnegative JSON safe integers and never decrease. Matching values are no-ops:
no new Field Version or Feed entry. Resource lifecycle and account ownership
are checked before no-op handling. Unknown request fields are invalidRequest;
unknown response fields and Feed kinds are ignored by older clients.

| HTTP | error | Additional fields / meaning |
|---|---|---|
| 400 | invalidRequest | Invalid shape, identifier, query, value or encoded body |
| 401 | unauthorized | Missing, expired or revoked session; follow v0 session clearing |
| 403 | storageLimitReached | Account or live-tag quota; duplicate-name creation remains allowed |
| 404 | notFound | Unknown or foreign entity; metadata before first Head Advance is unavailable |
| 409 | staleFieldVersion | `current`: the current endpoint response object |
| 409 | noteConflict | `current`: Note including its open conflict |
| 409 | noNoteConflict | `current`: Note without a conflict |
| 410 | lineageEnded | `lineage`: v0.1 Lineage |
| 410 | tagDeleted | The logical tag was deleted, including creation-key retries |
| 410 | tagMerged | `replacementTagId`: current canonical tag ID |
| 413 | metadataTooLarge | `field`: `note` or `name` |
| 429 | rate_limited | Optional Retry-After, as v0.1 |
| 503 | server_error | Transient service failure; optional Retry-After |

Every endpoint admits 400, 401, 429 and service failures. Writes that need added
storage admit 403. The endpoint tables add lifecycle and CAS errors. Expected
errors expose no raw database/platform text. Public error toString/logging must
not disclose Note text, tag names, device descriptions or credentials.

## Objects

A Lineage's metadata follows its identity across content Generation changes.
It becomes readable after the first Head Advance. Defaults are created lazily
or backfilled equivalently; no default metadata Feed entry is required.

```json
{
  "lineageId": "lineage-id",
  "version": 0,
  "favorite": {"value": false, "version": 0},
  "note": {"value": null, "version": 0, "device": null, "conflict": null},
  "assignments": {"version": 0, "items": []}
}
```

`version` increases for any visible metadata change. Favorite and Note each have
an independent Field Version. `assignments.version` increases for any membership
change, including tag deletion/merge, and distinguishes untouched from explicitly
cleared assignments during initialization. Its `items` list includes only true
memberships, each `{ "tagId": "id", "version": 1 }`, in stable tag-ID order.
Individual membership CAS still uses that membership's version. Unassigned
memberships retain their versions while the Lineage and tag are live.

An `Assignment` response is `{ "tagId": "id", "assigned": false, "version": 0 }`.
The default nonexistent live-tag membership has version 0.

A Note is `{value,version,device,conflict}`. `value` is normalized text or null.
`device` identifies the last accepted value's device, using v0.1's nullable
`{name,platform}` description; it is null for an untouched Note. An open conflict
is the following pair, with no historical-base lookup:

```json
{
  "accepted": {"text": "Current cloud text", "device": {"name": "Mac A", "platform": "macos"}},
  "incoming": {"text": "Incoming local text", "device": {"name": "Mac B", "platform": "macos"}}
}
```

Candidate text may be null, representing a clear. The current `note.value` stays
at the accepted candidate while the conflict is open. The Note's Field Version
changes when a conflict opens or resolves and is the guard for resolution.

A live Tag is `{tagId,name,normalizedName,color,version,nameVersion,colorVersion}`.
The three versions start at 1. Name and color writes compare their separate
versions; deletion compares the aggregate tag version. Assignments do not change
that tag version. Color is null or `#RRGGBB`, with case-insensitive input and
uppercase output. Vocabulary is `{version,tags:[Tag,...]}`, initially version 0,
with live tags in stable ID order.

## Normalization

Match Workspace's `library_mutation_planner.dart` helpers: display name is NFC
of Dart-trimmed text, nonempty and without NUL; normalizedName is NFKC followed
by locale-independent uppercase. Note text uses Dart trim, preserves internal
whitespace/case, rejects empty non-null values, and uses null for clearing.

Worker uses Unicode 17 normalization/case behavior and the exact Dart trim
character set. Shared vectors cover accents, compatibility forms, uppercase
expansion, CJK, supplementary characters, U+0085 and empty/invalid inputs.
Measure limits after normalization. Reject an over-limit write without mutation.

## Skill metadata endpoints

Paths below are relative to `/v0/lineages/{lineageId}/metadata`.
Each admits 404 notFound and 410 lineageEnded in addition to common errors.

| Method/path | Request | Success | Additional errors |
|---|---|---|---|
| GET base | — | 200 LineageMetadata | — |
| GET /favorite | — | 200 Favorite | — |
| PUT /favorite | `{expectedVersion,value:bool}` | 200 Favorite | 409 staleFieldVersion |
| GET /assignments/{tagId} | — | 200 Assignment | 410 tagDeleted/tagMerged |
| PUT /assignments/{tagId} | `{expectedVersion,assigned:bool}` | 200 Assignment | 409 staleFieldVersion; 410 tagDeleted/tagMerged |
| GET /note | — | 200 Note | — |
| PUT /note | `{expectedVersion,value:string-or-null}` | 200 Note | 409 staleFieldVersion/noteConflict; 413 metadataTooLarge |
| POST /note/conflicts | `{expectedVersion,value:string-or-null}` | 200 Note | 409 staleFieldVersion/noteConflict; 413 metadataTooLarge |
| POST /note/resolve | `{expectedVersion,value:string-or-null}` | 200 Note | 409 staleFieldVersion/noNoteConflict; 413 metadataTooLarge |

### Notes

A normal PUT at the current version updates the value and device. A stale PUT
with the same current value is a no-op; otherwise it returns staleFieldVersion.
It never clears an open conflict. During an open conflict, an ordinary retry of
either candidate returns the current conflict without mutation; another text
returns noteConflict.

After observing differing pending local and current cloud text, the client POSTs
`/note/conflicts` against the currently observed Note version. A stale expected
version returns staleFieldVersion; an equal current value is a no-op. With no
conflict, success stores current and incoming candidates and advances versions.
With an open conflict, repeats of either candidate are no-ops; a third distinct
text returns noteConflict and stays in its local Workspace.

Resolution CAS compares the open conflict version, sets the chosen/combined
value and resolving device, clears candidates and advances versions. A stale
resolution returns staleFieldVersion. If already resolved to the requested
current value, a retry is a no-op. No conflict plus a different value returns
noNoteConflict; it does not create an unreviewed replacement.

The App shows any distinct pending third local text alongside the server pair.
A user's merged/selected text is saved locally with the reviewed local guard;
server-resolution failure preserves that text and a review/retry action.
An old response cannot acknowledge a newer local edit. No indefinite accepted
edit history or resolution receipt is retained. Delayed retries can form a new
current/incoming conflict, but cannot silently discard unreviewed text.

## Vocabulary endpoints and creation identity

| Method/path | Request | Success | Additional errors |
|---|---|---|---|
| GET /v0/tags | — | 200 Vocabulary, including empty | — |
| GET /v0/tags/{tagId} | — | 200 Tag | 404 notFound; 410 tagDeleted/tagMerged |
| POST /v0/tags | `{clientKey,expectedVersion:null,name,color}` | 201 created Tag / 200 existing canonical Tag | 410 tagDeleted; 413 metadataTooLarge |
| PUT /v0/tags/{tagId}/name | `{expectedVersion,name}` | 200 surviving Tag | 404; 410 tagDeleted/tagMerged; 409 staleFieldVersion; 413 metadataTooLarge |
| PUT /v0/tags/{tagId}/color | `{expectedVersion,color}` | 200 Tag | 404; 410 tagDeleted/tagMerged; 409 staleFieldVersion |
| POST /v0/tags/{tagId}/delete | `{expectedVersion}` | 200 `{tagId}` | 404; 410 tagMerged; 409 staleFieldVersion |

`clientKey` is 64 lowercase hexadecimal characters, deterministically derived
by the App's existing installation HMAC seed and local tag identity. It contains
no user text or path, is scoped by account on the server, and is recoverable
without a creation receipt. An explicit new local tag has a new identity/key.

Create records a stable client-key alias even when it returns a preexisting
normalized-name tag. Look up this alias before creating a tag: a retry after
rename/merge returns the current canonical Tag, and a retry after deletion
returns tagDeleted. It must not create an orphan tag under the old name.
A name collision preserves the preexisting canonical name/color.

Rename uses nameVersion. Rename onto another tag atomically unions assignments
into the existing destination, preserving its identity/name/color, and ends the
source identity with a redirect. Recolor uses colorVersion. Delete uses tag
version, removes all memberships and wins over concurrent assignment; new tags
with reused names receive new identities. Repeated delete is successful while
its explicit deletion tombstone is available.

Keep compact creation-key aliases and ended identity markers for the account's
life, following merges to their canonical target. They contain no historical
name/color payload. Ended tag private payload is removed no later than 90 days;
ordinary expired tag lookups may answer notFound, but an old creation-key retry
still cannot resurrect the deleted logical tag. Account deletion removes these
records too; implementing the account-deletion feature is outside T33/T34.

## Feed, pagination and migration

Add `metadata` (id=lineageId, version=metadata.version) and `tagVocabulary`
(id=`vocabulary`, version=vocabulary.version) to the existing Account Change
Feed. Keep the latest entry per `(kind,id)`, ordered by the shared account
sequence. Every visible mutation, its versions and affected Feed entries commit
atomically in the same account shard. Tag merge/delete also advances every
affected live Lineage's assignment/metadata versions and Feed position.

Migrate account_feed to `(account,kind,id)` without changing existing lineage
sequences or cursor meanings. Older clients continue skipping unknown kinds.
There is no new realtime channel or polling of pack storage.

`GET /v0/library?include=metadata&cursor=...&limit=...` returns the existing
lineages/next/feedCursor plus paired `metadata` and `tagVocabulary` (full on
first page, null later). Include only live Lineages with a head. Preserve one
initial replay cursor across pages, bind paging cursors to their projection,
and reject a projection mismatch. Default v0.1 library shape is unchanged.

Stop a page before its encoded JSON exceeds 2 MiB, including metadata and
vocabulary; return a continuation after the last included row. Do not omit rows
or advance a cursor over a row that was not returned. The initial feedCursor is
a replay lower bound, not a multi-page database snapshot. Refresh vocabulary
before applying assignment IDs it does not yet know.

When upgrading an already running content sync, metadata bootstrap does not
advance past the existing content Feed cursor. Continue from that cursor after
initialization. A cursor-expired response follows the full reset path for both
content and metadata. Restart an expired library listing once, as in v0.1.

## Client initialization, recovery and local apply

Remember per-field agreed values/versions, account-scoped tag mappings,
vocabulary observations and unresolved Note conflicts in Cloud's state store.
Old state files without metadata fields remain valid and require initialization.
No field operation outbox is added. Normal retry behavior compares current
local and remote state, not original click timestamps.

- A newly installed Skill starts from remote values.
- For an existing Skill without metadata baselines, Favorite and Assignments
  take cloud values when their versions exceed zero; otherwise local values may
  initialize them by CAS. Empty local defaults do not clear existing cloud Notes.
- Nonempty local Notes differing from an edited cloud value, including a clear,
  retain both through the conflict flow. Equal text settles without conflict.
- Import old tags only after deciding which assignments are retained. Other
  unmapped local tags stay local. Explicit account login/switch establishes the
  known local-tag baseline without dropping this account's existing pending
  eligibility; subsequent new tags belong to the current account.
- After network responses, reread local values before acknowledging them. New
  edits remain pending. State recovery cannot silently overwrite a differing Note.

Extend RemoteSkillMetadata and RemoteTagVocabulary with optional
`expectedRepositoryRevision`, the revision of the local read. Cloud supplies it
on every apply. A mismatch returns staleSnapshot without mutation or journal;
the normal transaction guard also protects the later lock/commit window.
Existing callers omitting it retain their prior behavior. Keep expectedEffective
for Skill metadata. No server Field Version enters Workspace. Offline permutations of mapped tag
names use the atomic local `RemoteTagVocabulary.renameMany` variant described
in M5, preserving tag IDs and assignments rather than accidentally merging
two distinct cloud tags during sequential application.

Content and metadata attention are independent. Note Conflict, over-limit Note,
and tag correction conditions have visible resolving actions but do not hold
other fields/Skills indefinitely. Transient failures retain retryable state and
honor Retry-After. Known quota failures retry after recovery without a new edit.

GET /v0/tags returning 404 means an older service: continue content sync, expose
metadata-unavailable status and retry discovery on later checks. Authentication
and transient transport failures are not interpreted as missing support.

## Ending and acceptance

Synced Removal/Stop Syncing end metadata writes and remove that Lineage's cloud
metadata, assignments and conflicts atomically. Existing v0.1 tombstone/pack
retention remains. Stop Syncing keeps local metadata; the shared vocabulary
survives. Source Generation changes preserve metadata.

Acceptance covers local UI/CLI edits in the read/apply window; first association,
upgrade and state recovery; lost create response followed by rename/merge/delete;
two- and three-device Note conflicts; lost conflict/resolution responses; maximal
escaped payloads and complete bounded pagination; offline/restart/account switch;
old/new client-service compatibility; and simultaneous content/Note attention.
Run actual workerd/D1/R2 and two real temporary Workspaces, not only fake services.
No deployment, production migration or real email sending is implied by this card.
