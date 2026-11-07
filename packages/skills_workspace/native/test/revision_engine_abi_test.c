#include "skills_workspace_native.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE skills_workspace_library;
#define LOAD_LIBRARY(path) LoadLibraryA(path)
#define LOAD_SYMBOL(library, name) GetProcAddress(library, name)
static int close_library(skills_workspace_library library) {
  return FreeLibrary(library) != 0;
}
#else
#include <dlfcn.h>
#include <pthread.h>
typedef void *skills_workspace_library;
#define LOAD_LIBRARY(path) dlopen(path, RTLD_NOW | RTLD_LOCAL)
#define LOAD_SYMBOL(library, name) dlsym(library, name)
static int close_library(skills_workspace_library library) {
  return dlclose(library) == 0;
}
#endif

#define CLOSE_LIBRARY(library) close_library(library)

typedef int32_t (*revision_init_fn)(void);
typedef int32_t (*revision_shutdown_fn)(void);
typedef int32_t (*revision_version_fn)(int32_t *, int32_t *, int32_t *);
typedef int32_t (*store_create_fn)(const char *);
typedef int32_t (*store_verify_fn)(const char *);
typedef int32_t (*blob_create_fn)(const char *, const uint8_t *, intptr_t,
                                  char *, intptr_t);
typedef int32_t (*tree_create_single_fn)(const char *, const char *,
                                         const char *, char *, intptr_t);
typedef int32_t (*commit_create_root_fn)(const char *, const char *, char *,
                                         intptr_t);
typedef int32_t (*commit_verify_root_fn)(const char *, const char *,
                                         const char *, const uint8_t *,
                                         intptr_t);
typedef int32_t (*retention_refs_replace_fn)(
    const char *, const char *const *, const char *const *, intptr_t);
typedef int32_t (*transport_fetch_fn)(const char *, const char *,
                                      const char *, int32_t, const char *,
                                      const int32_t *, char *, intptr_t);
typedef int32_t (*transport_tree_list_fn)(const char *, const char *,
                                          const char *, uint8_t *, intptr_t,
                                          intptr_t *);
typedef int32_t (*transport_blob_read_fn)(const char *, const char *, int64_t,
                                          uint8_t *, intptr_t, intptr_t *);
typedef int32_t (*transport_windows_proxy_fn)(uint8_t *, intptr_t,
                                              intptr_t *);

static int fail(const char *message) {
  fprintf(stderr, "native ABI test failed: %s\n", message);
  return 1;
}

static void *required_symbol(skills_workspace_library library,
                             const char *name) {
  void *symbol = (void *)LOAD_SYMBOL(library, name);
  if (symbol == NULL) {
    fprintf(stderr, "native ABI test missing symbol: %s\n", name);
  }
  return symbol;
}

typedef struct {
  transport_blob_read_fn read;
  const char *store;
  const char *oid;
  int failed;
} source_thread_context;

#if defined(_WIN32)
static DWORD WINAPI exercise_source_thread(LPVOID payload) {
#else
static void *exercise_source_thread(void *payload) {
#endif
  source_thread_context *context = (source_thread_context *)payload;
  uint8_t bytes[256];
  intptr_t required;
  int i;
  for (i = 0; i < 128; i++) {
    if (context->read(context->store, context->oid, sizeof(bytes), bytes,
                       sizeof(bytes), &required) !=
        SKILLS_WORKSPACE_TRANSPORT_OK) {
      context->failed = 1;
      break;
    }
    // An invalid OID sets libgit2 thread-local error state too.
    if (context->read(context->store, "invalid", sizeof(bytes), bytes,
                       sizeof(bytes), &required) !=
        SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT) {
      context->failed = 1;
      break;
    }
  }
  return 0;
}

int main(int argc, char **argv) {
  static const uint8_t content[] =
      "# Native ABI\n\nDirect C boundary verification.\n";
  char blob_oid[SKILLS_WORKSPACE_REVISION_OID_HEX_SIZE + 1] = {0};
  char tree_oid[SKILLS_WORKSPACE_REVISION_OID_HEX_SIZE + 1] = {0};
  char commit_oid[SKILLS_WORKSPACE_REVISION_OID_HEX_SIZE + 1] = {0};
  int32_t major = 0;
  int32_t minor = 0;
  int32_t revision = 0;

  if (argc != 4) {
    return fail("usage: revision_engine_abi_test <library> <store> <renamed>");
  }

  skills_workspace_library library = LOAD_LIBRARY(argv[1]);
  if (library == NULL) {
    return fail("could not load the package-owned Native Asset");
  }

#define REQUIRE_FUNCTION(variable, type, symbol_name)                         \
  type variable = (type)required_symbol(library, symbol_name);                 \
  if (variable == NULL) {                                                      \
    CLOSE_LIBRARY(library);                                                    \
    return 1;                                                                  \
  }

  REQUIRE_FUNCTION(revision_init, revision_init_fn,
                   "skills_workspace_revision_init");
  REQUIRE_FUNCTION(revision_shutdown, revision_shutdown_fn,
                   "skills_workspace_revision_shutdown");
  REQUIRE_FUNCTION(revision_version, revision_version_fn,
                   "skills_workspace_revision_libgit2_version");
  REQUIRE_FUNCTION(store_create, store_create_fn,
                   "skills_workspace_revision_store_create");
  REQUIRE_FUNCTION(store_verify, store_verify_fn,
                   "skills_workspace_revision_store_open_verify");
  REQUIRE_FUNCTION(blob_create, blob_create_fn,
                   "skills_workspace_revision_blob_create");
  REQUIRE_FUNCTION(tree_create_single, tree_create_single_fn,
                   "skills_workspace_revision_tree_create_single");
  REQUIRE_FUNCTION(commit_create_root, commit_create_root_fn,
                   "skills_workspace_revision_commit_create_root");
  REQUIRE_FUNCTION(commit_verify_root, commit_verify_root_fn,
                   "skills_workspace_revision_commit_verify_root");
  REQUIRE_FUNCTION(retention_refs_replace, retention_refs_replace_fn,
                   "skills_workspace_revision_retention_refs_replace");
  REQUIRE_FUNCTION(transport_fetch, transport_fetch_fn,
                   "skills_workspace_transport_fetch");
  REQUIRE_FUNCTION(transport_tree_list, transport_tree_list_fn,
                   "skills_workspace_transport_tree_list");
  REQUIRE_FUNCTION(transport_blob_read, transport_blob_read_fn,
                   "skills_workspace_transport_blob_read");
  REQUIRE_FUNCTION(transport_windows_proxy, transport_windows_proxy_fn,
                   "skills_workspace_transport_windows_proxy");

  if (store_verify(argv[2]) != SKILLS_WORKSPACE_REVISION_NOT_INITIALIZED) {
    CLOSE_LIBRARY(library);
    return fail("an uninitialized call did not fail closed");
  }
  if (revision_shutdown() != SKILLS_WORKSPACE_REVISION_NOT_INITIALIZED) {
    CLOSE_LIBRARY(library);
    return fail("unbalanced shutdown did not fail closed");
  }
  if (revision_init() != SKILLS_WORKSPACE_REVISION_OK ||
      revision_init() != SKILLS_WORKSPACE_REVISION_OK) {
    CLOSE_LIBRARY(library);
    return fail("repeated initialization failed");
  }
  if (revision_version(&major, &minor, &revision) !=
          SKILLS_WORKSPACE_REVISION_OK ||
      major != 1 || minor != 9 || revision != 7) {
    CLOSE_LIBRARY(library);
    return fail("the embedded libgit2 pin is not 1.9.7");
  }
  if (store_create(argv[2]) != SKILLS_WORKSPACE_REVISION_OK ||
      store_verify(argv[2]) != SKILLS_WORKSPACE_REVISION_OK) {
    CLOSE_LIBRARY(library);
    return fail("bare Store create/open verification failed");
  }
  if (blob_create(argv[2], content, (intptr_t)(sizeof(content) - 1), blob_oid,
                  (intptr_t)sizeof(blob_oid)) !=
      SKILLS_WORKSPACE_REVISION_OK) {
    CLOSE_LIBRARY(library);
    return fail("blob creation failed");
  }
  if (tree_create_single(argv[2], "SKILL.md", blob_oid, tree_oid,
                         (intptr_t)sizeof(tree_oid)) !=
      SKILLS_WORKSPACE_REVISION_OK) {
    CLOSE_LIBRARY(library);
    return fail("tree creation failed");
  }
  if (commit_create_root(argv[2], tree_oid, commit_oid,
                         (intptr_t)sizeof(commit_oid)) !=
          SKILLS_WORKSPACE_REVISION_OK ||
      commit_verify_root(argv[2], commit_oid, "SKILL.md", content,
                         (intptr_t)(sizeof(content) - 1)) !=
          SKILLS_WORKSPACE_REVISION_OK) {
    CLOSE_LIBRARY(library);
    return fail("root commit creation or verification failed");
  }
  {
    const char *names[] = {
        "refs/skills-workspace/current/abi/effective"};
    const char *targets[] = {commit_oid};
    if (retention_refs_replace(argv[2], names, targets, 1) !=
            SKILLS_WORKSPACE_REVISION_OK ||
        retention_refs_replace(argv[2], NULL, NULL, 0) !=
            SKILLS_WORKSPACE_REVISION_OK) {
      CLOSE_LIBRARY(library);
      return fail("retention reference replacement failed");
    }
    names[0] = "refs/heads/not-owned";
    if (retention_refs_replace(argv[2], names, targets, 1) !=
        SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT) {
      CLOSE_LIBRARY(library);
      return fail("retention reference namespace did not fail closed");
    }
  }
  {
    char expected[128];
    uint8_t listing[256];
    uint8_t bytes[sizeof(content)];
    char fetched[SKILLS_WORKSPACE_REVISION_OID_HEX_SIZE + 1] = {0};
    char fetch_path[4096];
    intptr_t required = 0;
    int32_t cancelled = 1;
    int expected_length = snprintf(expected, sizeof(expected),
                                   "100644 blob %s\tSKILL.md", blob_oid);

    if (expected_length < 0 ||
        transport_tree_list(argv[2], commit_oid, "", NULL, 0, &required) !=
            SKILLS_WORKSPACE_TRANSPORT_BUFFER_TOO_SMALL ||
        required != expected_length + 1 ||
        transport_tree_list(argv[2], commit_oid, "", listing,
                            (intptr_t)sizeof(listing), &required) !=
            SKILLS_WORKSPACE_TRANSPORT_OK ||
        memcmp(listing, expected, (size_t)expected_length + 1) != 0) {
      CLOSE_LIBRARY(library);
      return fail("transport tree listing did not match ls-tree records");
    }
    if (transport_tree_list(argv[2], commit_oid, "missing", listing,
                            (intptr_t)sizeof(listing), &required) !=
            SKILLS_WORKSPACE_TRANSPORT_OK ||
        required != 0) {
      CLOSE_LIBRARY(library);
      return fail("a missing transport selection was not empty");
    }
    if (transport_blob_read(argv[2], blob_oid, 4, bytes,
                            (intptr_t)sizeof(bytes), &required) !=
            SKILLS_WORKSPACE_TRANSPORT_LIMIT_EXCEEDED ||
        transport_blob_read(argv[2], blob_oid, (int64_t)sizeof(bytes), bytes,
                            (intptr_t)sizeof(bytes), &required) !=
            SKILLS_WORKSPACE_TRANSPORT_OK ||
        required != (intptr_t)(sizeof(content) - 1) ||
        memcmp(bytes, content, sizeof(content) - 1) != 0) {
      CLOSE_LIBRARY(library);
      return fail("transport blob read did not honour its bound");
    }
    if (snprintf(fetch_path, sizeof(fetch_path), "%s-fetch.git", argv[2]) <=
        0) {
      CLOSE_LIBRARY(library);
      return fail("could not form the transport fetch path");
    }
    if (transport_fetch(fetch_path, NULL, NULL, 0, NULL, NULL, fetched,
                        (intptr_t)sizeof(fetched)) !=
            SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT ||
        transport_fetch(fetch_path, "https://example.invalid/r.git", NULL,
                        SKILLS_WORKSPACE_TRANSPORT_PROXY_SPECIFIED, NULL, NULL,
                        fetched, (intptr_t)sizeof(fetched)) !=
            SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT ||
        transport_fetch(fetch_path, "https://example.invalid/r.git", NULL,
                        SKILLS_WORKSPACE_TRANSPORT_PROXY_NONE, NULL,
                        &cancelled, fetched, (intptr_t)sizeof(fetched)) !=
            SKILLS_WORKSPACE_TRANSPORT_CANCELLED) {
      CLOSE_LIBRARY(library);
      return fail("transport fetch arguments did not fail closed");
    }
    {
      int32_t proxy = transport_windows_proxy(NULL, 0, &required);
#if defined(_WIN32)
      if (proxy != SKILLS_WORKSPACE_TRANSPORT_BUFFER_TOO_SMALL ||
          required < 3) {
#else
      if (proxy != SKILLS_WORKSPACE_TRANSPORT_UNSUPPORTED) {
#endif
        CLOSE_LIBRARY(library);
        return fail("the Windows proxy query did not match the platform");
      }
    }
  }
  if (blob_create(argv[2], content, -1, blob_oid,
                  (intptr_t)sizeof(blob_oid)) !=
      SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT) {
    CLOSE_LIBRARY(library);
    return fail("negative byte count did not fail closed");
  }
  if (revision_shutdown() != SKILLS_WORKSPACE_REVISION_OK ||
      store_verify(argv[2]) != SKILLS_WORKSPACE_REVISION_OK ||
      revision_shutdown() != SKILLS_WORKSPACE_REVISION_OK ||
      revision_shutdown() != SKILLS_WORKSPACE_REVISION_NOT_INITIALIZED) {
    CLOSE_LIBRARY(library);
    return fail("reference-counted shutdown contract failed");
  }

  {
    source_thread_context context = {transport_blob_read, argv[2], blob_oid, 0};
    int i;
#if defined(_WIN32)
    HANDLE thread = CreateThread(NULL, 0, exercise_source_thread, &context, 0,
                                  NULL);
    if (thread == NULL) {
#else
    pthread_t thread;
    if (pthread_create(&thread, NULL, exercise_source_thread, &context) != 0) {
#endif
      return fail("could not start concurrent Source caller");
    }
    for (i = 0; i < 128; i++) {
      if (revision_init() != SKILLS_WORKSPACE_REVISION_OK ||
          store_verify(argv[2]) != SKILLS_WORKSPACE_REVISION_OK ||
          revision_shutdown() != SKILLS_WORKSPACE_REVISION_OK) {
        return fail("Revision restart failed alongside Source calls");
      }
    }
#if defined(_WIN32)
    if (WaitForSingleObject(thread, 30000) != WAIT_OBJECT_0) {
      return fail("concurrent Source caller timed out");
    }
    CloseHandle(thread);
#else
    if (pthread_join(thread, NULL) != 0) {
      return fail("could not join concurrent Source caller");
    }
#endif
    if (context.failed) {
      return fail("Source calls failed across Revision shutdown/restart");
    }
  }

  // Source-only lifetimes after the final Revision shutdown. Reuse the loaded
  // module here so this contract also runs under macOS ASAN, whose image-global
  // registry does not support dlclose/dlopen cycles of an instrumented dylib.
  {
    int i;
    for (i = 0; i < 16; i++) {
      uint8_t bytes[sizeof(content)];
      intptr_t required;
      if (transport_blob_read(argv[2], blob_oid, sizeof(bytes), bytes,
                              sizeof(bytes), &required) !=
              SKILLS_WORKSPACE_TRANSPORT_OK ||
          required != (intptr_t)(sizeof(content) - 1) ||
          memcmp(bytes, content, sizeof(content) - 1) != 0 ||
          transport_blob_read(argv[2], "invalid", sizeof(bytes), bytes,
                              sizeof(bytes), &required) !=
              SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT) {
        return fail("Source-only calls failed after Revision shutdown");
      }
    }
  }

  if (!CLOSE_LIBRARY(library)) {
    return fail("could not release the package-owned Native Asset");
  }
  if (rename(argv[2], argv[3]) != 0) {
    return fail("Store handles remained open after shutdown");
  }

#if defined(_WIN32)
  // Also exercise actual Windows DLL reloads on the same live thread, where
  // stale FLS callbacks originally caused an access violation after unload.
  {
    int i;
    for (i = 0; i < 16; i++) {
      uint8_t bytes[sizeof(content)];
      intptr_t required;
      library = LOAD_LIBRARY(argv[1]);
      if (library == NULL) {
        return fail("could not reload the Native Asset");
      }
      transport_blob_read = (transport_blob_read_fn)required_symbol(
          library, "skills_workspace_transport_blob_read");
      if (transport_blob_read == NULL ||
          transport_blob_read(argv[3], blob_oid, sizeof(bytes), bytes,
                              sizeof(bytes), &required) !=
              SKILLS_WORKSPACE_TRANSPORT_OK ||
          required != (intptr_t)(sizeof(content) - 1) ||
          memcmp(bytes, content, sizeof(content) - 1) != 0 ||
          transport_blob_read(argv[3], "invalid", sizeof(bytes), bytes,
                              sizeof(bytes), &required) !=
              SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT) {
        return fail("Source-only call failed after DLL reload");
      }
      if (!CLOSE_LIBRARY(library)) {
        return fail("could not unload Source-only runtime");
      }
    }
  }
#endif

  puts("native ABI test passed");
  return 0;
}
