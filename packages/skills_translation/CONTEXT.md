# Translation

This context translates immutable Skill content for reading without modifying the Skill, its Repository Copy, or any Activation.

## Language

**Source Document**:
The complete selected Markdown document for one Slot Key, content hash, and
Document Identifier. The App supplies the Document Identifier as a POSIX relative path.
_Avoid_: Skill file, mutable document

**Document Identifier**:
The stable POSIX relative path that distinguishes Markdown documents inside one
immutable Skill revision.
_Avoid_: cache filename, absolute path

**Translation Job**:
One attempt to translate a selected Scope of one Source Document into one Target Language through one Translation Provider.
_Avoid_: Translation Segment, batch

**Translation Scope**:
The reader's choice between all translatable document prose and only the top-level `SKILL.md` description.
_Avoid_: Translation Segment, document path

**Target Language**:
The language requested for a Translation Job, represented by a stable language identifier rather than display text.
_Avoid_: App locale, system language

**Translation Provider**:
An implementation behind the provider interface that performs a user-initiated
Translation Job. The cross-platform implementations are OpenAI-compatible text
generation, with an explicit Chat Completions or Responses protocol, and
Anthropic Messages.
_Avoid_: Translation context, cache

**Translation Segment**:
A provider-internal portion of a Source Document used to satisfy provider limits while remaining part of one Translation Job.
_Avoid_: Translation Job, cache entry

**Local Markdown Segment**:
A portion such as a fenced code block, whitespace, or protected front matter
metadata that is preserved locally and never uploaded to a Translation
Provider. Only the decoded top-level front matter `description` string is a
Translation Segment.
_Avoid_: redacted content, translated segment

**Translation Draft**:
Ephemeral cumulative block replacements streamed while a Translation Job is
running, plus an optional translated front matter description and whole-Job
progress. A completed block may become visible before an earlier source block,
but a Draft is never treated as a complete cached result.
_Avoid_: Completed Translation, saved translation

**Markdown Block ID**:
A stable Source Document range identity published by the shared Markdown parser
and used to map one provider translation back to its display location. For a
`SKILL.md`, IDs are relative to the frontmatter-stripped Markdown body, exactly
matching the renderer. For every other Markdown document, IDs use the complete
displayed document coordinate space so visible front matter remains in place.
_Avoid_: Translation Segment index, cache key

**Completed Translation**:
The complete successful output for one Translation Scope, including provider and model provenance, eligible for the disposable Translation Cache.
_Avoid_: Translation Draft, annotation

**Translation Cache**:
The context-owned, content-addressed store of Completed Translations, located outside the engine's Repository Root and retaining no parallel provider/model history for the same Source Document, Target Language, and Translation Scope.
_Avoid_: Repository state, user-authored library

**Translation Replacement**:
The atomic cache commit that installs a newly Completed Translation and removes the previous result for the same Source Document, Target Language, and Translation Scope.
_Avoid_: Job start, cache history

**Cache Eviction**:
The immediate invalidation and deletion of every cached Completed Translation whose Source Document content hash is no longer current for its Slot Key.
_Avoid_: Lazy cleanup, translation archive

**Job Cancellation**:
The terminal outcome when the user closes the Source Document or selects a different Target Language before a Translation Job completes; its Translation Draft is discarded and it produces no Completed Translation.
_Avoid_: Paused translation, background translation

**Translation Failure**:
The terminal outcome when a Translation Job cannot produce a Completed Translation; its Translation Draft is discarded while any previous Completed Translation remains available.
_Avoid_: Automatic retry, partial translation

**Offline Reading**:
Reading an existing Completed Translation without contacting a Translation Provider or creating a Translation Job.
_Avoid_: Offline translation, queued translation

## Relationships

- A **Source Document** is identified by the engine's published Slot Key and content
  hash plus the App-supplied Document Identifier
- A **Translation Job** consumes exactly one immutable **Source Document**, one **Translation Scope**, and one **Target Language**
- A **Translation Provider** may divide a **Translation Job** into **Translation Segments** internally and execute them with bounded per-Job concurrency
- Fenced code blocks become **Local Markdown Segments** and are never sent to a Provider
- Source line endings adjacent to **Local Markdown Segments** are restored after
  Provider translation so model whitespace normalization cannot corrupt fenced
  Markdown structure
- A **Translation Segment** has no independent user-visible lifecycle or cache identity
- A running **Translation Job** may emit zero or more cumulative **Translation Drafts**
- A **Translation Draft** maps completed translations to shared **Markdown Block IDs**;
  lists and tables remain whole blocks
- `frontmatter:description` is a reserved Provider wire-unit ID. It maps only
  to `translatedDescription`, is never constructed as a **Markdown Block ID**,
  and cannot collide with the `b:<start>:<end>` Markdown ID namespace
- Concurrent block completion may become visible out of Source Document order
  without changing final document order
- Only a successful scoped **Translation Job** produces a **Completed Translation**
- Only a **Completed Translation** may enter the **Translation Cache**
- The **Translation Cache** is keyed on `(slotKey, contentHash,
  documentIdentifier, targetLanguage, scope)` and retains at most one **Completed
  Translation** for that identity; changing Provider or model does not preserve the
  previous result as an alternate version
- A Source Document content-hash change triggers immediate **Cache Eviction**; the previous translation becomes unavailable and its cached data is deleted immediately
- While a replacement Job runs, its **Translation Draft** is displayed and the previous **Completed Translation** remains only as a fallback
- A successful replacement Job performs one atomic **Translation Replacement**; a failed or cancelled Job leaves the previous **Completed Translation** unchanged
- **Job Cancellation** stops the active **Translation Job** instead of leaving it running in the background
- A **Translation Failure** never retries automatically; the user may explicitly start a new **Translation Job** after seeing the failure reason
- **Offline Reading** is available only when the Translation Cache contains a matching Completed Translation; otherwise the app displays the Source Document
- An unavailable network provider never creates a deferred Translation Job, and network recovery never starts or retries a Job automatically
- Translation never mutates the Source Document, Repository Copy, Skill Slot, or Activation

## Example dialogue

> **Dev:** "The provider translated the document in four chunks. Do I now have four translations?"
> **Domain expert:** "No. You have one **Translation Job** for the selected **Translation Scope**. The chunks are internal **Translation Segments**."

## Flagged ambiguities

- "Translation" can mean an attempt, partial output, or completed output. Use **Translation Job**, **Translation Draft**, or **Completed Translation** explicitly.
- A provider may batch blocks into Segments for technical limits, but callers
  never schedule or cache individual **Translation Segments**.
- Streaming output is not durable evidence of success; an interrupted **Translation Job** has no **Completed Translation**.
- Provider and model identify the provenance of a **Completed Translation**, not a user-visible history of alternatives.
- "Do not retain the old translation" means successful **Translation Replacement** removes it; the old result remains as failure recovery until the new Job succeeds.
- Provider failures use stable **Translation Failure** codes. The Provider's own
  error code/type and message may additionally be shown verbatim on explicit
  Translation failure, even if the message echoes sensitive content; full
  responses, headers, and SDK exceptions remain private. **Job Cancellation**
  remains a distinct non-failure outcome (ADR-0102).
- "Offline translation" is not a provider fallback. Offline mode can read a **Completed Translation** but cannot create one unless a separately configured on-device provider is available.
- A Translation Job is always user-initiated; reconnecting, reopening a page, or changing app lifecycle state never sends a Source Document automatically.
- The App must show the configured Endpoint and obtain an explicit user action before
  starting a network Job. Consent persistence and credential storage remain App-layer
  concerns under ADR-0062.
- Prose is uploaded without automatic secret redaction. Fenced code is the only content
  category kept local by the segmenter; the UI must disclose Provider-side retention.
- **Target Language** is selected independently from the app locale, even when the app uses the locale as a default.
