# skills_translation example

Developer-facing Flutter desktop app for manually exercising the public
`skills_translation` Provider contract.

The example supports:

- OpenAI-compatible Responses and Chat Completions;
- Anthropic Messages;
- a built-in editable Markdown sample or a selected local `.md` file;
- cumulative streaming Drafts, cancellation, sanitized Failures, and Completed
  Translation provenance.

It intentionally does not demonstrate `FileTranslationCache`. The API key and
all Provider configuration remain in memory, are never logged, and are cleared
when switching Provider. No request starts until **Translate** is selected.

## Run

```shell
flutter pub get
flutter run -d macos
# flutter run -d windows
# flutter run -d linux
```

Enter an API Base URI, model identifier, API key when required, and target
language. OpenAI-compatible local gateways may leave the API key empty. Choose
**Open .md** to load a real Skill document or edit the sample directly.
The Segment Character Budget defaults to `6000` and can be changed before
starting a translation to control the maximum Unicode scalar count sent in one
Provider request.
OpenAI-compatible requests omit `maxOutputTokens` and `temperature` by default
so gateways that reject those optional fields remain usable. Anthropic keeps
the package defaults because native Messages requests require `max_tokens`.

## Verify

The automated suite uses controlled Fakes and never contacts a Provider:

```shell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
```
