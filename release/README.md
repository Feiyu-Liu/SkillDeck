# SkillDeck desktop releases

Run from the monorepo root on the macOS signing host. The ignored local
`keys/desktop-release.json` configures target architecture, renderer, updater
feeds, DMG geometry and Windows build host. The tracked
`release/desktop.example.json` documents the configuration schema with placeholder
destinations only; it is not a publishing configuration. Version/build remain
explicit arguments; no version is inferred from another platform's appcast.
The source defaults to committed HEAD, not dirty files or local dependency overrides.

On a new signing host, create a local config only if one does not already exist:

```sh
mkdir -p keys
# Never overwrite an existing private configuration.
test -e keys/desktop-release.json || cp release/desktop.example.json keys/desktop-release.json
```

Edit that local file to supply your own bucket, public download domain, object
prefix and all target index keys, SSH host/project path and signing account.
Do not publish with placeholders. Both config locations are one directory below
the repository root, so `project_root: ".."` resolves identically. Other paths
in the config resolve from that project root. Keep real infrastructure settings,
defines and signing material under ignored `keys/`; do not commit them.
`plan` and `prepare` default to the local config and fail if it is missing.
They also accept `--config /absolute/path/to/config.json` or
`--config=/absolute/path/to/config.json`; there is no automatic example fallback.

Windows releases require `"build_version_define": "SKILLDECK_BUILD_VERSION"`
in the local release config and the matching release-tool implementation. New
Windows `plan`/`prepare` commands fail before invoking the backend when this
contract is missing; saved-run resume retains its frozen inputs. The
runner generates `x.y.z+n` from the same version/build inputs as both Windows
appcast fields. The App awaits this compiled installed identity before updater
initialization; a configured Windows updater refuses to start if it is absent
or invalid. Development without an update feed needs no release identity.
ProductVersion remains `x.y.z+n`, and FileVersion remains `x.y.z.n`.

The Windows build receipt records the generated build-input comparison identity and resolved Git dependency
revisions. Metadata creation requires the receipt identity to match the feed.
These build-input checks do not replace testing the actual installed App. See
`docs/validation/windows-comparison-version.md` for current evidence and gaps.

Once per machine, set `MACOS_RELEASE_SKILL` to the maintained
`macos-signed-release` checkout, or store `{"skill_root":"/absolute/skill/path"}`
in ignored `keys/release-tools.json`. Configure your own local checkout path.
This deliberately avoids silently running an older SkillDeck-managed copy.
The external automation and its build/signing/upload dependencies are not
bundled in this repository; install and review them separately. The wrapper
forwards CLI help to that automation.

This publication candidate has no active release CI and is not a ready-to-run
community publishing setup. Review destinations and host settings before using
it. Source-archive delivery remains a publication gate; this snapshot does not
complete it. Removing local configuration from the current tree does not remove
its contents from prior Git commits; history cleanup requires a separate decision.

```sh
# Offline preview. Replace example version/build with the intended release.
python3 tool/release.py plan --target macos-arm64 --version 1.0.7 --build-number 8

# Prepare only: no publication or change to the installed application.
python3 tool/release.py prepare --target macos-arm64 --version 1.0.7 --build-number 8

# Production publication after approval; accepted existing DMG layout can be reused.
python3 tool/release.py publish --run-dir /absolute/SkillDeck/dist/desktop-release-... --approve-dmg-layout

# Already-authorized build + publication in one command.
python3 tool/release.py prepare --target macos-arm64 --version 1.0.7 --build-number 8 --publish --approve-dmg-layout

python3 tool/release.py status --run-dir /absolute/SkillDeck/dist/desktop-release-...
python3 tool/release.py resume --run-dir /absolute/SkillDeck/dist/desktop-release-...

# Retry a failed tag push, or tag an earlier published run.
python3 tool/release.py tag --run-dir /absolute/SkillDeck/dist/desktop-release-...
```

After a run reaches `published`, the wrapper tags its source commit with an
annotated `v<version>` tag and pushes it to origin. All targets of one version
share the tag; a target built from a different commit reports the mismatch and
leaves the existing tag in place. Tag pushes are network writes and should be
performed only against your intended release remote; this candidate has no
active release CI.

Set `public_base_url` to a domain you control that serves the configured bucket.
If an existing installation uses an older feed hostname, preserve that hostname
and its feed objects while those installations remain supported. Publication
writes bucket keys, not hostnames.

Other targets are `macos-x86_64` (Skia, `FLTEnableImpeller=false`) and
`windows-x64` (unsigned Authenticode, signed WinSparkle installer). Windows
builds the exact commit in a separate worktree over SSH, returns a hash-checked
installer, and signs it on the macOS host; updater private keys stay local.
The commit must be fetchable from origin on the Windows host. This does not
close or replace an installed app. Both hosts need Flutter, Windows needs
Inno/Visual Studio, and the signing host needs Python 3.9+, the existing macOS
release tools, OpenSSL and authenticated Wrangler v4.

Dart cannot cross-compile the bundled `skilldeck` CLI for macOS, so an arm64
host preparing `macos-x86_64` needs its x86_64 slice from an Intel Mac. Compile
`packages/skilldeck_cli` there from the release commit with the pinned Dart
(`dart compile exe bin/skilldeck.dart --target-os=macos --target-arch=x64`),
copy the binary back, and pass its absolute path as `SKILLDECK_CLI_X86_64` to
`prepare`. The build uses it unsigned and signs the merged helper itself.

Private build defines come from the config's `define_file`, by default
`keys/release-defines.json`. Create it locally with the build settings your app
needs (an empty JSON object is sufficient if no additional settings are needed).
The external release backend reads it and overrides the feed and version for
the selected target; the wrapper has no production analytics URL/site policy.
Signing identity/profile files remain under `keys/`; no secret values belong in
the tracked example or build defines. Keep provider and signing credentials out
of all build-time configuration.

The DMG's 800×400 content area, 108px icons and (230,225)/(570,225) positions
were read back from the accepted 1.0.2+12 image. arm64 publication also updates
the legacy shared feed while preserving its Windows entry. Intel has its own
feed. Windows retains the shared feed and initializes `latest-windows.json`
only when R2 proves that this specifically configured object is absent.
The existing landing-page Windows link is separately maintained; generating
latest-windows.json does not deploy or change that page.

Recovery retains signed archives, final artifacts, hashes and Apple submission
IDs under the run directory. Resume reuses completed hash-checked stages. A
lost submission response without an ID requires matching Apple history to the
recorded archive before `attach-notary`; it never blindly submits a duplicate.
Resume a preparation separately from publication unless `--publish` was
explicitly requested for the original preparation. Each run stores its own
hash-protected automation snapshot; resume automatically uses it even after
the installed skill is updated. `publish`, `resume` and `status` use the run's
saved configuration and do not require the default local config to exist.
They still need the configured external automation entrypoint to dispatch to
the saved snapshot; the snapshot may require the original private inputs.

Use one signing/publication host at a time. The project lock serializes local
runs and indexes are re-read before overwrite; R2 publication is not a
cross-host atomic transaction. Partial index publication is recovered by
resuming the same run, with backed-up previous indexes retained for diagnosis.
Clean-machine installation, visual checks after layout changes, and real N-1
updates remain acceptance tests, separate from a successful script run.

Offline wrapper regressions use temporary projects and a fake external backend,
without reading real credentials or building, signing, uploading or tagging:

```sh
python3 -I tool/tests/test_release.py -v
```
