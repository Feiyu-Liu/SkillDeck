#ifndef SKILLS_WORKSPACE_INTERNAL_REPOSITORY_POLICY_H_
#define SKILLS_WORKSPACE_INTERNAL_REPOSITORY_POLICY_H_

#include <git2.h>
#include <git2/sys/config.h>
#include <git2/sys/repository.h>

// Internal bare Revision/object-transport handles only. APP priority is an
// operation-owned memory backend; neither config files nor global policy change.
static int skills_workspace_configure_internal_repository(git_repository *repository) {
#if defined(_WIN32)
  static const char policy[] = "[core]\nlongpaths = true\n";
  git_config *config = NULL;
  git_config_backend *backend = NULL;
  int result = -1;
  if (git_repository_config(&config, repository) < 0 ||
      git_config_backend_from_string(&backend, policy, sizeof(policy) - 1, NULL) < 0)
    goto cleanup;
  if (git_config_add_backend(config, backend, GIT_CONFIG_LEVEL_APP, repository, 1) < 0)
    goto cleanup;
  backend = NULL; /* The config now owns the memory-only backend. */
  result = git_repository_set_config(repository, config);
cleanup:
  if (backend != NULL) backend->free(backend);
  git_config_free(config);
  return result;
#else
  (void)repository;
  return 0;
#endif
}

#endif  // SKILLS_WORKSPACE_INTERNAL_REPOSITORY_POLICY_H_
