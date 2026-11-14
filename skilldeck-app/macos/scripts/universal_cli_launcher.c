#include <mach-o/dyld.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Dart executables carry a trailing AOT payload that lipo cannot relocate.
// This ordinary Mach-O dispatches to a complete executable for its own CPU.
int main(int argc, char **argv) {
  (void)argc;
  char executable[PATH_MAX], resolved[PATH_MAX];
  uint32_t size = sizeof(executable);
  if (_NSGetExecutablePath(executable, &size) != 0 ||
      realpath(executable, resolved) == NULL) {
    fputs("Cannot locate the SkillDeck CLI bundle.\n", stderr);
    return 70;
  }
  char *separator = strrchr(resolved, '/');
  if (separator == NULL) return 70;
  *separator = '\0';
#if defined(__arm64__)
  const char *architecture = "arm64";
#elif defined(__x86_64__)
  const char *architecture = "x86_64";
#else
#error Unsupported SkillDeck CLI architecture
#endif
  char helper[PATH_MAX];
  int length = snprintf(helper, sizeof(helper),
                        "%s/SkillDeckCLI/skilldeck.%s", resolved, architecture);
  if (length < 0 || length >= (int)sizeof(helper)) return 70;
  argv[0] = helper;
  execv(helper, argv);
  fputs("Cannot start the SkillDeck CLI.\n", stderr);
  return 70;
}
