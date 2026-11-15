# Skills Workspace Native Boundary

The Native Assets hook builds the vendored libgit2 revision recorded in
`libgit2.lock.json` as a static archive, then links that archive into the
package-owned dynamic Native Asset. Only functions declared in
`include/skills_workspace_native.h` are available to Dart.

## CMake orchestration decision

The Section 4 spike selects direct, pinned CMake orchestration. It was compared
with `native_toolchain_cmake` 0.3.1, whose own README still marks the API as
experimental. The helper is compatible with the current `hooks` and
`code_assets` constraints, but does not replace the project's fixed libgit2
feature switches, archive discovery, dependency recording, or artifact
inspection. Adding it would therefore introduce another evolving build API
without removing project-owned policy. Re-evaluate only if direct orchestration
cannot produce reproducible Windows or Linux artifacts.

The build enables exactly one network transport: HTTPS through the platform's
own TLS stack (ADR-0106).

| Platform | `USE_HTTPS` | Linked system libraries | Trust store |
| --- | --- | --- | --- |
| macOS | `SecureTransport` | Security, CoreFoundation | macOS Keychain |
| Windows | `WinHTTP` | `winhttp`, `rpcrt4`, `crypt32`, `ole32` | Windows certificate store |
| Linux | `OpenSSL-Dynamic` | `dl` only; `libssl` is loaded at run time | distribution OpenSSL defaults |

No CA bundle path is compiled into the artifact, and OpenSSL is never linked
at build time. SSH, GSSAPI, NTLM, the CLI, tests, examples, fuzzers, external
Git config paths, external templates, hooks, filters, and submodule operations
remain disabled or unexposed by the project ABI. Internal Revision Stores never
configure remotes. Network entry points use separate temporary Source, staging
or export repositories.

Public Source fetches install a credential callback that returns `GIT_EAUTH`
without acquiring credentials. This makes authentication challenges explicit
across backends, including WinHTTP, which otherwise reports an unhandled 401
as a generic HTTP error. The recorded WinHTTP project patch also disables
automatic authentication replay so Negotiate challenges cannot send an
Authorization token before the callback runs. Third-party authentication stays
delegated to system Git (ADR-0106).

libgit2's upstream CMake target globs several transport and filter translation
units even when their feature macros are disabled. Their presence in compiler
progress output therefore does not mean that a feature is enabled. After
configuration, the build hook reads the generated `git2_features.h` and fails
closed unless the platform's HTTPS backend macros are defined and every other
transport, credential backend, TLS backend, and iconv macro is absent, and
unless the selected builtin hash, compression, parser, regex, and thread
features are present. `tool/verify_dependency_spikes.dart` cross-checks the
per-platform `USE_HTTPS` values in `libgit2.lock.json` against this policy.

The final Native Asset is additionally linked with an explicit allowlist of
`skills_workspace_*` entry points. The locked `native_toolchain_c` version does
not expose linker options on `CBuilder.library`, so the hook passes a macOS
exported-symbols list or Linux version script as a linker flag. Windows
compiles both the static archive and its consumer with `GIT_STATIC`. The
recorded one-branch vendored-header patch makes libgit2 declarations plain
`extern` in that mode, while only the project shim carries
`__declspec(dllexport)`. This is necessary because MSVC otherwise preserves
libgit2's export linker directives when the static archive is linked into the
package DLL. Thus libgit2's broad C API is not reachable from Dart or another
dynamic-library consumer. Release inspection must still confirm the exact
allowlist with `nm` on macOS/Linux or `dumpbin /exports` on Windows and confirm
that no transport library is dynamically linked.

All libgit2 builds define `SHA1DC_FORCE_ALIGNED_ACCESS`. The bundled SHA1
collision-detection implementation otherwise intentionally reads unaligned
32-bit words on x86; although the processor permits that access, it violates
the C alignment contract and fails UBSAN on real object content. The aligned
path preserves collision detection without suppressing sanitizer findings.

On Windows, the hook deliberately does not use `CBuilder` compiler discovery.
The locked `native_toolchain_c` version decodes `vswhere -utf8` JSON through the
active Windows ANSI code page, which makes localized Visual Studio descriptions
invalid JSON. The project-owned adapter decodes only the UTF-8
`installationPath`, locates Visual Studio's bundled CMake, Ninja, and
`VsDevCmd.bat`, and captures the x64 developer environment without relying on
the caller's shell. CMake explicitly uses the bundled Ninja generator to avoid
Visual Studio 18 MSBuild tracking failures, while the shim is compiled through
the absolute MSVC path from `VCToolsInstallDir`. It links only the pinned static
archive and the required Windows system libraries `ws2_32`, `secur32`,
`advapi32`, `winhttp`, `rpcrt4`, `crypt32`, and `ole32`, then registers the DLL
as the same bundled Code Asset. This path
requires neither a user-installed libgit2 nor CMake or Ninja on the global
`PATH`.

The hook records the immutable vendored source directory and
`libgit2.lock.json` as build dependencies instead of serializing every upstream
test fixture and nested Git fixture as an individual dependency. A libgit2
update must replace the source subtree and update the pin, archive digest, and
build policy in the lock file together.

On macOS both the libgit2 CMake build and the enclosing Native Asset use the
oldest real deployment target for each architecture: 10.15 for x86_64 and 11.0
for arm64, which did not exist in macOS 10.15. The latter flag intentionally
appears in the project flag list because `native_toolchain_c` appends project
flags after the standalone Dart runner's newer default deployment target.
These are compatibility properties of the revision shim, not the minimum for
the Flutter host. The complete example bundle targets macOS 13.0 because
Flutter 3.41.9 Code Assets and the selected bundled SQLite binary target 13.

## Native verification

The private runtime is shared by Revision initialization references and
per-call Source leases. Its mutex serializes the first initialization (including
external-config isolation, User-Agent and timeouts) and final shutdown. Source
leases cover validation, sizing probes and all cleanup paths. Callers must
retain their Revision init reference until their Revision calls finish, and
finish all calls and balance all Revision references before unloading the DLL.
The last owner calls `git_libgit2_shutdown`, which unregisters Windows FLS
destructors before the code containing those destructors can be unloaded.
No cleanup runs under the Windows loader lock. A later owner can reinitialize;
the recorded `settings.c` patch clears freed global setting pointers so applying
the User-Agent again is safe.
Each owner also clears its own thread-error state before releasing its runtime
reference, using the private vendored `errors.c` helper. This avoids leaking a
live thread's error allocation when another thread performs final shutdown:
unlike Windows FLS cleanup, POSIX TLS key deletion does not run destructors for
other threads. No native diagnostic is retained across the project ABI.

The ABI tool also compiles `native/test/runtime_lifecycle_test.c` against the
production runtime with a fault-injected libgit2 boundary. It checks mixed
Source/Revision ownership, every global-option failure, partial init cleanup,
and retry with all restrictions reapplied. The real-library ABI harness races
Source reads against Revision restart, then repeats Source-only lifetimes and
unloads the library. Windows also repeats actual DLL load/use/unload cycles;
the tested macOS ASAN runtime reports duplicate globals when the same
instrumented dylib is reloaded after `dlclose`, so repeated image reload is a
Windows-specific addition to the existing all-platform final-unload gate.

`native/test/revision_engine_abi_test.c` loads the finished dynamic Native
Asset directly. It verifies fail-closed calls before initialization, repeated
initialization/shutdown, the 1.9.7 pin, Store/blob/tree/root-commit operations,
derived retention-ref replacement and namespace confinement, invalid-input
cleanup, unload, and Store rename after shutdown. Run it through:

```bash
dart run tool/run_native_abi_test.dart
```

Pass `--artifact <release-library>` to test the exact bundled release library.
`tool/inspect_native_artifact.dart` independently verifies the architecture,
export allowlist, deployment target, and absence of dynamic libgit2, SQLite,
OpenSSL, libssh, and libcurl dependencies.

The tracked `sanitizers.config` file defaults to `none`. Release-gate jobs keep
that Native Assets mode disabled and run the pure-Dart ABI tool from the
monorepo root:

```bash
dart packages/skills_workspace/tool/run_native_abi_test.dart --sanitized
```

The tool uses the same build policy as the hook, but directly builds a temporary
instrumented libgit2 archive and dynamic shim before compiling the C ABI harness
with the identical ASAN/UBSAN flags. This avoids asking Dart Native Assets to
install or rewrite an instrumented library before the harness starts, which is
not reliable across macOS toolchain versions. Unsupported names and Windows
sanitizer requests fail closed. `configure_native_sanitizers.dart` remains
available for explicit hook experiments, and those experiments must restore the
tracked mode to `none` afterward.

## Ephemeral repository object transport

The private `RepositoryTransportNativePort` is distinct from public Source
acquisition. `fetchInto` and `push` run through the same Native Asset in a worker
isolate, against an existing private bare staging/export repository. They do not
select an Effective Revision or perform a Workspace lifecycle operation. The
caller supplies explicit source/destination refspecs and operation-scoped custom
headers; auth renewal, remote authorization, retries and outcome reconciliation
belong to the caller outside Workspace.

The shim creates anonymous remotes only, never writes remote configuration,
never updates `FETCH_HEAD`, uses a fixed credential-free reflog message and
refuses implicit credentials. HTTPS URLs must have no userinfo, query or
fragment. All redirects, including same-host port/path redirects, are refused.
Plain HTTP is available only for explicit loopback qualification against
`127.0.0.1`. There is no authenticated system-Git fallback. Native header copies
are cleared when the worker returns; immutable Dart input strings remain subject
to Dart's normal memory lifetime and are never logged or persisted.

Each requested ref has an accepted/rejected/unreported result. A libgit2 overall
zero without every ref accepted produces `outcomeUnknown`; a server rejection
produces `rejectedRef` without copying the server's status text. Native pack,
transfer and status callbacks inspect the operation's own cancellation flag.
Cancellation or a network failure may leave remote objects/refs, so callers must
query and reconcile; local cancellation is never evidence of server rollback.

The vendored patches for strict redirect refusal and disabled `FETCH_HEAD`
updates are recorded in `libgit2.lock.json` and `THIRD_PARTY_NOTICES.md`. Existing
public Source acquisition keeps its initial-redirect and shallow-fetch policy.

Run the formal Dart/FFI/smart-HTTP qualification from this package:

```sh
dart test -j 1 test/native/repository_transport_native_test.dart
```

The tests create disposable repositories and random in-memory test credentials,
including mixed per-ref rejection, exact retry, complete-history fetch,
credential isolation, same-host redirects, existing-file preservation and
cancellation during an upload. Local smart-HTTP evidence is separate from
Artifacts/HTTPS service and cross-platform acceptance.

`tool/qualify_repository_transport.dart` qualifies the same shim against a real
HTTPS Git host. A parent process supplies one JSON object on stdin with `remote`
and `token`; optional `fixturePath` is only a parent directory for a fresh child
fixture. Never put the token in arguments, environment, a file, or a URL. The
probe emits one safe JSON result, creates local Git fixtures only, and removes
its own fixture in `finally`. It does not create or delete remote repositories;
the resource owner must clean up that exact temporary remote separately.

The probe uses the optional caller-owned native int64 transfer counter. Native
callbacks reset/update it; the caller sets its operation's cancellation flag
only after bytes are observed. As with cancellation memory, the caller releases
the counter only after the worker returns. Real-host acceptance, local per-ref
rejection qualification, and long-term reliability measurements remain separate
evidence.

## Immutable object graph inspection and import

`RevisionEnginePort.inspectCommit` returns the tree and all ordered parent IDs,
including every merge parent, without author/message text. Its metadata and
parent budgets are explicit `RevisionCommitInspectionLimits`; 64 KiB/64 parents
are defaults for this new seam, and callers may increase them. A budget failure
is `limitExceeded`, never evidence of corrupt content.

`importObjects` reads an isolated bare staging repository and an exact root set.
It checks every reachable commit/tree/blob's type, hash, connectivity and byte
budgets before the first canonical write. Its source ODB uses only that staging
repository's own loose/pack backends; alternates cannot borrow missing objects
from a canonical Store. Copying re-reads and hashes every object, writes those
verified bytes, checks the resulting OID, and re-reads the target for verification.
The operation never writes refs, HEAD, configuration, reflogs or SQLite selection.

`RevisionObjectImportLimits` configures object count, per-object and aggregate
bytes, commit metadata bytes and parent count. The new import seam additionally
has native operational caps of one million objects, 256 MiB per object and 8 GiB
total, reported as `limitExceeded`. These limits do not change legacy recovery
budgets. Worker cancellation uses an operation-owned native flag; failure or
cancellation during copying may leave unreferenced immutable objects. Selection,
retention and any business commit belong to the caller's Workspace transaction.

Recovery pack creation walks the full ancestry of every retained root, including
all sides of merges, and includes their trees/blobs while excluding unrelated
objects. `git_packbuilder_insert_recur(commit)` alone does not include parents.
Restoration now validates complete reachable ancestry before reporting success.
Old packs missing a parent or ancestor tree fail with `bundleInvalid`; restoration
does not invent or fetch missing history. Existing valid recovery packs are not
subject to the new inspection/import defaults and are not rewritten automatically.
The caller owns disposal of a rejected staged Store and must never select it.

Run the graph and existing recovery/worker qualification with:

```sh
dart test -j 1 test/native/revision_object_import_native_test.dart \
  test/revision_history/revision_history_native_test.dart \
  test/native/recovery_pack_paths_test.dart test/runtime/revision_worker_test.dart \
  test/runtime/revision_worker_runtime_test.dart \
  integration_test/native_revision_worker_integration_test.dart
```

## Public committed-revision transfer

`SkillsRepository` exposes `captureAuthoritativeState`, `exportCommittedRevision`,
`prepareIncomingRevision`, `pushCommittedRevision`, `fetchIncomingRevision`, and
transactional incoming apply/install/replacement. Transfer DTOs live in the domain
layer and the API barrel reexports them. The manifest carries Source provenance,
independent Upstream/Effective roots, and immutable published-event descriptors.
It contains neither local Workspace identity nor pack-layout hashes. Imported
history has an explicit imported origin; it does not fabricate local operations.

Fetch uses bounded Git smart HTTP: protocol v2 requests exact ref prefixes, with a
bounded v0 fallback, and streams raw sideband pack bytes into registered owned
staging before native indexing. Pack preflight inflates through fixed buffers,
checks declared and actual object/delta budgets, and validates indexed REF/OFS
dependencies and cycles. Before an index exists, the conservative total delta
count limit bounds possible REF depth; exact dependencies are checked after
indexing. No authenticated system-Git fallback is used. Push retains only the two
current roots; reachable published history must belong to their complete graph.

The development payload limit is 64 MiB for combined pack/index bytes, with a
4 MiB manifest and 10,000 history events. This is not a process-memory limit:
immutable DTOs, codec validation and isolate messaging can create multiple copies.
Network staging is registered before use, reconciled on recovery/capture, and
cancelled/drained before owner Removal or Source Replacement. Native socket waits
retain the platform's 60-second idle bound; the destruction drain bound is 70
seconds outside the writer lock.

Schema 4 is a reader/writer downgrade barrier. Migration from supported schemas
preserves domain rows and mints a Workspace UUID and recovery-incarnation UUID.
Normal reopen preserves both; verified primary restoration changes only the
incarnation in the staged database before promotion. Capture permits absence as
deletion evidence only when all proof flags and caller scope match. Caller-bound
reservations and transactional outcome receipts distinguish an exact applied
command from unchanged content, unknown state, or later edits.

Finalization publishes a same-revision Completed-Journal backup before owned
physical cleanup. Destructive finalization then publishes a clean cloned backup
that omits the proven completed Journal/steps, using secure deletion and VACUUM,
prior to deleting the live Journal. This adds an ordinary terminal backup and an
additional normalized clone for destruction. Any failed checkpoint or cleanup
returns committed finalization pending and resumes through the same recovery
protocol. Atomic Extra Data patches and independent Personal Tag mutations use
receiver-issued command bindings and exact receipts; name collisions stay typed
pending/conflict outcomes. Dirty Drafts, active Sessions, divergent history,
stale scope, and unsupported slot changes remain explicit pending boundaries.

Windows internal Revision and object-transport handles add a memory-only
`core.longpaths=true` backend. Repository-open and repository-less filesystem
iterator bounds match the existing NT-prefixed backend, counting UTF-16 units
and reserving the terminator. Public Source workdir policy and on-disk config
bytes are unchanged. Long paths containing Chinese and surrogate-pair emoji,
bounded pack restoration, and rejection beyond the actual backend capacity are
covered by `recovery_pack_paths_test.dart`.

The separate `integration_test/long_workspace_transfer_qualification_test.dart`
is an explicit qualification of an entire Workspace root above 320 characters.
It currently fails during existing Windows Control Plane startup before transfer;
its failure is retained as a platform boundary, not counted as a passed or skipped
ordinary test. The ordinary public transfer tests and native long-object-path
qualification do not establish support for an entire Workspace root of that size.

Unattended callers set `RemoveRequest.requireCleanDraft=true`. The writer checks
current Draft bytes and active Update Candidate Sessions; clean-Draft physical
fingerprints protect both sides of recovery capture and the pre-commit applying
boundary. Only marked Draft entries preserve a later external generation during
rollback, restoring every other transaction resource; post-commit edits remain
committed-finalization-pending and never reverse a completed business deletion.
Source Replacement uses the same clean-generation capture protection.

A freshly reserved command whose metadata/vocabulary already matches the request
records an exact scoped receipt at the current Repository Revision, without a
new Operation Record or publication. Unknown commands cannot claim that receipt
from matching values. Equal Upstream/Effective roots still import missing remote
published events transactionally, retaining independent local history; only a
fully represented history can take the unchanged path.

Schema 3 → 4 migration occurs when this package opens a Workspace, independently
of an App Cloud feature flag. Turning that flag off does not make an older App
safe to open the migrated database. Older readers must fail closed at the schema
barrier. This work has opened and migrated only disposable test fixtures, not a
user's real Workspace. Review the schema, imported-history tables, scoped outcome
receipts and destructive cleanup protocol together before any user-data trial.

Use the isolated integration checkout and self-cleaning fixtures for qualification:

```sh
cd /Users/tilapia/TilapiaFiles/Projects/App/SkillsManager/skilldeck-cloud-integration/packages/skills_workspace
PUB_HOSTED_URL=https://pub.dev dart test -j1 test/api/revision_transfer_e2e_test.dart test/infrastructure/operations/guarded_removal_race_test.dart
```

These tests create `revision-transfer-e2e-*` and `guarded-removal-race-*` roots in
the platform temporary directory. The second Windows qualification uses only
`%TEMP%\skilldeck-guard-final-20261115-8f470ae1` and disposable fixture siblings;
it does not modify the system Dart installation or user pub cache.

An old recovery pack may already lack parent/ancestor objects because the former
packbuilder call omitted ancestry. New restoration reports `bundleInvalid`
rather than fabricating history or silently accepting a partial graph. It retains
the authoritative source bundle as failure evidence; only rejected owned staging
is disposable. A healthy canonical Store can produce a complete new bundle during
normal Workspace maintenance. There is no automatic rewrite that destroys old
backup evidence to conceal an incomplete legacy pack.
