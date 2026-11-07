## Unreleased

- Publish one renderer-coordinate Markdown projection for live Drafts.
- Keep non-`SKILL.md` front matter visible while mapping body replacements to
  full-document block IDs.

## 0.3.0

- Use `flutter_md`'s shared `MarkdownSourceParser` for source-anchored Markdown
  blocks and body-relative `MarkdownBlockId` replacements.
- Replace whole-text Drafts with cumulative block and frontmatter-description
  replacements plus completed/total progress.
- Batch multiple whole Markdown blocks into strict versioned JSON Segment
  responses and incrementally publish completed `blocks` array elements.
- Make OpenAI-compatible native JSON Schema the default, with an explicit
  prompt-only compatibility mode and no automatic fallback or retry.
- Keep Anthropic on JSON prompting plus the same strict local decoder because
  `llm_dart 0.11.0-alpha.1` cannot project the shared response format there.
- Validate exact Segment/block mappings, non-empty translations, and compatible
  single-root Markdown block kinds before accepting output.
- Preserve lists and tables as whole blocks, fenced code locally, and the
  special `frontmatter:description` wire unit outside `translatedBlocks`.
- Raise the package baseline to Flutter 3.29 and allow FFI 2.2.

## 0.2.0

- Disable model reasoning by default with explicit OpenAI-compatible protocol
  projection, while allowing callers and the example to opt in.
- Reduce the default translated Segment budget from 12,000 to 6,000 Unicode
  scalar values for smaller-context local models.
- Strip echoed request-boundary lines from compatible model output.
- Add a Flutter desktop example for live Provider configuration, editable or
  file-backed Markdown, cumulative Drafts, completion, and cancellation.
- Add explicit OpenAI-compatible Responses API routing while preserving Chat
  Completions as the default.
- Preserve source line endings around local Markdown segments when Providers
  trim translated-fragment boundaries.
- Add OpenAI-compatible Chat Completions and Anthropic Messages Providers.
- Keep all `llm_dart 0.11.0-alpha.1` types behind the Translation interface.
- Add configurable bounded Markdown Segment concurrency with source-ordered
  Drafts and local fenced-code preservation.
- Keep YAML front matter local except for the decoded top-level `description`
  string, then safely re-encode its translation as valid YAML.
- Add cumulative live Drafts, request cancellation, stable sanitized failures,
  zero retries, timeout configuration, and OpenAI JSON fallback.
- Add `documentIdentifier` to Source and Completed Translation identity.
- Add a versioned, atomic, cross-platform `FileTranslationCache`.

## 0.1.0

- Add the whole-document Translation Provider interface.
- Add cumulative Translation Drafts and an explicitly cancellable Job handle.
- Add typed Completed Translation, Failure, and Job Cancellation outcomes.
- Ship no concrete Provider, cache, network, credential, retry, or UI code.
