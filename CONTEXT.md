# Skill Workspace

This context manages reusable Agent Skills, their Agent-visible exposure, and the user's private organization of managed Skills on one device.

## Language

**Skill**:
An installable instruction package containing a `SKILL.md` file and any supporting files.

**Agent**:
A tool that discovers and loads Skills from one or more Activation Locations.

**Agent Definition**:
A stable Agent identity with platform-specific detection and Activation Location rules.

**Agent Catalog**:
The combined set of built-in and caller-provided Agent Definitions used by Skill Workspace.

**Agent Detection**:
Evidence that an Agent is present on the device, used for defaults and warnings rather than authorization.
_Avoid_: Activation permission

**Project Root**:
A user-registered directory that defines the boundary for project-scoped Skill discovery and Activation.
_Avoid_: Current working directory, discovered repository

**Managed Skill ID**:
An opaque, stable identifier assigned when a Skill becomes managed and used as the database and revision-history identity for its entire managed lifetime.
_Avoid_: Slot Key, Declared Skill Name, filesystem path, Git object ID

**Skill Slot**:
The device-wide Activation-address position identified by a path-safe Slot Key and occupied by at most one managed Skill.
_Avoid_: Managed Skill identity, Source identity, repository identity

**Skill Extra Data**:
User-owned Favorite and Note data associated with one Managed Skill ID without modifying Skill content, Repository state, or Activations.
_Avoid_: Skill metadata, annotation

**Personal Tag**:
A reusable, device-local label with a stable identity and user-controlled display name, used for private Skill organization and filtering.
_Avoid_: Marketplace Tag, Catalog Category, Skill metadata

**Skill Tag Assignment**:
The association between one Managed Skill ID and one Personal Tag.
_Avoid_: Tag string, Marketplace classification

**Declared Skill Name**:
The original non-empty string from `SKILL.md` frontmatter, preserved for display and source selection but not used directly as a filesystem identity.
_Avoid_: Slot Key, directory name

**Slot Key**:
The lowercase, bounded, path-safe address derived from the Declared Skill Name and used for Repository materialization and Activation directory names.
_Avoid_: Managed Skill ID, database identity, CLI lock key, display name

**Slot Migration**:
The atomic relocation of one managed Skill's Repository materialization and every Activation from its current Slot Key to a new Slot Key after the same Source selection has produced a changed Declared Skill Name.
_Avoid_: New Skill, Source Replacement, inferred rename

**Slot Migration Conflict**:
A blocked Slot Migration whose destination Skill Slot is occupied or whose Source continuity cannot be established. It changes no managed state or filesystem path.
_Avoid_: Partial rename, automatic overwrite

**Repository Copy**:
The stable, path-addressed plain-directory materialization of a managed Skill's current Effective Revision. It contains no Git metadata and is not directly edited or discovered as a Draft.
_Avoid_: Git working tree, Draft Workspace, full revision history, installed Skill

**Draft Workspace**:
The persistent, application-owned ordinary directory containing one managed Skill's unpublished working files. It is materialized from a recorded Draft Base, may be edited by the App or an external editor, and is never exposed through an Activation.
_Avoid_: Git working tree, Repository Copy, Activation target, Current Revision

**Draft Base**:
The immutable Effective Revision from which a Draft Workspace was materialized, reset, or most recently re-anchored after a successful Publish, recorded by an authoritative SQLite Revision Pointer.
_Avoid_: Current Draft bytes, Git index, autosave version

**Dirty Draft**:
A Draft Workspace whose fully rescanned and normalized content differs from its Draft Base.
_Avoid_: File-watcher event, editor dirty flag, Local Customization

**Draft Resolution Required**:
A non-mutating result that blocks source Update, Restore Publish, or Source Replacement until the user publishes or discards a Dirty Draft or resolves an Update Candidate Session.
_Avoid_: Update Conflict, automatic stash, implicit rebase

**Publish**:
The deliberate local transition that validates one consistent content snapshot from a Draft Workspace or an explicitly reviewed drifted artifact, creates an immutable Effective Revision, and synchronizes every local Activation of that Skill as one recoverable operation. It may be requested directly or authorized as the final stage of an explicit source Update, but never pushes or writes back to an external Source.
_Avoid_: Autosave, file write, activate, remote push

**Effective Revision**:
The immutable, device-wide content revision of a managed Skill selected by its latest successful Publish and used by every Activation.
_Avoid_: Draft, project version, activation version

**Restore Publish**:
A user-requested Publish whose new Effective Revision reproduces the tree of a same-name historical revision while extending the current Effective history and preserving the current Upstream Revision.
_Avoid_: Pointer rewind, transaction rollback, source rollback

**Published Revision History**:
The reachable history of every successfully installed, updated, locally published, or restored revision retained in the Managed Skill's current Source Lineage. Source Replacement starts a new history root and permanently deletes the former lineage.
_Avoid_: Operation staging, failed candidate, expanded backup directories

**Upstream Revision**:
An immutable, normalized snapshot imported from a Skill's Source and recorded as the merge baseline for future source updates.
_Avoid_: Git remote, source checkout, Effective Revision

**Local Customization**:
The durable user-owned changes that distinguish an Effective Revision from its Upstream Revision.
_Avoid_: Drift, dirty Repository Copy, source modification

**Unresolved Drift**:
A managed Skill's published Repository Copy or Activation differs from its Effective Revision and awaits explicit user resolution. Its external bytes are preserved; the Snapshot reports `driftPending`.
_Avoid_: Local Customization, Dirty Draft, Revision Store Corruption

**Update Conflict**:
An unresolved conflict produced when the internal Git engine cannot automatically combine a new Upstream Revision with Local Customization. It never changes the current Effective Revision or any Activation.
_Avoid_: Broken Skill, partial update

**Conflict Session**:
The `conflicted` state of an Update Candidate Session, with typed unresolved paths that must be resolved before Publish.
_Avoid_: Independent session type, Git index, Operation Journal

**Update Candidate Session**:
The persistent, resumable state for a conflicted or validation-failed source merge, anchored to its Source Lineage, previous Upstream Revision, previous Effective Revision, incoming Upstream Revision, candidate tree, and Draft Workspace.
_Avoid_: Ordinary Draft, failed transient Update, Operation Journal

**Internal Revision Engine**:
The App-distributed, local-only `libgit2` runtime that stores and merges App-owned revision history without depending on a user-installed Git executable.
_Avoid_: Git Source transport, Source repository, system Git

**Revision Store**:
The canonical isolated bare Git repository owned by the active Source Lineage beneath a Managed Skill ID, containing only that lineage's normalized Upstream, Local Customization, and Effective revision history.
_Avoid_: Source checkout, shared object database, Draft Workspace, published materialization

**Revision Pointer**:
The authoritative SQLite association from one Managed Skill ID and revision role to a `(SourceLineageId, objectId)` revision address.
_Avoid_: Git ref, content bytes, public Skill identity

**Retention Ref**:
A derived internal Git ref that keeps objects reachable for garbage collection and supports recovery or diagnostics, but never determines current business state.
_Avoid_: Revision Pointer, Source Reference, business authority

**Revision Store Corruption**:
A state in which a committed Revision Pointer cannot be resolved to the required valid object in its Revision Store.
_Avoid_: Update Conflict, stale Git ref, automatic fallback

**Revision Recovery Bundle**:
The persistent, integrity-verified recovery artifact that covers one Source Lineage's Published Revision History without becoming revision authority or an off-device backup.
_Avoid_: Revision Store, Operation recovery bundle, export archive

**Control Plane Backup**:
A transactionally consistent, integrity-verified, same-device SQLite snapshot used only to recover relational authority from database corruption.
_Avoid_: Revision Recovery Bundle, off-device backup, Git-derived reconstruction

**Git Source Transport**:
The device's system Git executable used only to acquire content from an external Git Source through the user's existing HTTPS, SSH, and credential-helper environment.
_Avoid_: Internal Revision Engine, revision store

**Current Revision**:
Legacy name for the **Effective Revision**. New domain APIs and documentation use **Effective Revision**.
_Avoid_: New usage

**Repository Revision**:
The monotonic version of one authoritative Repository Snapshot, incremented by any committed Repository state change.
_Avoid_: Current Revision, Skill version

**Source Descriptor**:
The credential-free, type-tagged provenance of the external content selection from which a managed Skill was acquired, including the parameters needed to identify that selection.
_Avoid_: Bare path, credential bundle, Marketplace catalog entry

**Source Lineage**:
The opaque internal lifetime of one Source Descriptor and its Revision Store beneath a Managed Skill ID. Ordinary Updates stay in a lineage; Source Replacement creates a new lineage and retires the former one.
_Avoid_: Managed Skill identity, Slot Key, Git branch, public revision identity

**Source Reference**:
An opaque Git ref string that is resolved again whenever its source is checked or fetched.
_Avoid_: Pinned version, semantic version

**Adopted Snapshot Source**:
Update-ineligible provenance for a Repository Copy created from an External Skill, recording its authoritative original location and content hash.
_Avoid_: Local Source, tracked folder

**Source Unavailable**:
A source state in which the managed Skill can no longer be found or fetched without affecting its local Repository Copy.
_Avoid_: Removed Skill, broken Activation

**Source Replacement**:
An explicitly confirmed, identity-preserving destructive reset that installs a new Source for a Managed Skill ID while permanently deleting the complete previous Source lineage and content history after the Business Commit Point is finalized.
_Avoid_: Update

**External Skill**:
A valid Skill found in an Activation Location that is not backed by a managed Repository Copy.
_Avoid_: Installed Skill, unmanaged activation

**Adoption**:
An explicit operation that creates a Repository Copy from an External Skill and brings its activation under management.
_Avoid_: Discovery, automatic import

**External Conflict**:
Two or more External Skills competing for one Skill Slot while containing different content.
_Avoid_: Duplicate Skill

**Activation**:
The exposure of a Repository Copy through one Canonical Activation Location
that an Agent scans for active Skills.
_Avoid_: Installation, opening

**Activation Takeover**:
An ownership transition that uses an existing Repository Copy as authoritative content, replaces an occupied unmanaged Activation target, and materializes the requested Activation.
_Avoid_: Adoption, drift repair, source replacement

**Stale Activation Takeover**:
An Activation Takeover confirmation whose Repository Revision or occupied-target fingerprint no longer matches the state that the caller reviewed.
_Avoid_: Stale Operation Plan, automatic retry

**Requested Activation Mode**:
The caller's requested activation strategy: symbolic link, copy, or automatic selection.
_Avoid_: Activation Mode

**Activation Mode**:
The concrete symbolic-link or copy strategy that materialized an Activation.
_Avoid_: Automatic, global install mode

**Activation Location**:
A legacy umbrella term for an Agent-scanned Skill directory. New contracts distinguish a Canonical Activation Location from a Compatibility Discovery Location.
_Avoid_: Repository, storage directory

**Canonical Activation Location**:
The single writable location for one supported Agent scope where Skill Workspace creates new Activations and records Activation metadata.
_Avoid_: Compatibility path, every path an Agent scans

**Compatibility Discovery Location**:
A read-only legacy or Agent-specific location inspected for External Skills so they can be explicitly migrated to a Canonical Activation Location.
_Avoid_: Activation target, persisted Activation location, migration destination

**Agent Root Ownership Repair**:
An explicit environmental repair that restores the current user's ownership of reviewed global Agent Skills locations before a Skill Workspace mutation begins.
_Avoid_: Privileged Workspace operation, arbitrary administrator command, permission bypass

**Activation Group**:
The agents that share one Canonical Activation Location and therefore share the same activation state for a Skill.
_Avoid_: Agent toggle

**Removal**:
An explicit operation that deactivates a managed Skill everywhere and deletes its Managed Skill record, Slot state, Source lineages, content history, Draft and Update Candidate state, private per-Skill data, and per-Skill operation history while leaving reusable Personal Tags.
_Avoid_: Deactivation, closing

**Destructive Intent**:
A caller-confirmed Removal or Source Replacement bound to the Repository Revision the caller presented for confirmation.
_Avoid_: Operation Plan, confirmation token

**Stale Destructive Intent**:
A Destructive Intent whose expected Repository Revision no longer matches authoritative state; rejected before planning or mutation.
_Avoid_: Stale Operation Plan, automatic retry

**Operation Plan**:
An internal immutable transaction manifest compiled and automatically applied by a mutation call. It defines ordered changes, rollback responsibilities, progress, and one atomic commit boundary.
_Avoid_: Confirmation screen, public pipeline

**Operation Journal**:
The durable SQLite record written before the first external mutation and updated through each recoverable operation phase, containing enough typed intent and recovery data to choose rollback or roll-forward without inference.
_Avoid_: Debug log, raw command output, best-effort cleanup

**Operation Record**:
The immutable, compact header of one completed Skill Workspace operation, identified by Operation ID and used with Operation Subjects as the business index for operation and version history.
_Avoid_: Git commit, raw Journal steps, localized history text

**Operation Subject**:
The per-Skill portion of an Operation Record that carries Managed Skill ID, Source Lineage ID when applicable, revision addresses, and typed provenance and can be deleted without deleting unrelated Subjects from the same operation.
_Avoid_: Whole Operation Record, Skill bytes, recovery evidence

**Business Commit Point**:
The single SQLite transaction that atomically commits new revision selection and related business metadata, Repository Revision, stable Operation ID, and the Journal commit marker. Before it, recovery rolls the operation back; after it, recovery rolls the operation forward.
_Avoid_: First file write, Git commit creation, operation completion

## Relationships

- A **Managed Skill ID** identifies exactly one managed Skill record for its managed lifetime
- A **Slot Key** identifies exactly one **Skill Slot** on a device but is not the managed Skill's database identity
- At one point in time, one **Managed Skill ID** occupies exactly one **Skill Slot**, and one Skill Slot is occupied by at most one Managed Skill ID
- Each **Managed Skill ID** has exactly one active **Source Lineage**, and that lineage has exactly one current **Source Descriptor** and canonical active Revision Store
- Source provenance, Git-backed revision history, Draft state, Effective Revision, Activation metadata, Skill Extra Data, Skill Tag Assignments, and Operation Subjects reference the **Managed Skill ID**
- A revision address is scoped by **Source Lineage** as `(sourceLineageId, objectId)`; a Git object ID alone never selects business state
- Filesystem materializations and Activation paths use the current **Slot Key**, not the Managed Skill ID
- A changed **Declared Skill Name** preserves the **Managed Skill ID** only when the existing Source selection unambiguously resolves the changed Skill
- A verified name change performs one **Slot Migration** that moves the Repository materialization and every Activation to the new **Slot Key** while preserving Source, revision history, Favorite, Note, and Skill Tag Assignments
- Direct local Publish and Restore Publish must preserve the current **Declared Skill Name**; a future create-Skill flow may choose the name before creating the Managed Skill and Slot
- A **Slot Migration Conflict** preserves the previous Declared Skill Name, Slot Key, Effective Revision, materialization, and every Activation
- Skill Workspace never infers Source continuity from name similarity, content similarity, or an unrelated newly discovered path
- A **Personal Tag** may have zero or more **Skill Tag Assignments**, and one **Managed Skill ID** may have zero or more **Skill Tag Assignments**
- Renaming a **Personal Tag** does not change its stable identity or any **Skill Tag Assignment**
- An **Agent Catalog** contains built-in **Agent Definitions** and may include caller-provided definitions with unique IDs
- An **Agent Definition** resolves at most one **Canonical Activation Location** per supported platform scope and may add zero or more **Compatibility Discovery Locations**
- **Agent Detection** influences automatic selection but does not prevent explicit Activation when a location can be resolved
- Project-scoped canonical and compatibility locations are resolved only within registered **Project Roots**
- One **Compatibility Discovery Location** may map to multiple **Canonical Activation Locations** with the same scope and Project Root provenance; discovery retains every destination rather than making that shared path an **Activation Group**
- A **Skill Slot** contains zero or one **Repository Copy**
- An **External Skill** may occupy a canonical or compatibility discovery location without a **Repository Copy**
- External Skills with the same Skill Slot and content hash form one adoption candidate across multiple locations
- External Skills with the same Skill Slot but different content form an **External Conflict**
- Discovery is read-only; a **Compatibility Discovery Location** never becomes new Activation metadata
- **Adoption** creates a **Repository Copy** with an **Adopted Snapshot Source**, materializes only canonical Activations, and retires reviewed compatibility occurrences in the same recoverable transaction
- Recovery resolves parent symbolic links before capturing a mutation target, preserves the final Skill entry itself, and records the resulting physical mutation path
- A filesystem-backed Local Source or External Skill may be a Git working tree; source acquisition excludes exact `.git` metadata before normalization and hashing while preserving the current ordinary working-tree files
- A **Repository Copy** has exactly one **Effective Revision** and may have one **Draft Workspace**
- A Repository Copy materializes only the current **Effective Revision** at `repository/<slotKey>/`; historical revisions remain only in its Revision Store
- Publish and Update build a complete candidate in operation staging, validate it, and replace the stable Repository Copy path rather than editing published files in place
- The previous Repository Copy survives only as Operation Journal rollback material until finalization, after which it is deleted
- A Repository Copy contains no `.git`, index, refs, configuration, or other Revision Store metadata
- Repository Copies and Activations are App-generated, best-effort read-only derived artifacts; every supported App or external-editor edit targets the Draft Workspace instead
- Bypassing published-artifact permissions creates no Draft, Local Customization, or revision automatically; supported editing still targets the Draft Workspace
- On-demand integrity validation may repair missing projections, but preserves mismatching Repository Copies and Activations as **Unresolved Drift** pending user choice (ADR-0093/0109)
- Explicit Keep validates one reviewed external location as a new local **Publish** and rebuilds all published locations; reviewed projection Restore repairs only drifted and missing locations without publishing history (ADR-0109)
- One **Managed Skill ID** has at most one persistent **Draft Workspace**, whose **Draft Base** remains recorded across App restarts
- A Draft Workspace is an ordinary directory without `.git`, an index, remotes, hooks, or Git configuration
- The Draft directory is authoritative for unpublished working bytes; SQLite records its Draft Base and lifecycle metadata but does not mirror every file edit
- A managed Skill with a tracked Source has one current **Upstream Revision** anchoring its **Local Customization**
- Editing a **Draft Workspace** never changes its **Effective Revision** or any **Activation**
- File watching may refresh Draft presentation but never creates a revision, updates a Revision Pointer, or authorizes Publish
- Publish captures one consistent immutable Draft snapshot in operation staging, validates and commits only that snapshot, and returns `draftChangedDuringPublish` if bounded retries cannot obtain a stable capture
- Dirty state is decided by the same bounded consistent snapshot protocol against the **Draft Base**, not solely by watcher events or cached UI state
- Background update checks remain available while a **Dirty Draft** exists because they do not mutate Source, revision, Draft, or Activation state
- A requested source Update with a **Dirty Draft** returns **Draft Resolution Required** before importing, merging, journaling, or mutating any content
- After the user publishes the Draft, its Local Customization participates in the normal source merge; after an explicit discard, Update proceeds from the current Effective Revision
- Skill Workspace never automatically stashes, rebases, or merges incomplete Draft bytes during a source Update
- Only an explicit, successful **Publish** creates a new **Effective Revision**
- Publish is local and source-agnostic; it never pushes to or modifies an external Source
- A failed or interrupted pre-commit Publish leaves the previous **Effective Revision** business-authoritative and recovery restores its materializations, although an external Agent may transiently observe candidate bytes during the applying window
- After successful Publish, compare-and-delete removes a Draft only when the adapter proves it still equals the captured snapshot; a mismatch or uncertain comparison preserves it and re-anchors its bytes to the new Effective Revision
- Successful initial install, source Update, local Publish, and **Restore Publish** remain reachable in the current **Published Revision History** until Removal; **Source Replacement** is the explicit exception that destroys the previous lineage and starts a new history root
- A **Restore Publish** creates a new revision at the current history tip only when the selected historical tree has the current Declared Skill Name; it does not rewind the Effective or Upstream Revision Pointer
- Git reuses identical trees and blobs for Restore Publish, so restoring content does not duplicate the historical file bytes
- Transaction recovery before the Business Commit Point may restore old pointers because the candidate never committed; this is not a **Restore Publish**
- A source update imports a new **Upstream Revision** and delegates the three-way merge of the previous Upstream Revision, current Effective Revision, and new Upstream Revision to the internal Git engine
- Skill Workspace selects the revisions and owns update policy, validation, conflict presentation, Publish, and recovery; it does not implement the Git merge algorithm
- Initial Install or Adoption selects one root commit as both the Upstream and Effective Revision
- Successive changed Upstream Revisions form a single-parent Upstream line
- Local Publish and Restore Publish extend the Effective first-parent line with a single-parent commit whose parent is the previous Effective Revision
- Successful Update and Update Candidate Session completion extend the Effective line with a merge commit whose first parent is the previous Effective Revision and second parent is the incoming Upstream Revision
- **Local Customization** is the difference between the selected Upstream and Effective trees and has no separate commit line, branch, ref, or Revision Pointer
- A content-identical source check creates no commit, while Source Replacement starts a new root in a new Revision Store
- One **Managed Skill ID** may have at most one **Update Candidate Session**, and that session uses the managed Skill's single Draft Workspace for resolution bytes
- Conflicted and validation-failed source merges both retain previous Upstream, previous Effective, and incoming Upstream revision addresses until the user explicitly Publishes or abandons the Session
- An Update Candidate Session blocks direct Publish, another Update, Restore Publish, and Source Replacement from independently advancing revision or lineage state
- Abandoning an **Update Candidate Session** discards its resolution Draft and candidates without changing published content or history
- The **Internal Revision Engine** uses App-distributed `libgit2` for local object, tree, diff, commit, merge, and conflict operations for every managed Skill
- Every active **Source Lineage** owns exactly one canonical isolated **Revision Store**; Source Replacement may temporarily retain candidate and former Stores only as operation-scoped recovery material, and Revision Stores never share an object database, alternates, refs, locks, or garbage-collection roots
- A **Revision Store** contains immutable history but never serves as the mutable Draft Workspace or an Agent-visible materialization
- The **Revision Store** is authoritative for the bytes and ancestry of an object ID; SQLite **Revision Pointers** are authoritative for which lineage-addressed objects play current Upstream, current Effective, Draft Base, Update Candidate, or operation-candidate roles
- Ordinary revision reads use the canonical active Store; Source Replacement briefly closes one per-Skill revision-access gate, waits for admitted in-process reads, and switches the Store under the Writer Lock
- **Retention Refs** are derived from committed Revision Pointers and in-progress Operation Journal state; application reads never infer current business state from Git refs
- A ref mismatch without a committed pointer change is repaired toward the SQLite Revision Pointers, while an in-progress operation follows its durable Operation Journal recovery path
- A **Revision Store Corruption** never silently falls back to a nearby ref or commit and blocks affected mutations until explicit recovery succeeds
- Every active **Source Lineage** with published history has one **Revision Recovery Bundle** that can resolve all committed Revision Pointers and retained published ancestry
- A **Revision Recovery Bundle** is recovery evidence only; SQLite remains authoritative for revision selection and the Revision Store remains authoritative during normal reads
- Corruption recovery replaces an affected Revision Store from its verified Revision Recovery Bundle under the Writer Lock and Operation Journal, and never promotes a Repository Copy or Activation to authority
- Removal and Source Replacement delete every Revision Recovery Bundle that belongs to the lineage they permanently remove
- The Workspace maintains verified same-device **Control Plane Backups** and never reconstructs missing SQLite authority from Git refs or materializations
- Every mutating operation persists its **Operation Journal** before creating its first externally visible filesystem change
- One **Operation Record** has per-Skill **Operation Subjects**, and each Subject may reference zero, one, or several lineage-addressed Git objects because a product operation and a Git commit are not the same unit
- Version history is the successful, content-changing projection of Operation Records and Subjects; operation history may additionally include failed, cancelled, rolled-back, and no-op Subjects
- History presentation queries Operation Records and Subjects and resolves file trees or diffs from their revision addresses instead of scanning Git commit graphs for business meaning
- Git objects, staged materializations, backups, and operation Retention Refs created before the **Business Commit Point** remain candidates rather than current business state
- The **Business Commit Point** atomically commits new Revision Pointers, active Source Lineage, Activation metadata, Repository Revision, related SQLite state, and the Operation Journal commit marker
- Recovery before the **Business Commit Point** restores the previous filesystem state and pointers; recovery after it completes materializations, Retention Refs, and cleanup toward the committed state
- The **Git Source Transport** uses system Git only for acquiring external Git Source bytes through no-checkout, hook-free, filter-free controlled tree/blob export; it is not the internal revision fallback for Local, Well-known, Adopted, or Marketplace Sources
- The **Internal Revision Engine** does not import or execute Source remotes, hooks, filters, submodules, credential configuration, or global Git configuration
- An explicit source Update authorizes Publish when its merge is conflict-free and the resulting Skill passes validation; the Update and Publish complete as one recoverable operation
- A background update check is read-only and never authorizes merge or Publish
- An **Update Conflict** or validation-failed merged candidate persists as a resumable **Update Candidate Session**, and neither changes the existing Effective Revision or any Activation
- **Local Customization** continues to follow its Source until the managed Skill is removed or its Source is explicitly replaced
- Skill Workspace provides no operation that detaches an existing managed Skill from its Source while preserving the same content lineage
- A managed Skill acquired from a Git Source may retain one **Source Reference** without classifying it as a branch or tag
- An **Adopted Snapshot Source** cannot be checked for updates and must be explicitly replaced before source-based updates are available
- A **Source Unavailable** state limits update operations but does not change the **Repository Copy** or any **Activation**
- **Source Replacement** preserves Managed Skill ID, Slot identity subject to Slot Migration, Favorite, Note, Personal Tag Assignments, and Activation configuration
- **Source Replacement** does not carry old Local Customization into the new Source and permanently deletes the old **Source Descriptor**, Upstream and Effective Revisions, Local Customization, restore history, and Revision Store after successful finalization
- Until the Business Commit Point, the old Source Lineage, Revision Store, and Source metadata exist as rollback material; after commit, reads resolve only the new canonical Store while finalization finishes deleting the former lineage rather than make it user-restorable
- Source Replacement requires explicit destructive intent bound to the state the caller reviewed
- A **Repository Copy** may have zero or more **Activations**
- An **Activation** exposes a **Repository Copy** through one **Canonical Activation Location**
- A symbolic-link Activation targets the stable Repository Copy Slot path and therefore does not need a new link for each Effective Revision; a copy-mode Activation receives its own recoverable directory replacement
- **Adoption** chooses an External Skill as authoritative content and creates a Repository Copy; **Activation Takeover** starts from an existing Repository Copy and makes it authoritative at an occupied target
- An occupied unmanaged target whose content matches the **Effective Revision** may be taken over automatically; different or indeterminate content requires explicit **Activation Takeover** confirmation
- Every explicit **Activation Takeover** is bound to the reviewed **Repository Revision** and occupied-target fingerprints
- A **Stale Activation Takeover** changes no Repository or Activation state and requires a new inspection and confirmation
- An internal **Operation Plan** resolves a **Requested Activation Mode** into an **Activation Mode**
- An **Activation** records the resolved **Activation Mode** that materialized it
- Every **Activation** of a **Skill** uses the same **Effective Revision**
- A **Skill** may have global and project-scoped **Activations** at the same time
- A **Canonical Activation Location** belongs to one **Activation Group**
- Every agent in an **Activation Group** shares the same activation state for a **Skill**
- Removing an **Activation** does not remove its **Repository Copy**
- **Removal** deletes every Activation, Repository Copy, Skill Slot, Draft, Update Candidate Session, Source Lineage, Revision Store, Revision Recovery Bundle, Skill Extra Data, Skill Tag Assignment, and per-Skill Operation Subject owned by the Managed Skill ID
- Reusable **Personal Tags** survive Removal, but a completed Removal retains no per-Skill tombstone, summary, Source provenance, revision address, or eligible App-managed Control Plane Backup containing the removed Skill
- Every **Destructive Intent** carries the expected **Repository Revision** that the caller presented for confirmation
- A **Stale Destructive Intent** changes no Repository or Activation state and requires refresh plus new confirmation

## Example dialogue

> **Dev:** "Does turning off a **Skill** delete it?"
> **Domain expert:** "No. It removes the **Activation**, while the **Repository Copy** remains available for later reactivation."

## Flagged ambiguities

- "Installed" previously meant both stored locally and visible to an agent. Use **Repository Copy** for durable local storage and **Activation** for agent visibility.
- "Open" and "closed" are UI wording, not domain states. The domain operation is activation or deactivation.
- Per-agent activation is not promised when multiple agents share an **Activation Location**; activation is controlled by **Activation Group**.
- A Skill version is device-wide, not project-specific; publishing a new **Effective Revision** affects every Activation of that Skill.
- **Draft Workspace** edits are private work-in-progress until an explicit **Publish**; autosave never changes Agent-visible content.
- Draft Workspace files survive App restart and may be opened in an external editor; their lack of Git metadata is intentional.
- A successful Publish or Update deletes a Draft only through a proven unchanged compare-and-delete; a concurrent or uncertain post-snapshot state survives against the new Effective Revision.
- An explicit source Update may invoke **Publish** as its final stage without requiring a second user confirmation; this does not permit background update checks to mutate content.
- A **Publish** is blocked unless the new **Effective Revision** and every Activation can be synchronized in one recoverable operation.
- **Publish** means applying a revision locally; it never means pushing changes to GitHub, GitLab, a Local Source, or another remote system.
- Git is the internal revision and merge mechanism, not a Source type: Local, Git, Well-known, Adopted, and future Marketplace Sources retain their own provenance.
- The internal Git engine performs merge mechanics; Skill Workspace never reimplements file diff, rename detection, or three-way merge algorithms.
- Choosing embedded `libgit2` does not select a particular Dart package; the FFI adapter remains an internal implementation decision.
- Only an active **Source Lineage** of a managed, locally installed Skill owns a **Revision Store**; Marketplace catalog entries and unadopted External Skills do not.
- Garbage collection may remove unreachable failed, cancelled, or finalized operation candidates, but not reachable **Published Revision History**.
- SQLite and Git are not co-authorities for the same fact: SQLite selects current revision roles, while Git defines the immutable contents and history of the selected object IDs.
- Atomicity across several Agent-visible filesystem paths is recoverable rather than physically instantaneous; external Agents may observe a transient applying window even though App readers and later recovery have one committed outcome.
- Every Git **Source Reference** is re-resolved during update checks; moved tags are treated like changed branches, and raw commit pinning is not a guaranteed workflow.
- A Source locator or selected subpath that disappears makes the managed Skill **Source Unavailable**. A verified frontmatter-name change from the same Source selection instead follows **Slot Migration**; unrelated newly discovered Skills occupy their own Slots.
- Declared names that derive the same **Slot Key** compete for one **Skill Slot**, even when they come from different sources.
- A **Managed Skill ID** is never exposed as the Repository or Activation directory name; those paths continue to use the current **Slot Key**.
- “Open in external editor” opens the Draft Workspace, never the Repository Copy or an Activation path.
- Direct modification of a Repository Copy or Activation is unsupported editing, not Local Customization. Ordinary integrity validation preserves detected mismatches as **Unresolved Drift**; only explicit validated Keep makes those bytes published customization, while reviewed Restore replaces them (ADR-0093/0109).
- A Source update may change the **Declared Skill Name** without changing the **Managed Skill ID**, but only through a verified, conflict-free **Slot Migration**.
- A direct local Publish or Restore Publish cannot change the **Declared Skill Name**; a historical revision with a different name is not restorable under the current Slot.
- Changing the source occupying a **Skill Slot** is a **Source Replacement**, not a version update, and requires an explicit `replaceSource()` request rather than a second confirmation step.
- Source Replacement is not an ordinary Update and permanently destroys its previous Source lineage after successful finalization.
- Source Replacement removes Operation Subjects belonging to the deleted lineage and may retain only a new-lineage replacement Subject without the deleted **Source Descriptor**, object IDs, or historical bytes.
- Discovery is read-only; finding an **External Skill** never performs **Adoption** automatically.
- An **External Conflict** blocks Adoption until one candidate is explicitly selected as authoritative content.
- Adoption is not the only operation that may replace an occupied Activation target: **Activation Takeover** may do so when a Repository Copy already exists and the caller has reviewed any non-matching content.
- **Activation Takeover** handles ownership at a new unmanaged Activation target. On-demand integrity validation separately detects later drift in managed Activations (ADR-0093); explicit Keep or reviewed projection Restore resolves it (ADR-0109), rather than a new Takeover.
- Skill Workspace does not impose one device-wide **Activation Mode**; the caller supplies a **Requested Activation Mode** in the mutation request.
- Explicit symbolic-link and copy requests are strict; only automatic selection may fall back from symbolic link to copy.
- Automatic selection prefers symbolic link with copy fallback for global Activations and resolves directly to copy for project Activations.
- **Deactivation** is reversible exposure management, while **Removal** deletes the device-wide managed Skill.
- Completed **Removal** retains no per-Skill history summary or tombstone; shared Operation Record headers survive only for unaffected Subjects.
- **Repository Revision** versions the whole Repository Snapshot; **Effective Revision** identifies one Skill's published content. They are not interchangeable.
- Removal and Source Replacement never silently retry after a **Stale Destructive Intent** failure, even when the requested Slot Key still exists.
- Caller-provided **Agent Definitions** may extend the catalog but cannot silently replace a built-in definition with the same ID.
- An undetected **Agent** may be explicitly targeted when its **Activation Location** is valid; unsupported or unresolvable locations remain blocked.
- Discovery never searches the device for projects; only registered **Project Roots** participate in project-scoped management.
- Skill Workspace reports coexisting global and project **Activations** but does not infer an Agent's loading precedence between them.
