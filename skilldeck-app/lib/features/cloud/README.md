# Personal Cloud composition

Cloud is disabled by default. `SKILLDECK_CLOUD_ENABLED=true` and a trusted HTTPS
`SKILLDECK_CLOUD_BASE_URL` expose the Settings entry. A disabled/unconfigured
build neither constructs the gateway nor probes a Cloud database, reads the
Keychain or sends a request. An ordinary initial Cloud Settings page also does
none of those actions. Sign-in alone never selects or uploads Skills.

After email/browser verification, users can choose multiple supported local
Git/well-known Skills or Cloud lineages, then confirm one atomic initial scope.
Local filesystem/adopted sources are unsupported; absolute paths never enter
Cloud manifests. Existing source/slot/hash/roots can link to the same lineage.
Missing remote history is imported through a genuine public Workspace
transaction; a different root topology remains pending. Local Extra Data and
same-name/different-ID tags are preserved until their differences are resolved.
The current UI cannot change an existing scope's selected set; adding/removing
selection needs a future explicit rebootstrap/reconciliation flow.

Enable/resume performs a real first sync, then a single scheduler owns periodic
work. It waits 30 minutes with ±20% jitter; failures back off exponentially from
one minute to at most six hours. Foreground wakeups debounce and respect failure
backoff. No runs overlap. Pausing cancels and drains in-flight native/HTTP work,
retains all data and does not remove reconciliation fences. Logout pauses work
before clearing only credentials. Runtime `beforeClose` drains Cloud resources
before the same public Workspace facade closes.

Startup first waits for the existing ready Workspace provider. Only a read-only
background probe of an existing, recognized, enabled Cloud scope permits a saved
session restore. There is no new database creation during this probe. The
restored account/device and current complete Workspace identity must still
match authoritative local scope before scheduling. A paused/no-consent scope
causes no background Keychain read or authentication request. Background errors
update safe state without notification bursts; explicit actions use existing
short typed notifications.

The engine is borrowed from `SkillsManagerRuntime.cloudWorkspaceBackend`; it is
the same public `SkillsRepository` used by the App, never a second Workspace or a
private Store/DB cast. Receive/stage may continue while Agent Root ownership is
blocked, but local apply and new outbound work use non-interactive ownership
checks. Cloud owns accounts, cursors, receipts and tag mappings outside the
engine. All content uses public native Git transfer operations, with ephemeral
RAM-only credentials; there is no HTTP binary PACK upload path.

The Cloud core admits at most four preparation jobs. This App adapter currently
serializes native port preparation/capture/apply because an authoritative-ready
capture excludes active network transfers. It does not weaken readiness or
absence proofs to gain concurrency. Removal uses identity, local-lineage and
writer-enforced clean-Draft checks. Replacement guards the old local lineage and
effective reference before preserving Extra Data and advancing Cloud generation.
Missing cloud objects are repaired only from exact selected local manifests;
there is no implicit Publish, old-lineage revival or replacement of a Draft.

The independent database is
`<application support>/agent_skills/cloud/<origin SHA-256>/cloud.sqlite3`.
SQLite work runs in background isolates. Durable original intents, first-send
24-hour origins, native caller bindings, mappings, control-plane integrity state
and receipt/echo acknowledgements survive restart. Credentials are absent from
SQLite, files, URLs, operation records and logs. Lost/corrupt scope authority
fences sync; authentication and device management remain usable, and no file is
deleted or silently repaired.

`SecureCloudSessionStore` keeps the entire verified session record in one
origin-hashed platform secure-storage value. Its macOS options match Translation
(`usesDataProtectionKeychain:false`). It deletes only that key, preserving other
App credentials and preferences. Tests inject storage and never use the user's
Keychain.

The server's accepted-order metadata LWW rule is unchanged. This client currently
cannot automatically settle an unsent local field edit competing with a remote
value that differs from its confirmed baseline. It preserves the local edit and
leaves that atomic patch pending; it does not invent a merge or silently choose a
publication order. Unknown initial metadata similarly protects local edits.
An unresolved global vocabulary event conservatively pauses vocabulary writes,
while independent Skills continue. Local removal/replacement can retire older
non-unknown conflicts. Unknown native outcomes still require exact caller proof.
Unsupported normalization, slot migration and unsupported sources remain pending
rather than being renamed or coerced.

Validation includes SDK SQLite/HTTP/protocol tests, scheduler/provider/widget
regressions, real multi-Skill service+D1+native integration and macOS debug build.
`build/cloud-visual/` images are widget-rendered fixtures, not installed/device
acceptance. Independent initial-history fixtures exercise public incoming
installs, not ordinary original-source online acquisition. No production
service, real email, user Workspace, user Keychain, deployment, release or
replacement of the running App is part of these checks. Dart's known physical
TLS-handshake socket cleanup limitation is documented in `skills_cloud`; bounded
request cancellation is not claimed as physical socket closure.
