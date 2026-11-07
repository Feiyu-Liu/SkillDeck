# skills_translation

Live, explicitly cancellable translation of immutable Skill Markdown with a
content-addressed file cache. The package owns the Translation boundary; it
does not modify Skill content, Workspace state, or activations and has no
dependency on `skills_workspace`. It is a Flutter package because its block identity
and parsing contract comes directly from `flutter_md`.

## Providers

Two concrete adapters are available:

- `OpenAICompatibleTranslationProvider` uses `/chat/completions` by default
  and can explicitly select `/responses` through
  `OpenAICompatibleProtocol.responses`. It accepts a custom API Base URI and
  permits an empty API key for local Endpoints such as Ollama-compatible
  gateways. An empty key sends no Authorization header.
- `AnthropicMessagesTranslationProvider` uses Anthropic's native `/messages`
  protocol and requires an API key.

All adapters use the same plain-text translation protocol without a native
response schema. A singleton request returns one translated block directly. A
multi-block request separates blocks with standalone `%%` lines and requires
the same count and order in the response.

Both adapters wrap `llm_dart 0.11.0-alpha.1` internally. No `llm_dart` type is
exported or accepted by the public API. Jobs stream source-ordered cumulative
Drafts, use bounded per-Job Segment concurrency, use zero automatic retries,
and stop every active request plus every later Segment when cancelled.
OpenAI-compatible Endpoints that
ignore streaming and return one JSON response are adapted without a second
request.

```dart
import 'package:skills_translation/skills_translation.dart';

final provider = OpenAICompatibleTranslationProvider(
  apiBaseUri: Uri.parse('http://127.0.0.1:11434/v1'),
  modelIdentifier: 'local-model',
);

final sourceDocument = SourceDocument(
  slotKey: 'review-pull-requests',
  contentHash: 'published-content-hash',
  documentIdentifier: 'references/review.md',
  content: '# Review pull requests',
);
final job = provider.start(
  sourceDocument: sourceDocument,
  targetLanguage: TargetLanguage('zh-Hans'),
);

final subscription = job.drafts.listen((draft) {
  final visibleMarkdown = draft.applyTo(sourceDocument);
  // Display the cumulative replacement Draft. Never persist it.
});
final outcome = await job.result;
await subscription.cancel();
```

The System Prompt is configurable through `TranslationProviderOptions` and
must contain `{{targetLanguage}}`. The default System Prompt treats Skill prose
as source text rather than instructions addressed to the model, contains no
wire-protocol examples, and delegates the exact output contract to each
request. Singleton requests never mention the multi-block separator;
multi-block requests require matching block and separator counts. Keeping this
contract short reduces opportunities for smaller models to echo or reason
about the protocol, but it cannot make probabilistic Provider output correct.
The live E2E therefore rejects leaked separators, exposed analysis, and changed
fenced code in addition to the decoder's block-count checks.
`flutter_md`'s `MarkdownSourceParser` is the only Markdown
body/fence block parser. `parseTranslationDisplayDocument` exposes the exact
renderer coordinate space: `SKILL.md` uses its frontmatter-stripped body, while
other Markdown files keep their complete displayed source and use absolute body
block offsets. Multiple whole blocks are batched under a default budget of
about 2,000 Unicode scalar values; an oversized block is never split, and
lists/tables remain whole. Fenced code blocks are preserved byte-for-byte and
never uploaded. In leading YAML front matter, only the decoded top-level
`description` string is uploaded; delimiters, `name`, and all other metadata
remain local. The translated description is re-encoded as a valid YAML
double-quoted scalar. Its Provider-only wire ID is
`frontmatter:description`; it never becomes a `MarkdownBlockId` or enters
`TranslationDraft.translatedBlocks`. Malformed or unsupported front matter remains entirely
local. Other prose is not automatically redacted. `maxOutputTokens` and
`temperature` retain conservative defaults but accept `null` when a compatible
Endpoint requires those request fields to be omitted.

Model reasoning is disabled by default so hidden reasoning tokens cannot
displace the translated Markdown. OpenAI-compatible Chat Completions receives
`reasoning_effort: "none"`, Responses receives
`reasoning: {"effort": "none"}`, and Anthropic leaves extended thinking off.
Set `reasoningEnabled: true` to let the selected Provider use its native
reasoning behavior. Endpoints that do not support the explicit OpenAI-compatible
disable field fail safely instead of being retried without the requested
policy.

Each Segment returns plain translated Markdown. Standalone separator lines are
decoded incrementally and completed blocks are published as cumulative
replacements, so later source blocks may appear first. Final acceptance
requires the expected number of non-empty translated blocks. If a batch cannot
be decoded or reaches its output limit, its unfinished suffix is retried as
ordered singleton requests. A singleton protocol failure fails the entire Job;
callers keep an older cache entry or the original source.

`TranslationProviderOptions.maxConcurrentSegments` controls the maximum
number of Provider requests in flight for one Job and defaults to `1` for
compatibility. Separate Jobs do not share a global limit. When one Segment
fails after its internal singleton fallback, queued Segments do not start,
in-flight requests drain naturally, and the first sanitized Failure becomes
the Job outcome. Transport failures are never retried.

## Cache

`FileTranslationCache` stores only Completed Translations in a caller-injected
directory outside the Skill Workspace root. Its identity is
`(slotKey, contentHash, documentIdentifier, targetLanguage)`; Provider and model
are provenance and do not create history branches.

```dart
final cache = FileTranslationCache(
  rootDirectory: Directory('/app-support/agent_skills/translations'),
);

if (outcome case final CompletedTranslation completed) {
  await cache.saveOrReplace(completed);
}
```

Entries are versioned JSON beneath SHA-256-derived paths. Writes use an OS file
lock, same-directory temporary file, flush, and atomic replacement. Corrupt
entries become cache misses and are removed. `evictStale` deletes entries whose
published content hash is no longer current.

The cache stores no Source Document or API key. API keys must be supplied by
the App from secure storage and remain only in memory. Raw Provider exceptions,
headers, response bodies, URL userinfo, credentials, and Source content are not
returned in Translation Failures or emitted through package logging.

## Dependency pin

The pub.dev archive for `llm_dart 0.11.0-alpha.1` omitted required Provider
sources. This package therefore overrides the five used split packages to the
complete upstream release-tag commit
`a3b8827c5ff0cb86770f24a34bbd551482eaf3ae` and pins Dio to `5.9.2`. Because
Pub does not inherit dependency overrides from path dependencies, an App that
adds this internal package must repeat those overrides until the upstream
hosted artifact is replaced or this package upgrades `llm_dart`.

## Example app

`example/` is a small Cupertino desktop app that exercises the public Provider
contract without adding Flutter to this package. It supports OpenAI-compatible
Responses and Chat Completions, Anthropic Messages, editable Markdown, local
`.md` files, cumulative Drafts, cancellation, and Completed Translation
provenance. Its Segment concurrency stepper defaults to `3` and allows values
from `1` through `8`. Max Output Tokens is an optional positive integer field;
leaving it blank keeps the Provider request field omitted. Its Reasoning switch
defaults to off and is locked while a Translation Job is running.

```shell
cd example
flutter run -d macos
# Or use -d windows / -d linux on those platforms.
```

The example does not translate automatically. Provider settings and the API
key are entered at runtime, remain in memory only, and are cleared when the
Provider changes. It intentionally does not demonstrate the file cache; cache
behavior remains covered by the package tests.

For broad gateway compatibility, its OpenAI-compatible requests omit the
optional output-token and temperature fields; Anthropic retains package
defaults.

## Development

```shell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

The default suite never contacts a real Provider. An environment-gated live E2E
test is available for explicitly authorized OpenAI-compatible Endpoints:

```shell
SKILLS_TRANSLATION_E2E_API_KEY='...' \
SKILLS_TRANSLATION_E2E_API_BASE_URI='https://example.com/v1' \
SKILLS_TRANSLATION_E2E_MODEL='model-id' \
SKILLS_TRANSLATION_E2E_SKILL_PATH='/absolute/path/to/a/real/SKILL.md' \
SKILLS_TRANSLATION_E2E_PROTOCOL='chat' \
SKILLS_TRANSLATION_E2E_REASONING_ENABLED='false' \
SKILLS_TRANSLATION_E2E_SEGMENT_CHARACTER_BUDGET='4000' \
SKILLS_TRANSLATION_E2E_MAX_OUTPUT_TOKENS='16384' \
SKILLS_TRANSLATION_E2E_OUTPUT_PATH='/tmp/translated-skill.md' \
dart test test/live/openai_compatible_live_e2e_test.dart
```

The API key is optional for local gateways and, when supplied, is read only
from the process environment. Protocol defaults to Responses and reasoning
defaults to disabled. The Segment budget defaults to the package value of
6,000 and may be lowered for small-context compatible routes. The test verifies
a completed streaming translation,
stable provenance, Chinese output, front matter, and any fenced-code blocks
byte-for-byte. It also verifies that front matter remains valid YAML, retains
its original `name`, and contains a translated `description`. It skips without
the Base URI, model, and Skill path and is
therefore safe in the default offline CI suite. The optional output path is
intended for manual review and should not point inside the repository.

See `CONTEXT.md`, ADR-0052, and ADR-0062 for the ownership and privacy
boundaries. App consent UI, settings, secure credential storage, and Skill
detail-page composition are intentionally outside this package change.
