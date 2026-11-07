#ifndef SKILLS_WORKSPACE_RUNTIME_H_
#define SKILLS_WORKSPACE_RUNTIME_H_

#include <stdint.h>

// Private process-wide libgit2 runtime shared by the Revision Engine and the
// Source transport. Not part of the exported ABI.

// Holds libgit2 for one complete Source operation, including argument parsing
// that may set a libgit2 thread-local error. Each successful acquire must be
// balanced after all native objects are freed. The first owner initializes
// libgit2 and applies restrictive global options before admitting any caller;
// the last release shuts it down. Safe across concurrent Source/Revision users.
int skills_workspace_runtime_acquire(void);
void skills_workspace_runtime_release(void);

// Thread-safe Revision Engine reference count. Acquire returns the new count,
// or -1 on initialization failure. Release returns the new count or -1 when no
// reference was held. Each Revision reference also owns one runtime reference;
// callers must retain their init reference until their Revision calls finish.
int32_t skills_workspace_runtime_revision_acquire(void);
int32_t skills_workspace_runtime_revision_release(void);
int32_t skills_workspace_runtime_revision_count(void);

#endif  // SKILLS_WORKSPACE_RUNTIME_H_
