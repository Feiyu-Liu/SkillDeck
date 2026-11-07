#include "skills_workspace_runtime.h"

#include <git2.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

// Fault-inject only the libgit2 boundary; exercise the production owner/lock
// implementation without exposing test hooks in the package DLL.
static int native_count;
static int starts;
static int stops;
static int options;
static int fail_init;
static int fail_option;
static int invalid_options;

void git_error_thread_cleanup(void) {
  if (native_count != 1) invalid_options = 1;
}

int git_libgit2_init(void) {
  native_count++;
  starts++;
  options = 0;
  return fail_init ? -1 : native_count;
}

int git_libgit2_shutdown(void) {
  stops++;
  return --native_count;
}

int git_libgit2_opts(int option, ...) {
  va_list args;
  va_start(args, option);
  options++;
  switch (option) {
    case GIT_OPT_SET_SEARCH_PATH: {
      int level = va_arg(args, int);
      const char *path = va_arg(args, const char *);
      if ((level != GIT_CONFIG_LEVEL_SYSTEM &&
           level != GIT_CONFIG_LEVEL_GLOBAL &&
           level != GIT_CONFIG_LEVEL_XDG &&
           level != GIT_CONFIG_LEVEL_PROGRAMDATA) || strcmp(path, "") != 0) {
        invalid_options = 1;
      }
      break;
    }
    case GIT_OPT_SET_USER_AGENT:
      if (strcmp(va_arg(args, const char *), "SkillDeck") != 0) {
        invalid_options = 1;
      }
      break;
    case GIT_OPT_SET_SERVER_CONNECT_TIMEOUT:
      if (va_arg(args, int) != 30000) invalid_options = 1;
      break;
    case GIT_OPT_SET_SERVER_TIMEOUT:
      if (va_arg(args, int) != 60000) invalid_options = 1;
      break;
    default:
      invalid_options = 1;
      break;
  }
  va_end(args);
  return options == fail_option ? -1 : 0;
}

#define CHECK(condition)                                                     \
  do {                                                                       \
    if (!(condition)) {                                                      \
      fprintf(stderr, "runtime lifecycle failed at line %d\n", __LINE__);   \
      return 1;                                                              \
    }                                                                        \
  } while (0)

int main(void) {
#if defined(_WIN32)
  const int option_count = 7;
#else
  const int option_count = 6;
#endif
  int i;
  CHECK(skills_workspace_runtime_revision_release() == -1);
  CHECK(starts == 0 && stops == 0);

  // Source owns the runtime after both Revision owners release it.
  CHECK(skills_workspace_runtime_acquire() == 0);
  CHECK(options == option_count && !invalid_options);
  CHECK(skills_workspace_runtime_revision_acquire() == 1);
  CHECK(skills_workspace_runtime_revision_acquire() == 2);
  CHECK(starts == 1 && stops == 0 && native_count == 1);
  CHECK(skills_workspace_runtime_revision_release() == 1);
  CHECK(skills_workspace_runtime_revision_release() == 0);
  CHECK(skills_workspace_runtime_revision_count() == 0 && stops == 0);
  skills_workspace_runtime_release();
  CHECK(stops == 1 && native_count == 0);

  // Conversely, releasing Source must preserve a live Revision owner.
  CHECK(skills_workspace_runtime_revision_acquire() == 1);
  CHECK(options == option_count && !invalid_options);
  CHECK(skills_workspace_runtime_acquire() == 0);
  skills_workspace_runtime_release();
  CHECK(stops == 1 && native_count == 1);
  CHECK(skills_workspace_runtime_revision_release() == 0);
  CHECK(stops == 2 && native_count == 0);

  // Every partial initialization must roll back and permit a later retry.
  for (i = 0; i <= option_count; i++) {
    int prior_stops = stops;
    fail_init = i == 0;
    fail_option = i;
    CHECK(skills_workspace_runtime_revision_acquire() == -1);
    CHECK(skills_workspace_runtime_revision_count() == 0);
    CHECK(native_count == 0 && stops == prior_stops + 1);
    fail_init = 0;
    fail_option = 0;
    CHECK(skills_workspace_runtime_acquire() == 0);
    CHECK(options == option_count && !invalid_options);
    skills_workspace_runtime_release();
    CHECK(native_count == 0 && stops == prior_stops + 2);
  }
  CHECK(starts == stops);
  puts("native runtime lifecycle test passed");
  return 0;
}
