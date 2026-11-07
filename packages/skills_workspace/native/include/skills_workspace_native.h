#ifndef SKILLS_WORKSPACE_NATIVE_H_
#define SKILLS_WORKSPACE_NATIVE_H_

#include <stdint.h>

#if defined(_WIN32)
#define SKILLS_WORKSPACE_EXPORT __declspec(dllexport)
#else
#define SKILLS_WORKSPACE_EXPORT __attribute__((visibility("default")))
#endif

#if defined(__cplusplus)
extern "C" {
#endif

// Private smoke-test entry point for verifying Native Assets loading.
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_native_ping(void);

// Narrow POSIX durability boundary. Every function returns zero on success or
// the platform errno value on failure. Windows builds retain the symbols for a
// stable Native Assets surface but return ERROR_NOT_SUPPORTED (50).
typedef enum skills_workspace_filesystem_kind {
  SKILLS_WORKSPACE_FILESYSTEM_NOT_FOUND = 0,
  SKILLS_WORKSPACE_FILESYSTEM_FILE = 1,
  SKILLS_WORKSPACE_FILESYSTEM_DIRECTORY = 2,
  SKILLS_WORKSPACE_FILESYSTEM_SYMBOLIC_LINK = 3,
  SKILLS_WORKSPACE_FILESYSTEM_OTHER = 4
} skills_workspace_filesystem_kind;

SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_posix_write_new_at(
    const char *parent_path, const char *entry_name, const uint8_t *bytes,
    intptr_t byte_count);
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_posix_flush_path(
    const char *path, int32_t directory);
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_posix_flush_at(
    const char *parent_path, const char *entry_name, int32_t directory);
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_posix_stat(
    const char *path, int32_t follow_links, uint64_t *device,
    uint64_t *inode, uint32_t *mode, int32_t *kind);
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_posix_chmod(
    const char *path, uint32_t mode);
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_posix_rename_at(
    const char *parent_path, const char *old_name, const char *new_name);
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_posix_exchange_at(
    const char *parent_path, const char *first_name, const char *second_name);

#define SKILLS_WORKSPACE_REVISION_OID_HEX_SIZE 40

typedef enum skills_workspace_revision_status {
  SKILLS_WORKSPACE_REVISION_OK = 0,
  SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT = 1,
  SKILLS_WORKSPACE_REVISION_NOT_INITIALIZED = 2,
  SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE = 3,
  SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE = 4,
  SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE = 5,
  SKILLS_WORKSPACE_REVISION_BUFFER_TOO_SMALL = 6,
  SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE = 7
} skills_workspace_revision_status;

typedef enum skills_workspace_revision_commit_kind {
  SKILLS_WORKSPACE_REVISION_COMMIT_INITIAL = 0,
  SKILLS_WORKSPACE_REVISION_COMMIT_UPSTREAM = 1,
  SKILLS_WORKSPACE_REVISION_COMMIT_EFFECTIVE_UPDATE = 2,
  SKILLS_WORKSPACE_REVISION_COMMIT_LOCAL_PUBLISH = 3,
  SKILLS_WORKSPACE_REVISION_COMMIT_RESTORE_PUBLISH = 4,
  SKILLS_WORKSPACE_REVISION_COMMIT_UPDATE_CANDIDATE = 5
} skills_workspace_revision_commit_kind;

// Initializes the local-only Revision Engine and disables external Git config
// search paths. Calls are reference counted and must be balanced by shutdown.
// Retain an init reference until all of that caller's Revision calls finish.
// Source calls independently hold the shared runtime for their duration. The
// last owner shuts libgit2 down; a later init reapplies the global options.
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_init(void);
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_shutdown(void);

SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_libgit2_version(
    int32_t *major, int32_t *minor, int32_t *revision);

SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_store_create(
    const char *repository_path);
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_store_open_verify(
    const char *repository_path);

SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_blob_create(
    const char *repository_path, const uint8_t *bytes, intptr_t byte_count,
    char *oid_hex, intptr_t oid_hex_capacity);

SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_tree_create_single(
    const char *repository_path, const char *entry_name,
    const char *blob_oid_hex, char *oid_hex, intptr_t oid_hex_capacity);

// Creates one recursively nested tree from normalized regular-file entries.
// Paths use POSIX separators and executable flags map to Git 100755/100644.
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_tree_create(
    const char *repository_path, const char *const *relative_paths,
    const uint8_t *const *file_bytes, const intptr_t *byte_counts,
    const int32_t *executable_flags, intptr_t entry_count, char *oid_hex,
    intptr_t oid_hex_capacity);

// Lists all blobs in a commit or tree object as UTF-8 TSV records:
// path<TAB>mode<TAB>oid<TAB>byte-count<LF>.
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_tree_list(
    const char *repository_path, const char *object_oid_hex, uint8_t *output,
    intptr_t output_capacity, intptr_t *required_capacity);

SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_blob_read(
    const char *repository_path, const char *blob_oid_hex, uint8_t *output,
    intptr_t output_capacity, intptr_t *required_capacity);

SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_commit_create_root(
    const char *repository_path, const char *tree_oid_hex, char *oid_hex,
    intptr_t oid_hex_capacity);

SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_commit_create(
    const char *repository_path, const char *tree_oid_hex,
    const char *const *parent_oid_hex, intptr_t parent_count,
    int32_t commit_kind, char *oid_hex, intptr_t oid_hex_capacity);

SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_commit_verify(
    const char *repository_path, const char *commit_oid_hex,
    const char *expected_tree_oid_hex,
    const char *const *expected_parent_oid_hex, intptr_t expected_parent_count,
    int32_t expected_commit_kind);

SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_commit_is_ancestor(
    const char *repository_path, const char *ancestor_oid_hex,
    const char *descendant_oid_hex, int32_t *is_ancestor);

SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_commit_verify_root(
    const char *repository_path, const char *commit_oid_hex,
    const char *entry_name, const uint8_t *expected_bytes,
    intptr_t expected_byte_count);

// Lists normalized changes as UTF-8 TSV records:
// status<TAB>old-path<TAB>new-path<TAB>old-mode<TAB>new-mode<TAB>binary<LF>.
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_diff(
    const char *repository_path, const char *old_commit_oid_hex,
    const char *new_commit_oid_hex, uint8_t *output,
    intptr_t output_capacity, intptr_t *required_capacity);

// Runs an exact three-tree merge. A clean result returns a tree OID and no
// conflict payload. Conflicts are NUL-separated ancestor/current/incoming path
// triples, with an empty field representing a missing side.
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_merge(
    const char *repository_path, const char *previous_upstream_oid_hex,
    const char *current_effective_oid_hex,
    const char *incoming_upstream_oid_hex, char *tree_oid_hex,
    intptr_t tree_oid_hex_capacity, uint8_t *conflict_output,
    intptr_t conflict_output_capacity, intptr_t *required_conflict_capacity,
    intptr_t *conflict_count);

// Creates the exact `objects.pack` and `objects.idx` payloads for a staged
// Revision Recovery Bundle. The directory must already exist and be empty.
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_recovery_pack_create(
    const char *repository_path, const char *bundle_staging_path,
    const char *const *retained_root_oid_hex, intptr_t retained_root_count);

// Reconstructs a new staged bare Store from a Bundle's pack/index pair and
// verifies every indexed object plus all retained roots without system Git.
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_recovery_pack_restore(
    const char *staged_repository_path, const char *pack_path,
    const char *index_path, const char *const *retained_root_oid_hex,
    intptr_t retained_root_count);

// Replaces the package-owned derived retention references.  Names must use
// the fixed `refs/skills-workspace/` namespace and targets must be commits.
// The operation is set-like: stale refs in that namespace are removed and the
// supplied refs are created or updated.  SQLite remains business authority.
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_revision_retention_refs_replace(
    const char *repository_path, const char *const *ref_names,
    const char *const *target_oid_hex, intptr_t ref_count);

// Git Source transport (ADR-0106). These entry points fetch public Sources
// into a temporary bare repository and read them back. They never touch a
// Revision Store, never persist a remote or credential, and report failures
// only as status classes: no libgit2 message text crosses the boundary.
typedef enum skills_workspace_transport_status {
  SKILLS_WORKSPACE_TRANSPORT_OK = 0,
  SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT = 1,
  SKILLS_WORKSPACE_TRANSPORT_RUNTIME_FAILURE = 2,
  SKILLS_WORKSPACE_TRANSPORT_CANCELLED = 3,
  SKILLS_WORKSPACE_TRANSPORT_AUTHENTICATION_REQUIRED = 4,
  SKILLS_WORKSPACE_TRANSPORT_CERTIFICATE_FAILURE = 5,
  SKILLS_WORKSPACE_TRANSPORT_TLS_FAILURE = 6,
  SKILLS_WORKSPACE_TRANSPORT_NETWORK_FAILURE = 7,
  SKILLS_WORKSPACE_TRANSPORT_TIMED_OUT = 8,
  SKILLS_WORKSPACE_TRANSPORT_REF_NOT_FOUND = 9,
  SKILLS_WORKSPACE_TRANSPORT_REPOSITORY_FAILURE = 10,
  SKILLS_WORKSPACE_TRANSPORT_OBJECT_FAILURE = 11,
  SKILLS_WORKSPACE_TRANSPORT_BUFFER_TOO_SMALL = 12,
  SKILLS_WORKSPACE_TRANSPORT_LIMIT_EXCEEDED = 13,
  SKILLS_WORKSPACE_TRANSPORT_UNSUPPORTED = 14
} skills_workspace_transport_status;

typedef enum skills_workspace_transport_proxy_mode {
  // Connect directly.
  SKILLS_WORKSPACE_TRANSPORT_PROXY_NONE = 0,
  // Honour https_proxy, HTTPS_PROXY, and no_proxy from the environment.
  SKILLS_WORKSPACE_TRANSPORT_PROXY_ENVIRONMENT = 1,
  // Use the proxy URL passed by the caller.
  SKILLS_WORKSPACE_TRANSPORT_PROXY_SPECIFIED = 2
} skills_workspace_transport_proxy_mode;

// Creates a bare repository at repository_path and performs a depth-1,
// tag-free fetch of ref (or the remote HEAD when ref is NULL) from url.
// Redirects are followed only on the initial request. No credentials are
// offered, so a server that requires them yields AUTHENTICATION_REQUIRED.
// The fetch stops with CANCELLED soon after *cancel_flag becomes non-zero.
// On success, writes the fetched commit object ID to oid_hex.
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_transport_fetch(
    const char *repository_path, const char *url, const char *ref,
    int32_t proxy_mode, const char *proxy_url, const int32_t *cancel_flag,
    char *oid_hex, intptr_t oid_hex_capacity);

// Lists every non-tree entry beneath subpath (the whole tree when subpath is
// empty) of a commit, in `git ls-tree -r -z --full-tree` record format:
// mode SP type SP oid TAB full-path NUL. Gitlinks and every mode are reported
// as-is; path bytes are emitted unchanged.
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_transport_tree_list(
    const char *repository_path, const char *commit_oid_hex,
    const char *subpath, uint8_t *output, intptr_t output_capacity,
    intptr_t *required_capacity);

// Reads one blob. Returns LIMIT_EXCEEDED, without copying, when the blob is
// larger than maximum_bytes.
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_transport_blob_read(
    const char *repository_path, const char *blob_oid_hex,
    int64_t maximum_bytes, uint8_t *output, intptr_t output_capacity,
    intptr_t *required_capacity);

// Reports the current user's Windows proxy settings as UTF-8
// proxy TAB bypass TAB auto-config-flag. Other platforms return UNSUPPORTED.
SKILLS_WORKSPACE_EXPORT int32_t skills_workspace_transport_windows_proxy(
    uint8_t *output, intptr_t output_capacity, intptr_t *required_capacity);

#if defined(__cplusplus)
}
#endif

#endif  // SKILLS_WORKSPACE_NATIVE_H_
