#include "skills_workspace_runtime.h"

#include <git2.h>

// Private vendored helper, deliberately absent from the public libgit2/shim
// headers and dynamic export allowlist. No diagnostic survives a native call.
void git_error_thread_cleanup(void);

#if defined(_WIN32)
#include <windows.h>
#else
#include <pthread.h>
#endif

// Connect and read/write bounds for every network operation, in milliseconds.
#define SKILLS_WORKSPACE_CONNECT_TIMEOUT_MS 30000
#define SKILLS_WORKSPACE_SERVER_TIMEOUT_MS 60000

// Protect initialization, global options and both owners with the same lock.
// No libgit2 call may outlive its owner's reference.
#if defined(_WIN32)
static SRWLOCK runtime_lock = SRWLOCK_INIT;
#define LOCK_RUNTIME() AcquireSRWLockExclusive(&runtime_lock)
#define UNLOCK_RUNTIME() ReleaseSRWLockExclusive(&runtime_lock)
#else
static pthread_mutex_t runtime_lock = PTHREAD_MUTEX_INITIALIZER;
#define LOCK_RUNTIME() ((void)pthread_mutex_lock(&runtime_lock))
#define UNLOCK_RUNTIME() ((void)pthread_mutex_unlock(&runtime_lock))
#endif
static int32_t runtime_count = 0;
static int32_t revision_count = 0;

static int disable_external_config(void) {
  int result;

  result = git_libgit2_opts(GIT_OPT_SET_SEARCH_PATH, GIT_CONFIG_LEVEL_SYSTEM,
                            "");
  if (result < 0) {
    return result;
  }
  result = git_libgit2_opts(GIT_OPT_SET_SEARCH_PATH, GIT_CONFIG_LEVEL_GLOBAL,
                            "");
  if (result < 0) {
    return result;
  }
  result =
      git_libgit2_opts(GIT_OPT_SET_SEARCH_PATH, GIT_CONFIG_LEVEL_XDG, "");
  if (result < 0) {
    return result;
  }
#if defined(_WIN32)
  result = git_libgit2_opts(GIT_OPT_SET_SEARCH_PATH,
                            GIT_CONFIG_LEVEL_PROGRAMDATA, "");
  if (result < 0) {
    return result;
  }
#endif
  return 0;
}

// Called under runtime_lock, before publishing the first reference. Balance
// even partial initialization: libgit2 increments its count before subsystem
// initialization and keeps the registered cleanup callbacks on failure.
static int runtime_initialize(void) {
  if (git_libgit2_init() < 0) {
    git_libgit2_shutdown();
    return -1;
  }
  if (disable_external_config() < 0 ||
      git_libgit2_opts(GIT_OPT_SET_USER_AGENT, "SkillDeck") < 0 ||
      git_libgit2_opts(GIT_OPT_SET_SERVER_CONNECT_TIMEOUT,
                       SKILLS_WORKSPACE_CONNECT_TIMEOUT_MS) < 0 ||
      git_libgit2_opts(GIT_OPT_SET_SERVER_TIMEOUT,
                       SKILLS_WORKSPACE_SERVER_TIMEOUT_MS) < 0) {
    git_libgit2_shutdown();
    return -1;
  }
  return 0;
}

static int runtime_acquire_locked(void) {
  if (runtime_count == INT32_MAX ||
      (runtime_count == 0 && runtime_initialize() != 0)) {
    return -1;
  }
  runtime_count++;
  return 0;
}

static void runtime_release_locked(void) {
  // pthread_key_delete does not free values on other live threads. Release
  // this caller's error state while the key and allocator are still valid.
  git_error_thread_cleanup();
  if (--runtime_count == 0) {
    // In particular, unregister Windows FLS destructors before DLL unload.
    git_libgit2_shutdown();
  }
}

int skills_workspace_runtime_acquire(void) {
  int result;
  LOCK_RUNTIME();
  result = runtime_acquire_locked();
  UNLOCK_RUNTIME();
  return result;
}

void skills_workspace_runtime_release(void) {
  LOCK_RUNTIME();
  runtime_release_locked();
  UNLOCK_RUNTIME();
}

int32_t skills_workspace_runtime_revision_acquire(void) {
  int32_t result = -1;
  LOCK_RUNTIME();
  if (revision_count < INT32_MAX && runtime_acquire_locked() == 0) {
    result = ++revision_count;
  }
  UNLOCK_RUNTIME();
  return result;
}

int32_t skills_workspace_runtime_revision_release(void) {
  int32_t result = -1;
  LOCK_RUNTIME();
  if (revision_count > 0) {
    result = --revision_count;
    runtime_release_locked();
  }
  UNLOCK_RUNTIME();
  return result;
}

int32_t skills_workspace_runtime_revision_count(void) {
  int32_t result;
  LOCK_RUNTIME();
  result = revision_count;
  UNLOCK_RUNTIME();
  return result;
}
