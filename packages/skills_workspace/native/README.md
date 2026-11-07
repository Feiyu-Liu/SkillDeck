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
configure remotes; only the separate Source transport entry points use the
network.

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
