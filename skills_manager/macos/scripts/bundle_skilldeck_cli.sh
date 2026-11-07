#!/bin/bash
# Xcode's Runner phase; never print filesystem locations or tool diagnostics.
set -euo pipefail
# Match the CLI lockfile even when the GUI developer uses a pub mirror.
export PUB_HOSTED_URL=https://pub.dev

cli_package="$PROJECT_DIR/../../packages/skilldeck_cli"
cache_dir="$DERIVED_FILE_DIR/skilldeck-cli"
# Contents/Helpers, never Contents/MacOS: the default case-insensitive volume
# treats "skilldeck" and the App executable "SkillDeck" as the same file.
output="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/skilldeck"
mkdir -p "$cache_dir"
cd "$cli_package"

architectures="${ARCHS:-$(uname -m)}"
if [[ "$architectures" == *' '* && "${ONLY_ACTIVE_ARCH:-NO}" == YES ]]; then
  architectures="${NATIVE_ARCH_ACTUAL:-$(uname -m)}"
fi
# Dart cannot cross-compile a macOS executable, so an arm64 release host takes
# the x86_64 slice from an Intel Mac that compiled the same commit natively.
prebuilt_x86_64="${SKILLDECK_CLI_X86_64:-}"
if [[ -n "$prebuilt_x86_64" ]] &&
    [[ ! -f "$prebuilt_x86_64" || "$(lipo -archs "$prebuilt_x86_64" 2>/dev/null)" != x86_64 ]]; then
  echo 'error: The prebuilt x86_64 SkillDeck CLI is missing or not x86_64.' >&2
  exit 1
fi

# Run every time to detect edits/deletions nested below the declared directories.
# Cache the expensive compilation, including SDK and build-script changes.
source_hash=$(
  {
    printf '%s\n' "$architectures"
    if [[ -n "$prebuilt_x86_64" ]]; then shasum -a 256 < "$prebuilt_x86_64"; fi
    find lib bin -type f -print0 | LC_ALL=C sort -z |
      while IFS= read -r -d '' source; do
        shasum -a 256 "$source"
      done
    shasum -a 256 pubspec.lock pubspec.yaml "$PROJECT_DIR/scripts/bundle_skilldeck_cli.sh"
    "$FLUTTER_ROOT/bin/dart" --version 2>&1
  } | shasum -a 256 | awk '{print $1}'
)
stamp="$cache_dir/source.sha256"
stored_hash=''
if [[ -f "$stamp" ]]; then stored_hash=$(cat "$stamp"); fi
if [[ ! -f "$cache_dir/skilldeck" || "$source_hash" != "$stored_hash" ]]; then
  if ! "$FLUTTER_ROOT/bin/dart" --suppress-analytics pub get --offline --enforce-lockfile >/dev/null 2>&1; then
    echo 'error: Cannot resolve the locked SkillDeck CLI dependencies offline.' >&2
    exit 1
  fi
  compilation=$(mktemp -d "$cache_dir/compile.XXXXXX")
  trap 'rm -rf "$compilation"' EXIT
  binaries=()
  for architecture in $architectures; do
    case "$architecture" in
      arm64) dart_arch=arm64 ;;
      x86_64) dart_arch=x64 ;;
      *) echo 'error: Unsupported SkillDeck CLI target architecture.' >&2; exit 1 ;;
    esac
    binary="$compilation/skilldeck.$architecture"
    if [[ "$architecture" == x86_64 && -n "$prebuilt_x86_64" ]]; then
      cp "$prebuilt_x86_64" "$binary"
    elif ! "$FLUTTER_ROOT/bin/dart" --suppress-analytics compile exe bin/skilldeck.dart \
        --target-os=macos --target-arch="$dart_arch" -o "$binary" >/dev/null 2>&1; then
      echo 'error: SkillDeck CLI compilation failed.' >&2
      exit 1
    fi
    binaries+=("$binary")
  done
  if [[ ${#binaries[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$compilation/skilldeck" >/dev/null 2>&1
  else
    mv "${binaries[0]}" "$compilation/skilldeck"
  fi
  chmod 755 "$compilation/skilldeck"
  mv -f "$compilation/skilldeck" "$cache_dir/skilldeck"
  rm -rf "$compilation"
  trap - EXIT
  printf '%s\n' "$source_hash" > "$stamp"
fi

# Sign the staged helper on every build, including an identity change on a hit.
staged=$(mktemp "$cache_dir/bundle.XXXXXX")
trap 'rm -f "$staged"' EXIT
cp "$cache_dir/skilldeck" "$staged"
chmod 755 "$staged"
# Ad hoc when Xcode has no identity, so the entitlements survive a later
# release re-sign that preserves them.
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
timestamp=(--timestamp)
if [[ "$identity" == '-' ]]; then timestamp=(); fi
if ! codesign --force --sign "$identity" --options runtime \
    ${timestamp[@]+"${timestamp[@]}"} \
    --entitlements "$PROJECT_DIR/scripts/skilldeck_cli.entitlements" \
    "$staged" >/dev/null 2>&1; then
  echo 'error: SkillDeck CLI signing failed.' >&2
  exit 1
fi
# The hardened runtime kills a mis-entitled helper only at launch, which
# signing, notarization and codesign --verify all miss.
if [[ " $(lipo -archs "$staged") " == *" $(uname -m) "* ]] &&
    ! "$staged" --help >/dev/null 2>&1; then
  echo 'error: The signed SkillDeck CLI does not launch.' >&2
  exit 1
fi
mkdir -p "$(dirname "$output")"
mv -f "$staged" "$output"
