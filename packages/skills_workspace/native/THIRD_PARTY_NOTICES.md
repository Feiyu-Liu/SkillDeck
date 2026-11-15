# Third-Party Notices

The repository-wide source and per-binary inventories, including unresolved
legal questions, are in [THIRD_PARTY_NOTICES.md](../../../THIRD_PARTY_NOTICES.md).

The vendored source also includes xdiff (LGPL-2.1-or-later), zlib (Zlib),
PCRE2 (BSD), llhttp (MIT), SHA1 collision detection (MIT), wildmatch,
ntlmclient (MIT), and Wine WinHTTP definitions (LGPL-2.1-or-later). Their
copyright notices and full terms are in `third_party/libgit2/COPYING` and the
component license files. The selected binary components and platform-specific
exclusions are recorded in the root inventory.

## libgit2

The vendored `third_party/libgit2` tree is libgit2 v1.9.7 at commit
`49e408b3208bc3093757a1c2db938d3590f3f412`.

- Source: <https://github.com/libgit2/libgit2>
- License: GPL-2.0-only with the libgit2 linking exception
- License text: `third_party/libgit2/COPYING`

The package links libgit2 into its private native library. Its HTTPS transport
is enabled with the operating system's TLS stack (SecureTransport on macOS,
WinHTTP on Windows, and the distribution's OpenSSL loaded at run time on
Linux); no third-party TLS library is bundled. SSH, the CLI, external Git
configuration, external templates, hooks, filters, and submodule operations are
outside the exposed ABI.

The vendored source carries nine project patches recorded in
`libgit2.lock.json`:

- When `GIT_STATIC` is defined, public libgit2 declarations are ordinary
  `extern` declarations. This prevents MSVC from exporting the embedded
  library's broad public API from the package-owned DLL; this patch does not
  change libgit2 runtime behavior.
- The WinHTTP transport disables automatic authentication replay on its
  requests and preserves authentication-scheme errors as `GIT_EAUTH`.
  Public Source acquisition stays anonymous, including on hosts
  offering integrated Windows authentication. The project shim explicitly
  refuses credential acquisition with `GIT_EAUTH`; third-party private-source
  authentication remains delegated to system Git.
- Global settings shutdown clears the freed User-Agent, product, and cipher
  pointers so later initialization and option assignment cannot double-free
  values retained from the previous runtime lifetime.
- A private, non-exported error-state cleanup helper lets each runtime owner
  release its thread-local diagnostics before another thread shuts libgit2
  down. POSIX TLS key deletion alone does not free other live threads' values.
- Both HTTP backends reject every redirect when `GIT_REMOTE_REDIRECT_NONE`
  is requested, including same-host redirects to a different port or path.
  This isolates ephemeral custom headers to the caller-supplied endpoint.
- Fetches with `GIT_REMOTE_UPDATE_FETCHHEAD` disabled do not create or
  truncate `FETCH_HEAD`; the upstream code otherwise creates an empty file.

- Windows repository-path validation uses the extended Win32 backend capacity,
  counts UTF-16 units including surrogate pairs and reserves the terminator,
  instead of rejecting valid nested repositories at the legacy 260-character
  boundary. The backend already uses NT-prefixed paths; other platforms keep
  their existing behavior.

The project shim additionally overlays `core.longpaths=true` in memory on
Windows-owned repository handles. This enables the existing extended-path pack
backend without writing configuration or changing user Git settings.

- Repository-less filesystem iterators, including bare-reference enumeration
  during pack building, use the same extended UTF-16 backend bound. Paths
  associated with a repository retain its workdir `core.longpaths` policy.
