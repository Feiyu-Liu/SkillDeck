#!/bin/bash
# A single public entrypoint with two complete, independently signed Dart CLIs.
set -euo pipefail
cli_package="$PROJECT_DIR/../../packages/skilldeck_cli"
cache_dir="$DERIVED_FILE_DIR/skilldeck-cli-universal"
helpers="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
launcher_source="$PROJECT_DIR/scripts/universal_cli_launcher.c"
intel_cli="${SKILLDECK_CLI_X86_64:-}"
fail() { echo "error: $1" >&2; exit 1; }
[[ -x "$intel_cli" && "$(lipo -archs "$intel_cli" 2>/dev/null)" == x86_64 ]] ||
  fail 'Universal CLI needs a native x86_64 SkillDeck executable.'
[[ "$(uname -m)" == arm64 ]] ||
  fail 'Build the Universal CLI on Apple Silicon with a native Intel input.'
dart="$FLUTTER_ROOT/bin/dart"
mkdir -p "$cache_dir"
cd "$cli_package"
source_hash=$(
  {
    find lib bin -type f -print0 | LC_ALL=C sort -z |
      while IFS= read -r -d '' source; do shasum -a 256 "$source"; done
    shasum -a 256 pubspec.lock pubspec.yaml "$launcher_source" \
      "$PROJECT_DIR/scripts/bundle_skilldeck_universal_cli.sh" \
      "$PROJECT_DIR/scripts/skilldeck_cli.entitlements" "$intel_cli"
    "$dart" --version 2>&1
  } | shasum -a 256 | awk '{print $1}'
)
stored_hash=''
[[ ! -f "$cache_dir/source.sha256" ]] || stored_hash=$(cat "$cache_dir/source.sha256")
if [[ "$source_hash" != "$stored_hash" || ! -x "$cache_dir/output/skilldeck" ||
      ! -x "$cache_dir/output/SkillDeckCLI/skilldeck.arm64" ||
      ! -x "$cache_dir/output/SkillDeckCLI/skilldeck.x86_64" ]]; then
  compilation=$(mktemp -d "$cache_dir/compile.XXXXXX")
  trap 'rm -rf "$compilation"' EXIT
  payload="$compilation/SkillDeckCLI"
  mkdir -p "$payload"
  "$dart" --suppress-analytics pub get --offline --enforce-lockfile >/dev/null 2>&1 ||
    fail 'Cannot resolve the locked SkillDeck CLI dependencies offline.'
  "$dart" --suppress-analytics compile exe bin/skilldeck.dart \
    --target-os=macos --target-arch=arm64 -o "$payload/skilldeck.arm64" >/dev/null 2>&1 ||
    fail 'CLI compilation failed.'
  cp "$intel_cli" "$payload/skilldeck.x86_64"
  xcrun --sdk macosx clang -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 \
    -Os -Wall -Wextra -Werror "$launcher_source" -o "$compilation/skilldeck" >/dev/null 2>&1 ||
    fail 'Universal CLI launcher compilation failed.'
  chmod 755 "$compilation/skilldeck" "$payload/skilldeck.arm64" "$payload/skilldeck.x86_64"
  # Do not replace the App's helper when compilation fails.
  rm -rf "$cache_dir/output"
  mkdir -p "$cache_dir/output"
  mv "$compilation/skilldeck" "$compilation/SkillDeckCLI" "$cache_dir/output/"
  printf '%s\n' "$source_hash" > "$cache_dir/source.sha256"
  rm -rf "$compilation"
  trap - EXIT
fi
staging=$(mktemp -d "$cache_dir/bundle.XXXXXX")
trap 'rm -rf "$staging"' EXIT
cp -R "$cache_dir/output/skilldeck" "$cache_dir/output/SkillDeckCLI" "$staging/"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
timestamp=(--timestamp)
[[ "$identity" != '-' ]] || timestamp=()
for binary in "$staging/SkillDeckCLI/skilldeck.arm64" "$staging/SkillDeckCLI/skilldeck.x86_64" "$staging/skilldeck"; do
  codesign --force --sign "$identity" --options runtime \
    ${timestamp[@]+"${timestamp[@]}"} \
    --entitlements "$PROJECT_DIR/scripts/skilldeck_cli.entitlements" \
    "$binary" >/dev/null 2>&1 || fail 'Universal CLI signing failed.'
done
help=$("$staging/skilldeck" --help 2>/dev/null) || fail 'The signed Universal CLI does not launch.'
[[ "$help" == *'Usage: skilldeck'* && "$help" != *'Usage: dartvm'* ]] ||
  fail 'The Universal helper did not execute the SkillDeck CLI.'
mkdir -p "$helpers"
rm -rf "$helpers/SkillDeckCLI"
mv "$staging/SkillDeckCLI" "$helpers/SkillDeckCLI"
mv -f "$staging/skilldeck" "$helpers/skilldeck"
