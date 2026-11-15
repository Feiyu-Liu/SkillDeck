#include "skills_workspace_native.h"
#include "skills_workspace_runtime.h"
#include "internal_repository_policy.h"

#include "../third_party/libgit2/deps/zlib/zlib.h"

#include <git2.h>
#include <git2/odb_backend.h>
#include <git2/sys/odb_backend.h>
#include <git2/sys/repository.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
#endif

typedef struct skills_workspace_buffer {
  uint8_t *bytes;
  size_t length;
  size_t capacity;
} skills_workspace_buffer;

static int32_t require_initialized(void) {
  return skills_workspace_runtime_revision_count() > 0
             ? SKILLS_WORKSPACE_REVISION_OK
             : SKILLS_WORKSPACE_REVISION_NOT_INITIALIZED;
}

static int32_t open_bare_repository(git_repository **repository,
                                    const char *repository_path) {
  if (repository == NULL || repository_path == NULL ||
      repository_path[0] == '\0') {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  if (git_repository_open_bare(repository, repository_path) < 0 ||
      skills_workspace_configure_internal_repository(*repository) < 0) {
    git_repository_free(*repository);
    *repository = NULL;
    return SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
  }
  if (git_repository_is_bare(*repository) != 1) {
    git_repository_free(*repository);
    *repository = NULL;
    return SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
  }
  return SKILLS_WORKSPACE_REVISION_OK;
}

static int32_t create_bare_repository(git_repository **repository,
                                      const char *repository_path) {
  git_repository_init_options options = GIT_REPOSITORY_INIT_OPTIONS_INIT;

  if (repository == NULL || repository_path == NULL ||
      repository_path[0] == '\0') {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  options.flags = GIT_REPOSITORY_INIT_BARE | GIT_REPOSITORY_INIT_NO_REINIT |
                  GIT_REPOSITORY_INIT_MKPATH;
  options.mode = GIT_REPOSITORY_INIT_SHARED_UMASK;
  options.description = "Skills Workspace internal revision store";
  options.initial_head = "refs/heads/main";
  if (git_repository_init_ext(repository, repository_path, &options) < 0 ||
      skills_workspace_configure_internal_repository(*repository) < 0) {
    git_repository_free(*repository);
    *repository = NULL;
    return SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
  }
  return SKILLS_WORKSPACE_REVISION_OK;
}

static int32_t write_oid(char *output, intptr_t capacity,
                         const git_oid *oid) {
  if (output == NULL || oid == NULL) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  if (capacity < SKILLS_WORKSPACE_REVISION_OID_HEX_SIZE + 1) {
    return SKILLS_WORKSPACE_REVISION_BUFFER_TOO_SMALL;
  }
  if (git_oid_tostr(output, (size_t)capacity, oid) == NULL) {
    return SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
  }
  return SKILLS_WORKSPACE_REVISION_OK;
}

static int parse_oid(git_oid *oid, const char *oid_hex) {
  return oid != NULL && oid_hex != NULL && git_oid_fromstr(oid, oid_hex) == 0;
}

static int buffer_reserve(skills_workspace_buffer *buffer, size_t additional) {
  size_t required;
  size_t next_capacity;
  uint8_t *next;

  if (buffer == NULL || additional > SIZE_MAX - buffer->length) {
    return -1;
  }
  required = buffer->length + additional;
  if (required <= buffer->capacity) {
    return 0;
  }
  next_capacity = buffer->capacity == 0 ? 256 : buffer->capacity;
  while (next_capacity < required) {
    if (next_capacity > SIZE_MAX / 2) {
      next_capacity = required;
      break;
    }
    next_capacity *= 2;
  }
  next = (uint8_t *)realloc(buffer->bytes, next_capacity);
  if (next == NULL) {
    return -1;
  }
  buffer->bytes = next;
  buffer->capacity = next_capacity;
  return 0;
}

static int buffer_append(skills_workspace_buffer *buffer, const void *bytes,
                         size_t length) {
  if (length == 0) {
    return 0;
  }
  if (bytes == NULL || buffer_reserve(buffer, length) < 0) {
    return -1;
  }
  memcpy(buffer->bytes + buffer->length, bytes, length);
  buffer->length += length;
  return 0;
}

static int buffer_append_cstr(skills_workspace_buffer *buffer,
                              const char *value) {
  return buffer_append(buffer, value, value == NULL ? 0 : strlen(value));
}

static int buffer_append_int(skills_workspace_buffer *buffer, int64_t value) {
  char text[32];
  int length = snprintf(text, sizeof(text), "%lld", (long long)value);
  return length < 0 || (size_t)length >= sizeof(text)
             ? -1
             : buffer_append(buffer, text, (size_t)length);
}

static int32_t copy_buffer_output(const skills_workspace_buffer *buffer,
                                  uint8_t *output, intptr_t output_capacity,
                                  intptr_t *required_capacity) {
  if (buffer == NULL || required_capacity == NULL || output_capacity < 0) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  if (buffer->length > (size_t)INTPTR_MAX) {
    return SKILLS_WORKSPACE_REVISION_BUFFER_TOO_SMALL;
  }
  *required_capacity = (intptr_t)buffer->length;
  if ((size_t)output_capacity < buffer->length) {
    return SKILLS_WORKSPACE_REVISION_BUFFER_TOO_SMALL;
  }
  if (buffer->length > 0) {
    if (output == NULL) {
      return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
    }
    memcpy(output, buffer->bytes, buffer->length);
  }
  return SKILLS_WORKSPACE_REVISION_OK;
}

static void buffer_dispose(skills_workspace_buffer *buffer) {
  if (buffer != NULL) {
    free(buffer->bytes);
    buffer->bytes = NULL;
    buffer->length = 0;
    buffer->capacity = 0;
  }
}

static int32_t lookup_commit_tree(git_repository *repository,
                                  const char *commit_oid_hex,
                                  git_commit **commit, git_tree **tree) {
  git_oid commit_oid;

  if (repository == NULL || commit == NULL || tree == NULL ||
      !parse_oid(&commit_oid, commit_oid_hex)) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  if (git_commit_lookup(commit, repository, &commit_oid) < 0 ||
      git_commit_tree(tree, *commit) < 0) {
    git_tree_free(*tree);
    git_commit_free(*commit);
    *tree = NULL;
    *commit = NULL;
    return SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
  }
  return SKILLS_WORKSPACE_REVISION_OK;
}

static int32_t lookup_revision_tree(git_repository *repository,
                                    const char *object_oid_hex,
                                    git_commit **commit, git_tree **tree) {
  git_oid object_oid;

  if (repository == NULL || commit == NULL || tree == NULL ||
      !parse_oid(&object_oid, object_oid_hex)) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  if (git_tree_lookup(tree, repository, &object_oid) == 0) {
    return SKILLS_WORKSPACE_REVISION_OK;
  }
  if (git_commit_lookup(commit, repository, &object_oid) < 0 ||
      git_commit_tree(tree, *commit) < 0) {
    git_tree_free(*tree);
    git_commit_free(*commit);
    *tree = NULL;
    *commit = NULL;
    return SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
  }
  return SKILLS_WORKSPACE_REVISION_OK;
}

static const char *commit_message(int32_t kind) {
  switch (kind) {
    case SKILLS_WORKSPACE_REVISION_COMMIT_INITIAL:
      return "skills-workspace:initial";
    case SKILLS_WORKSPACE_REVISION_COMMIT_UPSTREAM:
      return "skills-workspace:upstream";
    case SKILLS_WORKSPACE_REVISION_COMMIT_EFFECTIVE_UPDATE:
      return "skills-workspace:effective-update";
    case SKILLS_WORKSPACE_REVISION_COMMIT_LOCAL_PUBLISH:
      return "skills-workspace:local-publish";
    case SKILLS_WORKSPACE_REVISION_COMMIT_RESTORE_PUBLISH:
      return "skills-workspace:restore-publish";
    case SKILLS_WORKSPACE_REVISION_COMMIT_UPDATE_CANDIDATE:
      return "skills-workspace:update-candidate";
    default:
      return NULL;
  }
}

static int commit_parent_count_is_valid(int32_t kind, intptr_t parent_count) {
  switch (kind) {
    case SKILLS_WORKSPACE_REVISION_COMMIT_INITIAL:
      return parent_count == 0;
    case SKILLS_WORKSPACE_REVISION_COMMIT_UPSTREAM:
    case SKILLS_WORKSPACE_REVISION_COMMIT_LOCAL_PUBLISH:
    case SKILLS_WORKSPACE_REVISION_COMMIT_RESTORE_PUBLISH:
    case SKILLS_WORKSPACE_REVISION_COMMIT_UPDATE_CANDIDATE:
      return parent_count == 1;
    case SKILLS_WORKSPACE_REVISION_COMMIT_EFFECTIVE_UPDATE:
      return parent_count == 2;
    default:
      return 0;
  }
}

int32_t skills_workspace_revision_init(void) {
  if (skills_workspace_runtime_revision_acquire() < 0) {
    return SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
  }
  return SKILLS_WORKSPACE_REVISION_OK;
}

int32_t skills_workspace_revision_shutdown(void) {
  return skills_workspace_runtime_revision_release() < 0
             ? SKILLS_WORKSPACE_REVISION_NOT_INITIALIZED
             : SKILLS_WORKSPACE_REVISION_OK;
}

int32_t skills_workspace_revision_libgit2_version(int32_t *major,
                                                  int32_t *minor,
                                                  int32_t *revision) {
  int native_major;
  int native_minor;
  int native_revision;
  int32_t initialized = require_initialized();

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  if (major == NULL || minor == NULL || revision == NULL) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  git_libgit2_version(&native_major, &native_minor, &native_revision);
  *major = (int32_t)native_major;
  *minor = (int32_t)native_minor;
  *revision = (int32_t)native_revision;
  return SKILLS_WORKSPACE_REVISION_OK;
}

int32_t skills_workspace_revision_store_create(const char *repository_path) {
  git_repository *repository = NULL;
  int32_t initialized = require_initialized();
  int32_t result;

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  result = create_bare_repository(&repository, repository_path);
  git_repository_free(repository);
  return result;
}

int32_t skills_workspace_revision_store_open_verify(
    const char *repository_path) {
  git_repository *repository = NULL;
  git_odb *odb = NULL;
  int32_t initialized = require_initialized();
  int32_t result;

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  result = open_bare_repository(&repository, repository_path);
  if (result == SKILLS_WORKSPACE_REVISION_OK &&
      git_repository_odb(&odb, repository) < 0) {
    result = SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
  }
  git_odb_free(odb);
  git_repository_free(repository);
  return result;
}

int32_t skills_workspace_revision_blob_create(
    const char *repository_path, const uint8_t *bytes, intptr_t byte_count,
    char *oid_hex, intptr_t oid_hex_capacity) {
  git_repository *repository = NULL;
  git_oid oid;
  int32_t initialized = require_initialized();
  int32_t result;

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  if (byte_count < 0 || (byte_count > 0 && bytes == NULL)) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }
  if (git_blob_create_from_buffer(&oid, repository, bytes,
                                  (size_t)byte_count) < 0) {
    git_repository_free(repository);
    return SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
  }
  result = write_oid(oid_hex, oid_hex_capacity, &oid);
  git_repository_free(repository);
  return result;
}

int32_t skills_workspace_revision_tree_create_single(
    const char *repository_path, const char *entry_name,
    const char *blob_oid_hex, char *oid_hex, intptr_t oid_hex_capacity) {
  git_repository *repository = NULL;
  git_treebuilder *builder = NULL;
  git_oid blob_oid;
  git_oid tree_oid;
  int32_t initialized = require_initialized();
  int32_t result;

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  if (entry_name == NULL || entry_name[0] == '\0' ||
      !parse_oid(&blob_oid, blob_oid_hex)) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }
  if (git_treebuilder_new(&builder, repository, NULL) < 0 ||
      git_treebuilder_insert(NULL, builder, entry_name, &blob_oid,
                             GIT_FILEMODE_BLOB) < 0 ||
      git_treebuilder_write(&tree_oid, builder) < 0) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
  } else {
    result = write_oid(oid_hex, oid_hex_capacity, &tree_oid);
  }
  git_treebuilder_free(builder);
  git_repository_free(repository);
  return result;
}

int32_t skills_workspace_revision_tree_create(
    const char *repository_path, const char *const *relative_paths,
    const uint8_t *const *file_bytes, const intptr_t *byte_counts,
    const int32_t *executable_flags, intptr_t entry_count, char *oid_hex,
    intptr_t oid_hex_capacity) {
  git_repository *repository = NULL;
  git_index *index = NULL;
  git_oid tree_oid;
  intptr_t entry_index;
  int32_t initialized = require_initialized();
  int32_t result;

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  if (entry_count < 0 ||
      (entry_count > 0 &&
       (relative_paths == NULL || file_bytes == NULL || byte_counts == NULL ||
        executable_flags == NULL))) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }
  if (git_index_new(&index) < 0) {
    git_repository_free(repository);
    return SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
  }
  for (entry_index = 0; entry_index < entry_count; entry_index += 1) {
    git_index_entry entry;
    git_oid blob_oid;
    const char *path = relative_paths[entry_index];
    intptr_t byte_count = byte_counts[entry_index];
    const uint8_t *bytes = file_bytes[entry_index];

    if (path == NULL || path[0] == '\0' || byte_count < 0 ||
        (byte_count > 0 && bytes == NULL)) {
      result = SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
      goto cleanup_tree_create;
    }
    if (git_blob_create_from_buffer(&blob_oid, repository, bytes,
                                    (size_t)byte_count) < 0) {
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
      goto cleanup_tree_create;
    }
    memset(&entry, 0, sizeof(entry));
    entry.mode = executable_flags[entry_index] ? GIT_FILEMODE_BLOB_EXECUTABLE
                                               : GIT_FILEMODE_BLOB;
    entry.path = path;
    git_oid_cpy(&entry.id, &blob_oid);
    if (git_index_add(index, &entry) < 0) {
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
      goto cleanup_tree_create;
    }
  }
  if (git_index_write_tree_to(&tree_oid, index, repository) < 0) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
  } else {
    result = write_oid(oid_hex, oid_hex_capacity, &tree_oid);
  }

cleanup_tree_create:
  git_index_free(index);
  git_repository_free(repository);
  return result;
}

typedef struct tree_list_context {
  git_repository *repository;
  skills_workspace_buffer output;
  int failed;
} tree_list_context;

static int tree_list_callback(const char *root, const git_tree_entry *entry,
                              void *payload) {
  tree_list_context *context = (tree_list_context *)payload;
  git_blob *blob = NULL;
  char oid_hex[SKILLS_WORKSPACE_REVISION_OID_HEX_SIZE + 1];
  const char *name;
  git_filemode_t mode;

  if (context == NULL || entry == NULL) {
    return -1;
  }
  if (git_tree_entry_type(entry) == GIT_OBJECT_TREE) {
    return 0;
  }
  if (git_tree_entry_type(entry) != GIT_OBJECT_BLOB ||
      git_blob_lookup(&blob, context->repository, git_tree_entry_id(entry)) <
          0 ||
      git_oid_tostr(oid_hex, sizeof(oid_hex), git_tree_entry_id(entry)) ==
          NULL) {
    git_blob_free(blob);
    context->failed = 1;
    return -1;
  }
  name = git_tree_entry_name(entry);
  mode = git_tree_entry_filemode(entry);
  if (buffer_append_cstr(&context->output, root == NULL ? "" : root) < 0 ||
      buffer_append_cstr(&context->output, name) < 0 ||
      buffer_append(&context->output, "\t", 1) < 0 ||
      buffer_append_int(&context->output, (int64_t)mode) < 0 ||
      buffer_append(&context->output, "\t", 1) < 0 ||
      buffer_append_cstr(&context->output, oid_hex) < 0 ||
      buffer_append(&context->output, "\t", 1) < 0 ||
      buffer_append_int(&context->output, (int64_t)git_blob_rawsize(blob)) <
          0 ||
      buffer_append(&context->output, "\n", 1) < 0) {
    git_blob_free(blob);
    context->failed = 1;
    return -1;
  }
  git_blob_free(blob);
  return 0;
}

int32_t skills_workspace_revision_tree_list(
    const char *repository_path, const char *object_oid_hex, uint8_t *output,
    intptr_t output_capacity, intptr_t *required_capacity) {
  git_repository *repository = NULL;
  git_commit *commit = NULL;
  git_tree *tree = NULL;
  tree_list_context context;
  int32_t initialized = require_initialized();
  int32_t result;

  memset(&context, 0, sizeof(context));
  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }
  result = lookup_revision_tree(repository, object_oid_hex, &commit, &tree);
  if (result == SKILLS_WORKSPACE_REVISION_OK) {
    context.repository = repository;
    if (git_tree_walk(tree, GIT_TREEWALK_PRE, tree_list_callback, &context) <
            0 ||
        context.failed) {
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
    } else {
      result = copy_buffer_output(&context.output, output, output_capacity,
                                  required_capacity);
    }
  }
  buffer_dispose(&context.output);
  git_tree_free(tree);
  git_commit_free(commit);
  git_repository_free(repository);
  return result;
}

int32_t skills_workspace_revision_blob_read(
    const char *repository_path, const char *blob_oid_hex, uint8_t *output,
    intptr_t output_capacity, intptr_t *required_capacity) {
  git_repository *repository = NULL;
  git_blob *blob = NULL;
  git_oid blob_oid;
  skills_workspace_buffer buffer = {0};
  int32_t initialized = require_initialized();
  int32_t result;

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  if (!parse_oid(&blob_oid, blob_oid_hex)) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }
  if (git_blob_lookup(&blob, repository, &blob_oid) < 0 ||
      buffer_append(&buffer, git_blob_rawcontent(blob),
                    (size_t)git_blob_rawsize(blob)) < 0) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
  } else {
    result = copy_buffer_output(&buffer, output, output_capacity,
                                required_capacity);
  }
  buffer_dispose(&buffer);
  git_blob_free(blob);
  git_repository_free(repository);
  return result;
}

int32_t skills_workspace_revision_commit_create(
    const char *repository_path, const char *tree_oid_hex,
    const char *const *parent_oid_hex, intptr_t parent_count,
    int32_t commit_kind, char *oid_hex, intptr_t oid_hex_capacity) {
  git_repository *repository = NULL;
  git_tree *tree = NULL;
  git_signature *signature = NULL;
  git_commit **parents = NULL;
  git_oid tree_oid;
  git_oid commit_oid;
  intptr_t parent_index;
  const char *message;
  int32_t initialized = require_initialized();
  int32_t result;

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  message = commit_message(commit_kind);
  if (!parse_oid(&tree_oid, tree_oid_hex) || message == NULL ||
      !commit_parent_count_is_valid(commit_kind, parent_count) ||
      (parent_count > 0 && parent_oid_hex == NULL)) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }
  if (git_tree_lookup(&tree, repository, &tree_oid) < 0 ||
      git_signature_new(&signature, "Skills Workspace",
                        "revision@skills.workspace", 0, 0) < 0) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
    goto cleanup_commit_create;
  }
  if (parent_count > 0) {
    parents = (git_commit **)calloc((size_t)parent_count, sizeof(git_commit *));
    if (parents == NULL) {
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
      goto cleanup_commit_create;
    }
  }
  for (parent_index = 0; parent_index < parent_count; parent_index += 1) {
    git_oid parent_oid;
    if (!parse_oid(&parent_oid, parent_oid_hex[parent_index]) ||
        git_commit_lookup(&parents[parent_index], repository, &parent_oid) < 0) {
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
      goto cleanup_commit_create;
    }
  }
  if (git_commit_create(&commit_oid, repository, NULL, signature, signature,
                        "UTF-8", message, tree, (size_t)parent_count,
                        (const git_commit **)parents) < 0) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
  } else {
    result = write_oid(oid_hex, oid_hex_capacity, &commit_oid);
  }

cleanup_commit_create:
  if (parents != NULL) {
    for (parent_index = 0; parent_index < parent_count; parent_index += 1) {
      git_commit_free(parents[parent_index]);
    }
  }
  free(parents);
  git_signature_free(signature);
  git_tree_free(tree);
  git_repository_free(repository);
  return result;
}

int32_t skills_workspace_revision_commit_create_root(
    const char *repository_path, const char *tree_oid_hex, char *oid_hex,
    intptr_t oid_hex_capacity) {
  return skills_workspace_revision_commit_create(
      repository_path, tree_oid_hex, NULL, 0,
      SKILLS_WORKSPACE_REVISION_COMMIT_INITIAL, oid_hex, oid_hex_capacity);
}

int32_t skills_workspace_revision_commit_verify(
    const char *repository_path, const char *commit_oid_hex,
    const char *expected_tree_oid_hex,
    const char *const *expected_parent_oid_hex,
    intptr_t expected_parent_count, int32_t expected_commit_kind) {
  git_repository *repository = NULL;
  git_commit *commit = NULL;
  git_oid commit_oid;
  git_oid expected_tree_oid;
  intptr_t parent_index;
  const char *expected_message;
  int32_t initialized = require_initialized();
  int32_t result;

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  expected_message = commit_message(expected_commit_kind);
  if (!parse_oid(&commit_oid, commit_oid_hex) ||
      !parse_oid(&expected_tree_oid, expected_tree_oid_hex) ||
      expected_message == NULL ||
      !commit_parent_count_is_valid(expected_commit_kind,
                                    expected_parent_count) ||
      expected_parent_count < 0 || expected_parent_count > 2 ||
      (expected_parent_count > 0 && expected_parent_oid_hex == NULL)) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }
  if (git_commit_lookup(&commit, repository, &commit_oid) < 0 ||
      !git_oid_equal(git_commit_tree_id(commit), &expected_tree_oid) ||
      git_commit_parentcount(commit) != (size_t)expected_parent_count ||
      git_commit_message(commit) == NULL ||
      strcmp(git_commit_message(commit), expected_message) != 0) {
    result = SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
    goto cleanup_commit_verify;
  }
  for (parent_index = 0; parent_index < expected_parent_count;
       parent_index += 1) {
    git_oid expected_parent_oid;
    if (!parse_oid(&expected_parent_oid,
                   expected_parent_oid_hex[parent_index]) ||
        !git_oid_equal(git_commit_parent_id(commit, (unsigned int)parent_index),
                       &expected_parent_oid)) {
      result = SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
      goto cleanup_commit_verify;
    }
  }
  result = SKILLS_WORKSPACE_REVISION_OK;

cleanup_commit_verify:
  git_commit_free(commit);
  git_repository_free(repository);
  return result;
}


static int32_t read_verified_object(git_odb_object **out, git_odb *odb,
                                    const git_oid *oid, git_object_t expected,
                                    uint64_t maximum_bytes) {
  size_t size;
  git_object_t type;
  git_oid computed;
  if (git_odb_read_header(&size, &type, odb, oid) < 0)
    return SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
  if (type != expected) return SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
  if ((uint64_t)size > maximum_bytes)
    return SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED;
  if (git_odb_read(out, odb, oid) < 0 ||
      git_odb_object_type(*out) != expected ||
      git_odb_object_size(*out) != size ||
      git_odb_hash(&computed, git_odb_object_data(*out), size, expected) < 0 ||
      !git_oid_equal(&computed, oid)) {
    git_odb_object_free(*out);
    *out = NULL;
    return SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
  }
  return SKILLS_WORKSPACE_REVISION_OK;
}

int32_t skills_workspace_revision_commit_inspect(
    const char *repository_path, const char *commit_oid_hex,
    int64_t maximum_commit_bytes, int64_t maximum_parent_count,
    uint8_t *output, intptr_t output_capacity, intptr_t *required_capacity) {
  git_repository *repository = NULL;
  git_odb *odb = NULL;
  git_odb_object *object = NULL;
  git_commit *commit = NULL;
  skills_workspace_buffer buffer = {0};
  git_oid oid;
  char hex[GIT_OID_SHA1_HEXSIZE + 1];
  unsigned int i, parent_count;
  int32_t result = require_initialized();
  if (result != SKILLS_WORKSPACE_REVISION_OK) return result;
  if (!parse_oid(&oid, commit_oid_hex) || required_capacity == NULL ||
      output_capacity < 0 || maximum_commit_bytes < 1 ||
      maximum_parent_count < 0) return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) return result;
  if (git_repository_odb(&odb, repository) < 0) {
    result = SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
    goto cleanup_inspect;
  }
  result = read_verified_object(&object, odb, &oid, GIT_OBJECT_COMMIT,
                                (uint64_t)maximum_commit_bytes);
  if (result != SKILLS_WORKSPACE_REVISION_OK) goto cleanup_inspect;
  if (git_commit_lookup(&commit, repository, &oid) < 0) {
    result = SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
    goto cleanup_inspect;
  }
  parent_count = git_commit_parentcount(commit);
  if ((uint64_t)parent_count > (uint64_t)maximum_parent_count) {
    result = SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED;
    goto cleanup_inspect;
  }
  {
    size_t size;
    git_object_t type;
    if (git_odb_read_header(&size, &type, odb, git_commit_tree_id(commit)) < 0 ||
        type != GIT_OBJECT_TREE) {
      result = SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
      goto cleanup_inspect;
    }
  }
  git_oid_tostr(hex, sizeof(hex), git_commit_tree_id(commit));
  if (buffer_append_cstr(&buffer, hex) < 0 ||
      buffer_append_cstr(&buffer, "\n") < 0) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
    goto cleanup_inspect;
  }
  for (i = 0; i < parent_count; ++i) {
    size_t size;
    git_object_t type;
    if (git_odb_read_header(&size, &type, odb, git_commit_parent_id(commit, i)) < 0 ||
        type != GIT_OBJECT_COMMIT) {
      result = SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
      goto cleanup_inspect;
    }
    if (size > (uint64_t)maximum_commit_bytes) {
      result = SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED;
      goto cleanup_inspect;
    }
    git_oid_tostr(hex, sizeof(hex), git_commit_parent_id(commit, i));
    if (buffer_append_cstr(&buffer, hex) < 0 ||
        buffer_append_cstr(&buffer, "\n") < 0) {
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
      goto cleanup_inspect;
    }
  }
  result = copy_buffer_output(&buffer, output, output_capacity, required_capacity);
cleanup_inspect:
  buffer_dispose(&buffer);
  git_commit_free(commit);
  git_odb_object_free(object);
  git_odb_free(odb);
  git_repository_free(repository);
  return result;
}

typedef struct revision_import_node {
  git_oid oid;
  git_object_t type;
  uint64_t size;
} revision_import_node;

typedef struct revision_import_graph {
  revision_import_node *nodes;
  uint32_t *slots;
  size_t slot_count;
  size_t count;
  size_t maximum_count;
} revision_import_graph;

static uint32_t revision_oid_hash(const git_oid *oid) {
  uint32_t hash = 2166136261U;
  size_t i;
  for (i = 0; i < GIT_OID_SHA1_SIZE; ++i)
    hash = (hash ^ oid->id[i]) * 16777619U;
  return hash;
}

static int32_t revision_graph_add(revision_import_graph *graph, git_odb *odb,
                                  const git_oid *oid, git_object_t type) {
  size_t object_size;
  git_object_t actual_type;
  size_t slot;
  if (git_odb_read_header(&object_size, &actual_type, odb, oid) < 0)
    return SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
  if (actual_type != type) return SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
  slot = revision_oid_hash(oid) & (graph->slot_count - 1);
  while (graph->slots[slot] != 0) {
    revision_import_node *node = &graph->nodes[graph->slots[slot] - 1];
    if (git_oid_equal(&node->oid, oid))
      return node->type == type ? SKILLS_WORKSPACE_REVISION_OK
                               : SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
    slot = (slot + 1) & (graph->slot_count - 1);
  }
  if (graph->count >= graph->maximum_count)
    return SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED;
  git_oid_cpy(&graph->nodes[graph->count].oid, oid);
  graph->nodes[graph->count].type = type;
  graph->slots[slot] = (uint32_t)++graph->count;
  return SKILLS_WORKSPACE_REVISION_OK;
}

static int revision_import_cancelled(const int32_t *flag) {
  return flag != NULL && *(const volatile int32_t *)flag != 0;
}

static int32_t validate_revision_graph(
    revision_import_graph *graph, git_repository *source, git_odb *source_odb,
    const char *const *retained_root_oid_hex, intptr_t retained_root_count,
    int64_t maximum_object_count, int64_t maximum_object_bytes,
    int64_t maximum_total_bytes, int64_t maximum_commit_bytes,
    int64_t maximum_parent_count, const int32_t *cancel_flag, uint64_t *verified_total) {
  intptr_t root;
  size_t i;
  uint64_t total = 0;
  int32_t result;
  if (maximum_object_count < 1 || (uint64_t)maximum_object_count >= UINT32_MAX ||
      (uint64_t)maximum_object_count > SIZE_MAX / sizeof(revision_import_node))
    return SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED;
  graph->maximum_count = (size_t)maximum_object_count;
  graph->slot_count = 1;
  while (graph->slot_count < graph->maximum_count * 2) graph->slot_count *= 2;
  graph->nodes = calloc(graph->maximum_count, sizeof(revision_import_node));
  graph->slots = calloc(graph->slot_count, sizeof(uint32_t));
  if (graph->nodes == NULL || graph->slots == NULL) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
    return result;
  }
  for (root = 0; root < retained_root_count; ++root) {
    git_oid oid;
    if (!parse_oid(&oid, retained_root_oid_hex[root])) {
      result = SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
      return result;
    }
    result = revision_graph_add(graph, source_odb, &oid, GIT_OBJECT_COMMIT);
    if (result != SKILLS_WORKSPACE_REVISION_OK) return result;
  }
  // Iterative bounded traversal: source completeness is required independently
  // of objects already present in the canonical target. No recursion/refs.
  for (i = 0; i < graph->count; ++i) {
    revision_import_node *node = &graph->nodes[i];
    git_odb_object *object = NULL;
    git_commit *commit = NULL;
    git_tree *tree = NULL;
    size_t j;
    if (revision_import_cancelled(cancel_flag)) {
      result = SKILLS_WORKSPACE_REVISION_CANCELLED;
      return result;
    }
    result = read_verified_object(&object, source_odb, &node->oid, node->type,
        node->type == GIT_OBJECT_COMMIT && maximum_object_bytes > (uint64_t)maximum_commit_bytes
            ? (uint64_t)maximum_commit_bytes : (uint64_t)maximum_object_bytes);
    if (result != SKILLS_WORKSPACE_REVISION_OK) return result;
    node->size = git_odb_object_size(object);
    git_odb_object_free(object);
    if (node->size > (uint64_t)maximum_total_bytes - total) {
      result = SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED;
      return result;
    }
    total += node->size;
    if (node->type == GIT_OBJECT_COMMIT) {
      if (node->size > (uint64_t)maximum_commit_bytes ||
          git_commit_lookup(&commit, source, &node->oid) < 0) {
        result = node->size > (uint64_t)maximum_commit_bytes
            ? SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED
            : SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
        return result;
      }
      if ((uint64_t)git_commit_parentcount(commit) > (uint64_t)maximum_parent_count) {
        git_commit_free(commit);
        result = SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED;
        return result;
      }
      result = revision_graph_add(graph, source_odb, git_commit_tree_id(commit), GIT_OBJECT_TREE);
      for (j = 0; result == SKILLS_WORKSPACE_REVISION_OK &&
                  j < git_commit_parentcount(commit); ++j)
        result = revision_graph_add(graph, source_odb, git_commit_parent_id(commit, (unsigned int)j),
                                     GIT_OBJECT_COMMIT);
      git_commit_free(commit);
    } else if (node->type == GIT_OBJECT_TREE) {
      if (git_tree_lookup(&tree, source, &node->oid) < 0) {
        result = SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
        return result;
      }
      for (j = 0; j < git_tree_entrycount(tree); ++j) {
        const git_tree_entry *entry = git_tree_entry_byindex(tree, j);
        git_filemode_t mode = git_tree_entry_filemode(entry);
        git_object_t expected;
        if (revision_import_cancelled(cancel_flag)) {
          result = SKILLS_WORKSPACE_REVISION_CANCELLED;
          break;
        }
        if (mode == GIT_FILEMODE_TREE) expected = GIT_OBJECT_TREE;
        else if (mode == GIT_FILEMODE_BLOB || mode == GIT_FILEMODE_BLOB_EXECUTABLE ||
                 mode == GIT_FILEMODE_LINK) expected = GIT_OBJECT_BLOB;
        else {
          result = SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
          break;
        }
        result = revision_graph_add(graph, source_odb, git_tree_entry_id(entry), expected);
        if (result != SKILLS_WORKSPACE_REVISION_OK) break;
      }
      git_tree_free(tree);
    }
    if (result != SKILLS_WORKSPACE_REVISION_OK) return result;
  }
  *verified_total = total;
  return SKILLS_WORKSPACE_REVISION_OK;
}

// A staging closure must be self-contained, not borrowed from alternates.
// Construct only its own loose/pack backends and use the same ODB for parsing.
static int isolated_staging_odb(git_odb **out, git_repository *repository) {
  git_buf objects = GIT_BUF_INIT;
  git_odb_backend *loose = NULL, *packed = NULL;
  git_odb *odb = NULL;
  int result = -1;
  if (git_repository_item_path(&objects, repository, GIT_REPOSITORY_ITEM_OBJECTS) < 0 ||
      git_odb_new(&odb) < 0 ||
      git_odb_backend_loose(&loose, objects.ptr, -1, 0, 0, 0) < 0)
    goto cleanup_isolated;
  if (git_odb_add_backend(odb, loose, 1) < 0) goto cleanup_isolated;
  loose = NULL;
  if (git_odb_backend_pack(&packed, objects.ptr) < 0 ||
      git_odb_add_backend(odb, packed, 2) < 0) goto cleanup_isolated;
  packed = NULL;
  if (git_repository_set_odb(repository, odb) < 0) goto cleanup_isolated;
  *out = odb;
  odb = NULL;
  result = 0;
cleanup_isolated:
  if (loose != NULL) loose->free(loose);
  if (packed != NULL) packed->free(packed);
  git_odb_free(odb);
  git_buf_dispose(&objects);
  return result;
}

int32_t skills_workspace_revision_objects_import(
    const char *repository_path, const char *staged_repository_path,
    const char *const *retained_root_oid_hex, intptr_t retained_root_count,
    int64_t maximum_object_count, int64_t maximum_object_bytes,
    int64_t maximum_total_bytes, int64_t maximum_commit_bytes,
    int64_t maximum_parent_count, const int32_t *cancel_flag,
    int64_t *verified_object_count, int64_t *verified_total_bytes) {
  git_repository *source = NULL, *target = NULL;
  git_odb *source_odb = NULL, *target_odb = NULL;
  revision_import_graph graph = {0};
  size_t i;
  uint64_t total = 0;
  int32_t result = require_initialized();
  if (verified_object_count != NULL) *verified_object_count = 0;
  if (verified_total_bytes != NULL) *verified_total_bytes = 0;
  if (result != SKILLS_WORKSPACE_REVISION_OK) return result;
  if (retained_root_count < 1 ||
      retained_root_oid_hex == NULL || verified_object_count == NULL ||
      verified_total_bytes == NULL || maximum_object_count < 1 ||
      maximum_object_bytes < 1 || maximum_total_bytes < 1 ||
      maximum_commit_bytes < 1 || maximum_parent_count < 0)
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  if (retained_root_count > 1000000 || maximum_object_count > 1000000 ||
      maximum_object_bytes > 256LL * 1024 * 1024 ||
      maximum_total_bytes > 8LL * 1024 * 1024 * 1024)
    return SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED;
  if (revision_import_cancelled(cancel_flag))
    return SKILLS_WORKSPACE_REVISION_CANCELLED;
  result = open_bare_repository(&source, staged_repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) goto cleanup_import;
  result = open_bare_repository(&target, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) goto cleanup_import;
  if (isolated_staging_odb(&source_odb, source) < 0 ||
      git_repository_odb(&target_odb, target) < 0) {
    result = SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
    goto cleanup_import;
  }
  result = validate_revision_graph(&graph, source, source_odb,
      retained_root_oid_hex, retained_root_count, maximum_object_count,
      maximum_object_bytes, maximum_total_bytes, maximum_commit_bytes,
      maximum_parent_count, cancel_flag, &total);
  if (result != SKILLS_WORKSPACE_REVISION_OK) goto cleanup_import;
  // Re-read/hash each bounded source object while copying, to fail closed if
  // the caller violated staging immutability. Partial immutable ODB residue is
  // harmless to selection; publishing/pinning belongs to the transaction.
  for (i = 0; i < graph.count; ++i) {
    revision_import_node *node = &graph.nodes[i];
    git_odb_object *object = NULL, *verified = NULL;
    git_oid written;
    if (revision_import_cancelled(cancel_flag)) {
      result = SKILLS_WORKSPACE_REVISION_CANCELLED;
      goto cleanup_import;
    }
    result = read_verified_object(&object, source_odb, &node->oid, node->type, node->size);
    if (result != SKILLS_WORKSPACE_REVISION_OK) goto cleanup_import;
    if (git_odb_write(&written, target_odb, git_odb_object_data(object),
                       git_odb_object_size(object), node->type) < 0 ||
        !git_oid_equal(&written, &node->oid)) {
      git_odb_object_free(object);
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
      goto cleanup_import;
    }
    git_odb_object_free(object);
    result = read_verified_object(&verified, target_odb, &node->oid, node->type, node->size);
    git_odb_object_free(verified);
    if (result != SKILLS_WORKSPACE_REVISION_OK) goto cleanup_import;
  }
  if (revision_import_cancelled(cancel_flag)) {
    result = SKILLS_WORKSPACE_REVISION_CANCELLED;
    goto cleanup_import;
  }
  *verified_object_count = (int64_t)graph.count;
  *verified_total_bytes = (int64_t)total;
  result = SKILLS_WORKSPACE_REVISION_OK;
cleanup_import:
  git_odb_free(target_odb);
  git_odb_free(source_odb);
  git_repository_free(target);
  git_repository_free(source);
  free(graph.slots);
  free(graph.nodes);
  return result;
}

int32_t skills_workspace_revision_commit_is_ancestor(
    const char *repository_path, const char *ancestor_oid_hex,
    const char *descendant_oid_hex, int32_t *is_ancestor) {
  git_repository *repository = NULL;
  git_oid ancestor_oid;
  git_oid descendant_oid;
  int descendant_result;
  int32_t initialized = require_initialized();
  int32_t result;

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  if (is_ancestor == NULL || !parse_oid(&ancestor_oid, ancestor_oid_hex) ||
      !parse_oid(&descendant_oid, descendant_oid_hex)) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }
  descendant_result =
      git_graph_descendant_of(repository, &descendant_oid, &ancestor_oid);
  if (descendant_result < 0) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
  } else {
    *is_ancestor = descendant_result == 1 ? 1 : 0;
    result = SKILLS_WORKSPACE_REVISION_OK;
  }
  git_repository_free(repository);
  return result;
}

int32_t skills_workspace_revision_commit_verify_root(
    const char *repository_path, const char *commit_oid_hex,
    const char *entry_name, const uint8_t *expected_bytes,
    intptr_t expected_byte_count) {
  git_repository *repository = NULL;
  git_commit *commit = NULL;
  git_tree *tree = NULL;
  git_blob *blob = NULL;
  const git_tree_entry *entry = NULL;
  git_oid commit_oid;
  const void *blob_bytes;
  int32_t initialized = require_initialized();
  int32_t result;

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  if (!parse_oid(&commit_oid, commit_oid_hex) || entry_name == NULL ||
      entry_name[0] == '\0' || expected_byte_count < 0 ||
      (expected_byte_count > 0 && expected_bytes == NULL)) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }
  if (git_commit_lookup(&commit, repository, &commit_oid) < 0 ||
      git_commit_parentcount(commit) != 0 || git_commit_tree(&tree, commit) < 0 ||
      (entry = git_tree_entry_byname(tree, entry_name)) == NULL ||
      git_tree_entry_type(entry) != GIT_OBJECT_BLOB ||
      git_blob_lookup(&blob, repository, git_tree_entry_id(entry)) < 0 ||
      git_blob_rawsize(blob) != (git_off_t)expected_byte_count) {
    result = SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
    goto cleanup_root_verify;
  }
  blob_bytes = git_blob_rawcontent(blob);
  result = expected_byte_count > 0 &&
                   memcmp(blob_bytes, expected_bytes,
                          (size_t)expected_byte_count) != 0
               ? SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE
               : SKILLS_WORKSPACE_REVISION_OK;

cleanup_root_verify:
  git_blob_free(blob);
  git_tree_free(tree);
  git_commit_free(commit);
  git_repository_free(repository);
  return result;
}

static char diff_status_code(git_delta_t status) {
  switch (status) {
    case GIT_DELTA_ADDED:
      return 'A';
    case GIT_DELTA_DELETED:
      return 'D';
    case GIT_DELTA_RENAMED:
      return 'R';
    case GIT_DELTA_TYPECHANGE:
      return 'T';
    default:
      return 'M';
  }
}

static int oid_is_binary_blob(git_repository *repository, const git_oid *oid) {
  git_blob *blob = NULL;
  int result = 0;
  if (repository == NULL || oid == NULL || git_oid_is_zero(oid)) {
    return 0;
  }
  if (git_blob_lookup(&blob, repository, oid) == 0) {
    result = git_blob_is_binary(blob) == 1;
  }
  git_blob_free(blob);
  return result;
}

int32_t skills_workspace_revision_diff(
    const char *repository_path, const char *old_commit_oid_hex,
    const char *new_commit_oid_hex, uint8_t *output,
    intptr_t output_capacity, intptr_t *required_capacity) {
  git_repository *repository = NULL;
  git_commit *old_commit = NULL;
  git_commit *new_commit = NULL;
  git_tree *old_tree = NULL;
  git_tree *new_tree = NULL;
  git_diff *diff = NULL;
  git_diff_options diff_options = GIT_DIFF_OPTIONS_INIT;
  git_diff_find_options find_options = GIT_DIFF_FIND_OPTIONS_INIT;
  skills_workspace_buffer buffer = {0};
  size_t delta_index;
  int32_t initialized = require_initialized();
  int32_t result;

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }
  result = lookup_commit_tree(repository, old_commit_oid_hex, &old_commit,
                              &old_tree);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    goto cleanup_diff;
  }
  result = lookup_commit_tree(repository, new_commit_oid_hex, &new_commit,
                              &new_tree);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    goto cleanup_diff;
  }
  diff_options.flags = GIT_DIFF_INCLUDE_TYPECHANGE;
  if (git_diff_tree_to_tree(&diff, repository, old_tree, new_tree,
                            &diff_options) < 0) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
    goto cleanup_diff;
  }
  find_options.flags = GIT_DIFF_FIND_RENAMES;
  if (git_diff_find_similar(diff, &find_options) < 0) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
    goto cleanup_diff;
  }
  for (delta_index = 0; delta_index < git_diff_num_deltas(diff);
       delta_index += 1) {
    const git_diff_delta *delta = git_diff_get_delta(diff, delta_index);
    char status;
    int binary;
    if (delta == NULL) {
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
      goto cleanup_diff;
    }
    status = diff_status_code(delta->status);
    binary = oid_is_binary_blob(repository, &delta->old_file.id) ||
             oid_is_binary_blob(repository, &delta->new_file.id);
    if (buffer_append(&buffer, &status, 1) < 0 ||
        buffer_append(&buffer, "\t", 1) < 0 ||
        buffer_append_cstr(&buffer, delta->old_file.path) < 0 ||
        buffer_append(&buffer, "\t", 1) < 0 ||
        buffer_append_cstr(&buffer, delta->new_file.path) < 0 ||
        buffer_append(&buffer, "\t", 1) < 0 ||
        buffer_append_int(&buffer, (int64_t)delta->old_file.mode) < 0 ||
        buffer_append(&buffer, "\t", 1) < 0 ||
        buffer_append_int(&buffer, (int64_t)delta->new_file.mode) < 0 ||
        buffer_append(&buffer, binary ? "\t1\n" : "\t0\n", 3) < 0) {
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
      goto cleanup_diff;
    }
  }
  result = copy_buffer_output(&buffer, output, output_capacity,
                              required_capacity);

cleanup_diff:
  buffer_dispose(&buffer);
  git_diff_free(diff);
  git_tree_free(new_tree);
  git_commit_free(new_commit);
  git_tree_free(old_tree);
  git_commit_free(old_commit);
  git_repository_free(repository);
  return result;
}

static int append_conflict_path(skills_workspace_buffer *buffer,
                                const git_index_entry *entry) {
  if (entry != NULL && entry->path != NULL &&
      buffer_append_cstr(buffer, entry->path) < 0) {
    return -1;
  }
  return buffer_append(buffer, "\0", 1);
}

typedef struct resolved_conflict_entry {
  git_oid id;
  uint32_t mode;
  char *path;
} resolved_conflict_entry;

static int append_resolved_conflict_entry(
    resolved_conflict_entry **entries, size_t *entry_count,
    size_t *entry_capacity, const git_index_entry *selected) {
  resolved_conflict_entry *next;
  size_t next_capacity;
  size_t path_length;

  if (entries == NULL || entry_count == NULL || entry_capacity == NULL ||
      selected == NULL || selected->path == NULL) {
    return -1;
  }
  if (*entry_count == *entry_capacity) {
    next_capacity = *entry_capacity == 0 ? 4 : *entry_capacity * 2;
    if (next_capacity < *entry_capacity ||
        next_capacity > SIZE_MAX / sizeof(resolved_conflict_entry)) {
      return -1;
    }
    next = (resolved_conflict_entry *)realloc(
        *entries, next_capacity * sizeof(resolved_conflict_entry));
    if (next == NULL) {
      return -1;
    }
    *entries = next;
    *entry_capacity = next_capacity;
  }
  path_length = strlen(selected->path);
  (*entries)[*entry_count].path = (char *)malloc(path_length + 1);
  if ((*entries)[*entry_count].path == NULL) {
    return -1;
  }
  memcpy((*entries)[*entry_count].path, selected->path, path_length + 1);
  git_oid_cpy(&(*entries)[*entry_count].id, &selected->id);
  (*entries)[*entry_count].mode = selected->mode;
  *entry_count += 1;
  return 0;
}

int32_t skills_workspace_revision_merge(
    const char *repository_path, const char *previous_upstream_oid_hex,
    const char *current_effective_oid_hex,
    const char *incoming_upstream_oid_hex, char *tree_oid_hex,
    intptr_t tree_oid_hex_capacity, uint8_t *conflict_output,
    intptr_t conflict_output_capacity, intptr_t *required_conflict_capacity,
    intptr_t *conflict_count) {
  git_repository *repository = NULL;
  git_commit *ancestor_commit = NULL;
  git_commit *current_commit = NULL;
  git_commit *incoming_commit = NULL;
  git_tree *ancestor_tree = NULL;
  git_tree *current_tree = NULL;
  git_tree *incoming_tree = NULL;
  git_index *merged_index = NULL;
  git_index_conflict_iterator *iterator = NULL;
  const git_index_entry *ancestor_entry;
  const git_index_entry *current_entry;
  const git_index_entry *incoming_entry;
  git_merge_options merge_options = GIT_MERGE_OPTIONS_INIT;
  skills_workspace_buffer conflicts = {0};
  resolved_conflict_entry *resolved_entries = NULL;
  size_t resolved_entry_count = 0;
  size_t resolved_entry_capacity = 0;
  size_t resolved_index;
  git_oid merged_tree_oid;
  intptr_t count = 0;
  int iterator_result;
  int32_t initialized = require_initialized();
  int32_t result;

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  if (tree_oid_hex == NULL ||
      tree_oid_hex_capacity < SKILLS_WORKSPACE_REVISION_OID_HEX_SIZE + 1 ||
      required_conflict_capacity == NULL || conflict_count == NULL) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  tree_oid_hex[0] = '\0';
  *required_conflict_capacity = 0;
  *conflict_count = 0;
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }
  result = lookup_commit_tree(repository, previous_upstream_oid_hex,
                              &ancestor_commit, &ancestor_tree);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    goto cleanup_merge;
  }
  result = lookup_commit_tree(repository, current_effective_oid_hex,
                              &current_commit, &current_tree);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    goto cleanup_merge;
  }
  result = lookup_commit_tree(repository, incoming_upstream_oid_hex,
                              &incoming_commit, &incoming_tree);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    goto cleanup_merge;
  }
  if ((!git_oid_equal(git_commit_id(current_commit),
                      git_commit_id(ancestor_commit)) &&
       git_graph_descendant_of(repository, git_commit_id(current_commit),
                               git_commit_id(ancestor_commit)) != 1) ||
      git_commit_parentcount(incoming_commit) != 1 ||
      !git_oid_equal(git_commit_parent_id(incoming_commit, 0),
                     git_commit_id(ancestor_commit)) ||
      git_commit_message(incoming_commit) == NULL ||
      strcmp(git_commit_message(incoming_commit),
             commit_message(SKILLS_WORKSPACE_REVISION_COMMIT_UPSTREAM)) != 0) {
    result = SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
    goto cleanup_merge;
  }
  merge_options.flags = GIT_MERGE_FIND_RENAMES;
  if (git_merge_trees(&merged_index, repository, ancestor_tree, current_tree,
                      incoming_tree, &merge_options) < 0) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
    goto cleanup_merge;
  }
  if (!git_index_has_conflicts(merged_index)) {
    if (git_index_write_tree_to(&merged_tree_oid, merged_index, repository) <
        0) {
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
    } else {
      result = write_oid(tree_oid_hex, tree_oid_hex_capacity, &merged_tree_oid);
    }
    goto cleanup_merge;
  }
  if (git_index_conflict_iterator_new(&iterator, merged_index) < 0) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
    goto cleanup_merge;
  }
  while ((iterator_result = git_index_conflict_next(
              &ancestor_entry, &current_entry, &incoming_entry, iterator)) ==
         0) {
    const git_index_entry *selected_entry =
        current_entry != NULL ? current_entry
                              : (incoming_entry != NULL ? incoming_entry
                                                        : ancestor_entry);
    if (append_conflict_path(&conflicts, ancestor_entry) < 0 ||
        append_conflict_path(&conflicts, current_entry) < 0 ||
        append_conflict_path(&conflicts, incoming_entry) < 0) {
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
      goto cleanup_merge;
    }
    if (selected_entry == NULL) {
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
      goto cleanup_merge;
    }
    if (append_resolved_conflict_entry(
            &resolved_entries, &resolved_entry_count,
            &resolved_entry_capacity, selected_entry) < 0) {
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
      goto cleanup_merge;
    }
    count += 1;
  }
  if (iterator_result != GIT_ITEROVER) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
    goto cleanup_merge;
  }
  git_index_conflict_iterator_free(iterator);
  iterator = NULL;
  for (resolved_index = 0; resolved_index < resolved_entry_count;
       resolved_index += 1) {
    git_index_entry resolved_entry;
    memset(&resolved_entry, 0, sizeof(resolved_entry));
    git_oid_cpy(&resolved_entry.id, &resolved_entries[resolved_index].id);
    resolved_entry.mode = resolved_entries[resolved_index].mode;
    resolved_entry.path = resolved_entries[resolved_index].path;
    GIT_INDEX_ENTRY_STAGE_SET(&resolved_entry, 0);
    if (git_index_add(merged_index, &resolved_entry) < 0) {
      result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
      goto cleanup_merge;
    }
  }
  if (git_index_conflict_cleanup(merged_index) < 0 ||
      git_index_write_tree_to(&merged_tree_oid, merged_index, repository) < 0) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
    goto cleanup_merge;
  }
  result = write_oid(tree_oid_hex, tree_oid_hex_capacity, &merged_tree_oid);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    goto cleanup_merge;
  }
  *conflict_count = count;
  result = copy_buffer_output(&conflicts, conflict_output,
                              conflict_output_capacity,
                              required_conflict_capacity);

cleanup_merge:
  for (resolved_index = 0; resolved_index < resolved_entry_count;
       resolved_index += 1) {
    free(resolved_entries[resolved_index].path);
  }
  free(resolved_entries);
  buffer_dispose(&conflicts);
  git_index_conflict_iterator_free(iterator);
  git_index_free(merged_index);
  git_tree_free(incoming_tree);
  git_commit_free(incoming_commit);
  git_tree_free(current_tree);
  git_commit_free(current_commit);
  git_tree_free(ancestor_tree);
  git_commit_free(ancestor_commit);
  git_repository_free(repository);
  return result;
}

static char *join_path(const char *parent, const char *child) {
  size_t parent_length;
  size_t child_length;
  size_t required;
  int needs_separator;
  char *result;

  if (parent == NULL || child == NULL) {
    return NULL;
  }
  parent_length = strlen(parent);
  child_length = strlen(child);
  needs_separator = parent_length > 0 && parent[parent_length - 1] != '/' &&
                    parent[parent_length - 1] != '\\';
  if (parent_length > SIZE_MAX - child_length - (size_t)needs_separator - 1) {
    return NULL;
  }
  required = parent_length + child_length + (size_t)needs_separator + 1;
  result = (char *)malloc(required);
  if (result == NULL) {
    return NULL;
  }
  snprintf(result, required, needs_separator ? "%s/%s" : "%s%s", parent,
           child);
  return result;
}

#ifdef _WIN32
/* Dart paths are UTF-8 regardless of the host process ANSI code page. */
static wchar_t *wide_path(const char *path) {
  int length;
  wchar_t *decoded;
  wchar_t *result;
  size_t index;
  size_t prefix_length = 0;
  size_t skip = 0;
  const wchar_t *prefix = L"";

  if (path == NULL ||
      (length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1,
                                    NULL, 0)) <= 0 ||
      (size_t)length > SIZE_MAX / sizeof(wchar_t) - 8) {
    return NULL;
  }
  decoded = (wchar_t *)malloc((size_t)length * sizeof(wchar_t));
  if (decoded == NULL) {
    return NULL;
  }
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, decoded,
                          length) != length) {
    free(decoded);
    return NULL;
  }
  /* Relative and drive-relative paths retain the CRT's ordinary semantics. */
  if (length > 3 &&
      ((decoded[0] >= L'A' && decoded[0] <= L'Z') ||
       (decoded[0] >= L'a' && decoded[0] <= L'z')) &&
      decoded[1] == L':' && (decoded[2] == L'/' || decoded[2] == L'\\')) {
    prefix = L"\\\\?\\";
    prefix_length = 4;
  } else if (length > 2 &&
             (decoded[0] == L'/' || decoded[0] == L'\\') &&
             (decoded[1] == L'/' || decoded[1] == L'\\')) {
    if (length > 4 && (decoded[2] == L'?' || decoded[2] == L'.') &&
        (decoded[3] == L'/' || decoded[3] == L'\\')) {
      /* Already in an extended or device namespace. */
      for (index = 0; index < (size_t)length; index += 1) {
        if (decoded[index] == L'/') decoded[index] = L'\\';
      }
      return decoded;
    }
    prefix = L"\\\\?\\UNC\\";
    prefix_length = 8;
    skip = 2;
  }
  if (prefix_length == 0) {
    return decoded;
  }
  result = (wchar_t *)malloc(
      (prefix_length + (size_t)length - skip) * sizeof(wchar_t));
  if (result != NULL) {
    memcpy(result, prefix, prefix_length * sizeof(wchar_t));
    for (index = skip; index < (size_t)length; index += 1) {
      result[prefix_length + index - skip] =
          decoded[index] == L'/' ? L'\\' : decoded[index];
    }
  }
  free(decoded);
  return result;
}
#endif

static FILE *path_fopen(const char *path, const char *mode) {
#ifdef _WIN32
  wchar_t *wide = wide_path(path);
  FILE *file;
  if (wide == NULL) {
    return NULL;
  }
  file = _wfopen(wide, strcmp(mode, "rb") == 0 ? L"rb" : L"wb");
  free(wide);
  return file;
#else
  return fopen(path, mode);
#endif
}

static int path_rename(const char *source, const char *target) {
#ifdef _WIN32
  wchar_t *wide_source = wide_path(source);
  wchar_t *wide_target = wide_path(target);
  int result = -1;
  /* No MOVEFILE_REPLACE_EXISTING: retain Windows CRT no-replace semantics. */
  if (wide_source != NULL && wide_target != NULL &&
      MoveFileExW(wide_source, wide_target, 0)) {
    result = 0;
  }
  free(wide_target);
  free(wide_source);
  return result;
#else
  return rename(source, target);
#endif
}

static int path_remove(const char *path) {
#ifdef _WIN32
  wchar_t *wide = wide_path(path);
  int result;
  if (wide == NULL) {
    return -1;
  }
  result = _wremove(wide);
  free(wide);
  return result;
#else
  return remove(path);
#endif
}

static int file_exists(const char *path) {
  FILE *file = path_fopen(path, "rb");
  if (file == NULL) {
    return 0;
  }
  fclose(file);
  return 1;
}

int32_t skills_workspace_revision_recovery_pack_create(
    const char *repository_path, const char *bundle_staging_path,
    const char *const *retained_root_oid_hex, intptr_t retained_root_count) {
  git_repository *repository = NULL;
  git_packbuilder *packbuilder = NULL;
  git_revwalk *walk = NULL;
  const char *pack_name;
  char generated_pack_name[64];
  char generated_index_name[64];
  char *generated_pack_path = NULL;
  char *generated_index_path = NULL;
  char *target_pack_path = NULL;
  char *target_index_path = NULL;
  intptr_t root_index;
  int32_t initialized = require_initialized();
  int32_t result;

  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  if (bundle_staging_path == NULL || bundle_staging_path[0] == '\0' ||
      retained_root_count <= 0 || retained_root_oid_hex == NULL) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }
  if (git_packbuilder_new(&packbuilder, repository) < 0 ||
      git_revwalk_new(&walk, repository) < 0) {
    result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup_pack_create;
  }
  for (root_index = 0; root_index < retained_root_count; root_index += 1) {
    git_oid root_oid;
    git_commit *root_commit = NULL;
    if (!parse_oid(&root_oid, retained_root_oid_hex[root_index]) ||
        git_commit_lookup(&root_commit, repository, &root_oid) < 0 ||
        git_revwalk_push(walk, &root_oid) < 0) {
      git_commit_free(root_commit);
      result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
      goto cleanup_pack_create;
    }
    git_commit_free(root_commit);
  }
  // insert_recur(commit) includes only that commit and its tree. A revwalk
  // explicitly traverses every parent, including every side of a merge.
  if (git_packbuilder_insert_walk(packbuilder, walk) < 0) {
    result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup_pack_create;
  }
  target_pack_path = join_path(bundle_staging_path, "objects.pack");
  target_index_path = join_path(bundle_staging_path, "objects.idx");
  if (target_pack_path == NULL || target_index_path == NULL ||
      file_exists(target_pack_path) || file_exists(target_index_path) ||
      git_packbuilder_write(packbuilder, bundle_staging_path, 0, NULL, NULL) <
          0 ||
      (pack_name = git_packbuilder_name(packbuilder)) == NULL) {
    result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup_pack_create;
  }
  if (snprintf(generated_pack_name, sizeof(generated_pack_name),
               "pack-%s.pack", pack_name) < 0 ||
      snprintf(generated_index_name, sizeof(generated_index_name),
               "pack-%s.idx", pack_name) < 0) {
    result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup_pack_create;
  }
  generated_pack_path = join_path(bundle_staging_path, generated_pack_name);
  generated_index_path = join_path(bundle_staging_path, generated_index_name);
  if (generated_pack_path == NULL || generated_index_path == NULL ||
      path_rename(generated_pack_path, target_pack_path) != 0 ||
      path_rename(generated_index_path, target_index_path) != 0) {
    if (file_exists(target_pack_path) && !file_exists(target_index_path)) {
      path_rename(target_pack_path, generated_pack_path);
    }
    result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup_pack_create;
  }
  result = SKILLS_WORKSPACE_REVISION_OK;

cleanup_pack_create:
  free(target_index_path);
  free(target_pack_path);
  free(generated_index_path);
  free(generated_pack_path);
  git_revwalk_free(walk);
  git_packbuilder_free(packbuilder);
  git_repository_free(repository);
  return result;
}

int32_t skills_workspace_revision_recovery_pack_create_bounded(
    const char *repository_path, const char *bundle_staging_path,
    const char *const *roots, intptr_t root_count,
    int64_t maximum_object_count, int64_t maximum_object_bytes,
    int64_t maximum_total_bytes, int64_t maximum_commit_bytes,
    int64_t maximum_parent_count) {
  git_repository *repository = NULL;
  git_odb *odb = NULL;
  revision_import_graph graph = {0};
  uint64_t total = 0;
  int32_t result = require_initialized();
  if (result != SKILLS_WORKSPACE_REVISION_OK) return result;
  if (roots == NULL || root_count < 1 || maximum_object_count < 1 ||
      maximum_object_bytes < 1 || maximum_total_bytes < 1 ||
      maximum_commit_bytes < 1 || maximum_parent_count < 0)
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  if (root_count > 1000000 || maximum_object_count > 1000000 ||
      maximum_object_bytes > 256LL * 1024 * 1024 || maximum_total_bytes > 8LL * 1024 * 1024 * 1024)
    return SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED;
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) return result;
  if (isolated_staging_odb(&odb, repository) < 0) {
    result = SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
    goto cleanup;
  }
  result = validate_revision_graph(&graph, repository, odb, roots, root_count,
      maximum_object_count, maximum_object_bytes, maximum_total_bytes,
      maximum_commit_bytes, maximum_parent_count, NULL, &total);
cleanup:
  free(graph.slots); free(graph.nodes);
  git_odb_free(odb); git_repository_free(repository);
  if (result != SKILLS_WORKSPACE_REVISION_OK) return result;
  return skills_workspace_revision_recovery_pack_create(repository_path,
      bundle_staging_path, roots, root_count);
}

static int copy_file(const char *source_path, const char *target_path) {
  FILE *source = NULL;
  FILE *target = NULL;
  uint8_t buffer[64 * 1024];
  size_t read_count;
  int result = -1;

  source = path_fopen(source_path, "rb");
  if (source == NULL) {
    goto cleanup_copy;
  }
  target = path_fopen(target_path, "wb");
  if (target == NULL) {
    goto cleanup_copy;
  }
  while ((read_count = fread(buffer, 1, sizeof(buffer), source)) > 0) {
    if (fwrite(buffer, 1, read_count, target) != read_count) {
      goto cleanup_copy;
    }
  }
  if (ferror(source) || fflush(target) != 0) {
    goto cleanup_copy;
  }
  result = 0;

cleanup_copy:
  if (target != NULL && fclose(target) != 0) {
    result = -1;
  }
  if (source != NULL) {
    fclose(source);
  }
  if (result != 0) {
    path_remove(target_path);
  }
  return result;
}

static int pack_trailer_name(const char *pack_path, char output[41]) {
  FILE *pack = NULL;
  uint8_t header[4];
  uint8_t trailer[20];
  long length;
  size_t index;
  static const char hex[] = "0123456789abcdef";
  int result = -1;

  pack = path_fopen(pack_path, "rb");
  if (pack == NULL || fread(header, 1, sizeof(header), pack) != sizeof(header) ||
      memcmp(header, "PACK", sizeof(header)) != 0 ||
      fseek(pack, 0, SEEK_END) != 0 || (length = ftell(pack)) < 32 ||
      fseek(pack, length - 20, SEEK_SET) != 0 ||
      fread(trailer, 1, sizeof(trailer), pack) != sizeof(trailer)) {
    goto cleanup_pack_name;
  }
  for (index = 0; index < sizeof(trailer); index += 1) {
    output[index * 2] = hex[trailer[index] >> 4];
    output[index * 2 + 1] = hex[trailer[index] & 0x0f];
  }
  output[40] = '\0';
  result = 0;

cleanup_pack_name:
  if (pack != NULL) {
    fclose(pack);
  }
  return result;
}

typedef struct odb_verify_context {
  git_odb *odb;
  int failed;
  int64_t object_count;
  uint64_t total_bytes;
  int64_t maximum_object_count, maximum_object_bytes, maximum_total_bytes;
  int64_t maximum_commit_bytes;
  int limit_exceeded;
  const int32_t *cancel_flag;
} odb_verify_context;

static int verify_odb_object(const git_oid *oid, void *payload) {
  odb_verify_context *context = (odb_verify_context *)payload;
  git_odb_object *object = NULL;
  size_t size;
  git_object_t type;
  if (context == NULL || oid == NULL) return -1;
  if (revision_import_cancelled(context->cancel_flag)) goto failed;
  if (context->maximum_object_count > 0) {
    if (context->object_count >= context->maximum_object_count) goto limit;
    if (git_odb_read_header(&size, &type, context->odb, oid) < 0) goto failed;
    if ((uint64_t)size > (uint64_t)context->maximum_object_bytes ||
        (uint64_t)size > (uint64_t)context->maximum_total_bytes - context->total_bytes ||
        (type == GIT_OBJECT_COMMIT && (uint64_t)size > (uint64_t)context->maximum_commit_bytes)) goto limit;
    context->total_bytes += size;
    if (read_verified_object(&object, context->odb, oid, type, (uint64_t)size) != SKILLS_WORKSPACE_REVISION_OK) goto failed;
  } else if (git_odb_read(&object, context->odb, oid) < 0) goto failed;
  context->object_count += 1;
  git_odb_object_free(object);
  return 0;
limit:
  context->limit_exceeded = 1;
failed:
  context->failed = 1;
  git_odb_object_free(object);
  return -1;
}

static int32_t preflight_pack(const char *, const char *, int64_t, int64_t,
    int64_t, int64_t, int64_t, const int32_t *);

static int32_t copy_bounded_pack_file(const char *source_path, const char *target_path,
                                     uint64_t maximum_bytes, const int32_t *cancel_flag) {
  FILE *source = path_fopen(source_path, "rb"), *target = NULL;
  uint8_t buffer[32768];
  uint64_t total = 0;
  size_t count;
  int32_t result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
  if (source == NULL || (target = path_fopen(target_path, "wb")) == NULL) goto cleanup;
  while ((count = fread(buffer, 1, sizeof(buffer), source)) > 0) {
    if (revision_import_cancelled(cancel_flag)) { result = SKILLS_WORKSPACE_REVISION_CANCELLED; goto cleanup; }
    if (count > maximum_bytes - total) {
      result = SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED;
      goto cleanup;
    }
    total += count;
    if (fwrite(buffer, 1, count, target) != count) goto cleanup;
  }
  if (ferror(source) || fflush(target) != 0) goto cleanup;
  result = SKILLS_WORKSPACE_REVISION_OK;
cleanup:
  if (target != NULL && fclose(target) != 0) result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
  if (source != NULL) fclose(source);
  if (result != SKILLS_WORKSPACE_REVISION_OK) path_remove(target_path);
  return result;
}

static int32_t recovery_pack_restore(
    const char *staged_repository_path, const char *pack_path,
    const char *index_path, const char *const *retained_root_oid_hex,
    intptr_t retained_root_count, int64_t maximum_object_count,
    int64_t maximum_object_bytes, int64_t maximum_total_bytes,
    int64_t maximum_commit_bytes, int64_t maximum_parent_count,
    int64_t maximum_delta_depth, const int32_t *cancel_flag) {
  git_repository *repository = NULL;
  git_odb *odb = NULL;
  odb_verify_context verify_context;
  revision_import_graph graph = {0};
  uint64_t verified_total = 0;
  char pack_name[41];
  char generated_pack_name[64];
  char generated_index_name[64];
  char *objects_path = NULL;
  char *pack_directory_path = NULL;
  char *target_pack_path = NULL;
  char *target_index_path = NULL;
  int32_t initialized = require_initialized();
  int32_t result;

  memset(&verify_context, 0, sizeof(verify_context));
  if (initialized != SKILLS_WORKSPACE_REVISION_OK) {
    return initialized;
  }
  if (pack_path == NULL || index_path == NULL || retained_root_count <= 0 ||
      retained_root_oid_hex == NULL || pack_trailer_name(pack_path, pack_name) <
          0) {
    return SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
  }
  result = create_bare_repository(&repository, staged_repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
  }
  git_repository_free(repository);
  repository = NULL;
  objects_path = join_path(staged_repository_path, "objects");
  pack_directory_path = join_path(objects_path, "pack");
  if (snprintf(generated_pack_name, sizeof(generated_pack_name),
               "pack-%s.pack", pack_name) < 0 ||
      snprintf(generated_index_name, sizeof(generated_index_name),
               "pack-%s.idx", pack_name) < 0) {
    result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup_pack_restore;
  }
  target_pack_path = join_path(pack_directory_path, generated_pack_name);
  target_index_path = join_path(pack_directory_path, generated_index_name);
  if (objects_path == NULL || pack_directory_path == NULL ||
      target_pack_path == NULL || target_index_path == NULL) {
    result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup_pack_restore;
  }
  if (maximum_object_count > 0) {
    result = copy_bounded_pack_file(pack_path, target_pack_path, (uint64_t)maximum_total_bytes, cancel_flag);
    if (result != SKILLS_WORKSPACE_REVISION_OK) goto cleanup_pack_restore;
    result = copy_bounded_pack_file(index_path, target_index_path,
        1072ULL + 36ULL * (uint64_t)maximum_object_count, cancel_flag);
    if (result != SKILLS_WORKSPACE_REVISION_OK) goto cleanup_pack_restore;
    // Validate only the owned copies. The caller's source files can no longer
    // change the bytes later opened by libgit2 after this preflight.
    result = preflight_pack(target_pack_path, target_index_path, maximum_object_count,
        maximum_object_bytes, maximum_total_bytes, maximum_commit_bytes, maximum_delta_depth, cancel_flag);
    if (result != SKILLS_WORKSPACE_REVISION_OK) goto cleanup_pack_restore;
  } else if (copy_file(pack_path, target_pack_path) < 0 ||
             copy_file(index_path, target_index_path) < 0) {
    result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup_pack_restore;
  }
  result = open_bare_repository(&repository, staged_repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK ||
      git_repository_odb(&odb, repository) < 0 || git_odb_refresh(odb) < 0) {
    result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup_pack_restore;
  }
  verify_context.odb = odb;
  verify_context.maximum_object_count = maximum_object_count;
  verify_context.maximum_object_bytes = maximum_object_bytes;
  verify_context.maximum_total_bytes = maximum_total_bytes;
  verify_context.maximum_commit_bytes = maximum_commit_bytes;
  verify_context.cancel_flag = cancel_flag;
  if (git_odb_foreach(odb, verify_odb_object, &verify_context) < 0 ||
      verify_context.failed) {
    result = revision_import_cancelled(cancel_flag) ? SKILLS_WORKSPACE_REVISION_CANCELLED : verify_context.limit_exceeded ? SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED
                                          : SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup_pack_restore;
  }
  if (verify_context.object_count == 0) {
    result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup_pack_restore;
  }
  result = validate_revision_graph(&graph, repository, odb,
      retained_root_oid_hex, retained_root_count, verify_context.object_count,
      maximum_object_count > 0 ? maximum_object_bytes : INT64_MAX,
      maximum_object_count > 0 ? maximum_total_bytes : INT64_MAX,
      maximum_object_count > 0 ? maximum_commit_bytes : INT64_MAX,
      maximum_object_count > 0 ? maximum_parent_count : UINT32_MAX,
      cancel_flag, &verified_total);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    if (result != SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED)
      result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup_pack_restore;
  }
  result = SKILLS_WORKSPACE_REVISION_OK;

cleanup_pack_restore:
  free(graph.slots);
  free(graph.nodes);
  git_odb_free(odb);
  git_repository_free(repository);
  free(target_index_path);
  free(target_pack_path);
  free(pack_directory_path);
  free(objects_path);
  return result;
}

int32_t skills_workspace_revision_recovery_pack_restore(
    const char *staged_repository_path, const char *pack_path,
    const char *index_path, const char *const *retained_root_oid_hex,
    intptr_t retained_root_count) {
  return recovery_pack_restore(staged_repository_path, pack_path, index_path,
      retained_root_oid_hex, retained_root_count, 0, 0, 0, 0, 0, 0, NULL);
}

typedef struct preflight_pack_object {
  uint64_t offset, declared_size, base_size, result_size;
  int64_t base;
  uint8_t type, resolved_type, visit, indexed;
  unsigned int depth;
  uint8_t base_oid[20];
} preflight_pack_object;
typedef struct preflight_index_entry { uint8_t oid[20]; uint32_t object; } preflight_index_entry;

static int pf_seek(FILE *file, int64_t offset, int origin) {
#ifdef _WIN32
  return _fseeki64(file, offset, origin);
#else
  return fseeko(file, (off_t)offset, origin);
#endif
}
static int64_t pf_tell(FILE *file) {
#ifdef _WIN32
  return _ftelli64(file);
#else
  return (int64_t)ftello(file);
#endif
}
static int pf_read(FILE *file, void *output, size_t count) {
  return fread(output, 1, count, file) == count;
}
static uint32_t pf_u32(const uint8_t bytes[4]) {
  return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
         ((uint32_t)bytes[2] << 8) | bytes[3];
}
static int pf_varints(const uint8_t *bytes, size_t length, uint64_t *base, uint64_t *result) {
  size_t i = 0;
  unsigned int field;
  for (field = 0; field < 2; ++field) {
    uint64_t value = 0;
    unsigned int shift = 0;
    for (;;) {
      uint8_t byte;
      if (i == length) return 0;
      byte = bytes[i++];
      if (shift >= 64 || ((uint64_t)(byte & 127) > (UINT64_MAX >> shift))) return -1;
      value |= (uint64_t)(byte & 127) << shift;
      if (!(byte & 128)) break;
      shift += 7;
    }
    if (field == 0) *base = value; else *result = value;
  }
  return 1;
}
static int64_t pf_find_offset(const preflight_pack_object *objects, uint32_t count, uint64_t offset) {
  uint32_t low = 0, high = count;
  while (low < high) {
    uint32_t mid = low + (high - low) / 2;
    if (objects[mid].offset < offset) low = mid + 1; else high = mid;
  }
  return low < count && objects[low].offset == offset ? (int64_t)low : -1;
}
static int64_t pf_find_oid(const preflight_index_entry *entries, uint32_t count, const uint8_t *oid) {
  uint32_t low = 0, high = count;
  while (low < high) {
    uint32_t mid = low + (high - low) / 2;
    if (memcmp(entries[mid].oid, oid, 20) < 0) low = mid + 1; else high = mid;
  }
  return low < count && memcmp(entries[low].oid, oid, 20) == 0 ? (int64_t)entries[low].object : -1;
}

// Preflight precedes every libgit2 pack reader. Inflate into fixed buffers and
// inspect both declared and actual sizes, including delta result sizes, before
// a library can allocate an object/result buffer. The v2 index supplies only
// dependency addresses here; object hashes/connectivity are checked afterward.
static int32_t preflight_pack(const char *pack_path, const char *index_path,
    int64_t maximum_count, int64_t maximum_object_bytes, int64_t maximum_total_bytes,
    int64_t maximum_commit_bytes, int64_t maximum_delta_depth, const int32_t *cancel_flag) {
  FILE *pack = NULL, *index = NULL;
  preflight_pack_object *objects = NULL;
  preflight_index_entry *entries = NULL;
  uint32_t *stack = NULL;
  uint8_t header[12], word[8], trailer[20];
  uint32_t count = 0, i, j, fanout[256], histogram[256] = {0}, raw_delta_count = 0;
  uint64_t final_total = 0, inflated_total = 0;
  int64_t pack_length, index_length;
  int32_t status = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
  pack = path_fopen(pack_path, "rb");
  if (pack == NULL || pf_seek(pack, 0, SEEK_END) != 0 ||
      (pack_length = pf_tell(pack)) < 32 || pf_seek(pack, 0, SEEK_SET) != 0 ||
      !pf_read(pack, header, 12) || memcmp(header, "PACK", 4) != 0 ||
      (pf_u32(header + 4) != 2 && pf_u32(header + 4) != 3)) goto done;
  if ((uint64_t)pack_length > (uint64_t)maximum_total_bytes) goto limit;
  count = pf_u32(header + 8);
  if (count == 0) goto done;
  if ((uint64_t)count > (uint64_t)maximum_count) goto limit;
  objects = calloc(count, sizeof(preflight_pack_object));
  entries = calloc(count, sizeof(preflight_index_entry));
  stack = calloc(count, sizeof(uint32_t));
  if (objects == NULL || entries == NULL || stack == NULL) goto done;
  for (i = 0; i < count; ++i) {
    if (revision_import_cancelled(cancel_flag)) { status = SKILLS_WORKSPACE_REVISION_CANCELLED; goto done; }
    preflight_pack_object *object = &objects[i];
    uint8_t byte;
    unsigned int shift = 4;
    uint64_t size, output_count = 0;
    uint8_t input_buffer[32768], output_buffer[16384], prefix[20];
    size_t prefix_length = 0;
    int delta_ready = 0, code;
    z_stream stream;
    object->offset = (uint64_t)pf_tell(pack);
    object->base = -1;
    if (!pf_read(pack, &byte, 1)) goto done;
    object->type = (byte >> 4) & 7;
    size = byte & 15;
    while (byte & 128) {
      if (!pf_read(pack, &byte, 1) || shift >= 64 ||
          ((uint64_t)(byte & 127) > (UINT64_MAX >> shift))) goto done;
      size |= (uint64_t)(byte & 127) << shift;
      shift += 7;
    }
    if (object->type == 0 || object->type == 5) goto done;
    object->declared_size = size;
    // Without an index, conservatively cap the total number of delta objects.
    // This bounds any possible REF dependency chain before the indexer runs.
    // The indexed preflight below validates exact dependencies and depth.
    if (index_path == NULL && object->type >= 6 && ++raw_delta_count > (uint64_t)maximum_delta_depth) goto limit;
    if (size > (uint64_t)maximum_object_bytes) goto limit;
    if (object->type == 6) {
      uint64_t distance;
      if (!pf_read(pack, &byte, 1)) goto done;
      distance = byte & 127;
      while (byte & 128) {
        if (!pf_read(pack, &byte, 1) || distance >= (UINT64_MAX >> 7)) goto done;
        distance = ((distance + 1) << 7) | (byte & 127);
      }
      if (distance == 0 || distance > object->offset ||
          (object->base = pf_find_offset(objects, i, object->offset - distance)) < 0) goto done;
    } else if (object->type == 7) {
      if (!pf_read(pack, object->base_oid, 20)) goto done;
    } else {
      object->resolved_type = object->type;
      object->result_size = size;
      if (object->type == 1 && size > (uint64_t)maximum_commit_bytes) goto limit;
      if (size > (uint64_t)maximum_total_bytes - final_total) goto limit;
      final_total += size;
    }
    memset(&stream, 0, sizeof(stream));
    if (inflateInit(&stream) != Z_OK) goto done;
    for (;;) {
      size_t produced;
      if (revision_import_cancelled(cancel_flag)) { inflateEnd(&stream); status = SKILLS_WORKSPACE_REVISION_CANCELLED; goto done; }
      if (stream.avail_in == 0) {
        stream.avail_in = (uInt)fread(input_buffer, 1, sizeof(input_buffer), pack);
        stream.next_in = input_buffer;
        if (stream.avail_in == 0) { inflateEnd(&stream); goto done; }
      }
      stream.next_out = output_buffer;
      stream.avail_out = (uInt)sizeof(output_buffer);
      code = inflate(&stream, Z_NO_FLUSH);
      produced = sizeof(output_buffer) - stream.avail_out;
      if (produced > (uint64_t)maximum_object_bytes - output_count ||
          produced > (uint64_t)maximum_total_bytes - inflated_total) {
        inflateEnd(&stream); goto limit;
      }
      output_count += produced;
      inflated_total += produced;
      if (output_count > object->declared_size) { inflateEnd(&stream); goto done; }
      if (object->type >= 6 && !delta_ready) {
        size_t take = produced < sizeof(prefix) - prefix_length ? produced : sizeof(prefix) - prefix_length;
        int parsed;
        memcpy(prefix + prefix_length, output_buffer, take);
        prefix_length += take;
        parsed = pf_varints(prefix, prefix_length, &object->base_size, &object->result_size);
        if (parsed < 0 || (parsed == 0 && prefix_length == sizeof(prefix))) { inflateEnd(&stream); goto done; }
        if (parsed == 1) {
          delta_ready = 1;
          if (object->base_size > (uint64_t)maximum_object_bytes ||
              object->result_size > (uint64_t)maximum_object_bytes ||
              object->result_size > (uint64_t)maximum_total_bytes - final_total) {
            inflateEnd(&stream); goto limit;
          }
          final_total += object->result_size;
        }
      }
      if (code == Z_STREAM_END) {
        int remaining = (int)stream.avail_in;
        inflateEnd(&stream);
        if (pf_seek(pack, -remaining, SEEK_CUR) != 0 || output_count != size ||
            (object->type >= 6 && !delta_ready)) goto done;
        break;
      }
      if (code != Z_OK) { inflateEnd(&stream); goto done; }
    }
  }
  if (pf_tell(pack) != pack_length - 20 || !pf_read(pack, trailer, 20)) goto done;
  if (index_path == NULL) { status = SKILLS_WORKSPACE_REVISION_OK; goto done; }
  index = path_fopen(index_path, "rb");
  if (index == NULL || pf_seek(index, 0, SEEK_END) != 0 ||
      (index_length = pf_tell(index)) < 1072 || pf_seek(index, 0, SEEK_SET) != 0 ||
      !pf_read(index, word, 8) || pf_u32(word) != 0xff744f63U || pf_u32(word + 4) != 2) goto done;
  if ((uint64_t)index_length < 1072ULL + 28ULL * count ||
      (uint64_t)index_length > 1072ULL + 36ULL * count) goto done;
  for (i = 0; i < 256; ++i) {
    if (!pf_read(index, word, 4)) goto done;
    fanout[i] = pf_u32(word);
    if ((i && fanout[i] < fanout[i - 1]) || fanout[i] > count) goto done;
  }
  if (fanout[255] != count) goto done;
  for (i = 0; i < count; ++i) {
    if (revision_import_cancelled(cancel_flag)) { status = SKILLS_WORKSPACE_REVISION_CANCELLED; goto done; }
    if (!pf_read(index, entries[i].oid, 20) ||
        (i && memcmp(entries[i - 1].oid, entries[i].oid, 20) >= 0)) goto done;
    histogram[entries[i].oid[0]]++;
  }
  for (i = 0, j = 0; i < 256; ++i) {
    j += histogram[i];
    if (fanout[i] != j) goto done;
  }
  for (i = 0; i < count; ++i) {
    if (revision_import_cancelled(cancel_flag)) { status = SKILLS_WORKSPACE_REVISION_CANCELLED; goto done; }
    uint64_t offset;
    int64_t object_index;
    if (pf_seek(index, 1032LL + 24LL * count + 4LL * i, SEEK_SET) != 0 || !pf_read(index, word, 4)) goto done;
    offset = pf_u32(word);
    if (offset & 0x80000000U) {
      uint64_t large = offset & 0x7fffffffU;
      if (1032ULL + 28ULL * count + large * 8 + 8 > (uint64_t)index_length - 40 ||
          pf_seek(index, (int64_t)(1032ULL + 28ULL * count + large * 8), SEEK_SET) != 0 || !pf_read(index, word, 8)) goto done;
      offset = ((uint64_t)pf_u32(word) << 32) | pf_u32(word + 4);
    }
    object_index = pf_find_offset(objects, count, offset);
    if (object_index < 0 || objects[object_index].indexed) goto done;
    objects[object_index].indexed = 1;
    entries[i].object = (uint32_t)object_index;
  }
  if (pf_seek(index, index_length - 40, SEEK_SET) != 0 || !pf_read(index, header, 12) ||
      memcmp(header, trailer, 12) != 0 || !pf_read(index, word, 8) || memcmp(word, trailer + 12, 8) != 0) goto done;
  for (i = 0; i < count; ++i) {
    if (revision_import_cancelled(cancel_flag)) { status = SKILLS_WORKSPACE_REVISION_CANCELLED; goto done; }
    if (objects[i].type == 7 &&
        (objects[i].base = pf_find_oid(entries, count, objects[i].base_oid)) < 0) goto done;
  }
  for (i = 0; i < count; ++i) {
    if (revision_import_cancelled(cancel_flag)) { status = SKILLS_WORKSPACE_REVISION_CANCELLED; goto done; }
    uint32_t cursor = i, length = 0;
    while (objects[cursor].visit != 2) {
      if (revision_import_cancelled(cancel_flag)) { status = SKILLS_WORKSPACE_REVISION_CANCELLED; goto done; }
      if (objects[cursor].visit == 1) goto done;
      objects[cursor].visit = 1;
      stack[length++] = cursor;
      if (objects[cursor].base < 0) break;
      cursor = (uint32_t)objects[cursor].base;
    }
    while (length) {
      preflight_pack_object *object = &objects[stack[--length]];
      if (object->base >= 0) {
        preflight_pack_object *base = &objects[object->base];
        object->depth = base->depth + 1;
        object->resolved_type = base->resolved_type;
        if (object->base_size != base->result_size) goto done;
        if ((uint64_t)object->depth > (uint64_t)maximum_delta_depth) goto limit;
        if (object->resolved_type == 1 && object->result_size > (uint64_t)maximum_commit_bytes) goto limit;
      }
      object->visit = 2;
    }
  }
  status = SKILLS_WORKSPACE_REVISION_OK;
  goto done;
limit:
  status = SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED;
done:
  free(stack); free(entries); free(objects);
  if (index != NULL) fclose(index);
  if (pack != NULL) fclose(pack);
  return status;
}

int32_t skills_workspace_revision_recovery_pack_restore_bounded(
    const char *staged_repository_path, const char *pack_path,
    const char *index_path, const char *const *retained_root_oid_hex,
    intptr_t retained_root_count, int64_t maximum_object_count,
    int64_t maximum_object_bytes, int64_t maximum_total_bytes,
    int64_t maximum_commit_bytes, int64_t maximum_parent_count,
    int64_t maximum_delta_depth, const int32_t *cancel_flag) {
  if (maximum_object_count < 1 || maximum_object_bytes < 1 ||
      maximum_total_bytes < 1 || maximum_commit_bytes < 1 || maximum_parent_count < 0 || maximum_delta_depth < 0)
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  if (maximum_object_count > 1000000 || maximum_object_bytes > 256LL * 1024 * 1024 ||
      maximum_total_bytes > 8LL * 1024 * 1024 * 1024)
    return SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED;
  return recovery_pack_restore(staged_repository_path, pack_path, index_path,
      retained_root_oid_hex, retained_root_count, maximum_object_count,
      maximum_object_bytes, maximum_total_bytes, maximum_commit_bytes, maximum_parent_count, maximum_delta_depth, cancel_flag);
}

static int revision_index_cancel(const git_indexer_progress *stats, void *payload) {
  (void)stats;
  return revision_import_cancelled((const int32_t *)payload) ? GIT_EUSER : 0;
}

int32_t skills_workspace_revision_pack_index_create_bounded(
    const char *pack_path, const char *staging_directory,
    int64_t maximum_object_count, int64_t maximum_object_bytes,
    int64_t maximum_total_bytes, int64_t maximum_commit_bytes,
    int64_t maximum_delta_depth, const int32_t *cancel_flag) {
  git_indexer *indexer = NULL;
  git_indexer_options options = GIT_INDEXER_OPTIONS_INIT;
  git_indexer_progress progress = {0};
  FILE *input = NULL;
  uint8_t bytes[32768];
  size_t count;
  char pack_name[64], index_name[64];
  char *owned = NULL, *target_pack = NULL, *target_index = NULL;
  char *generated_pack = NULL, *generated_index = NULL;
  const char *name;
  int32_t result = require_initialized();
  if (result != SKILLS_WORKSPACE_REVISION_OK) return result;
  if (pack_path == NULL || staging_directory == NULL || maximum_object_count < 1 ||
      maximum_object_bytes < 1 || maximum_total_bytes < 1 || maximum_commit_bytes < 1 || maximum_delta_depth < 0)
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  if (maximum_object_count > 1000000 || maximum_object_bytes > 256LL * 1024 * 1024 || maximum_total_bytes > 8LL * 1024 * 1024 * 1024)
    return SKILLS_WORKSPACE_REVISION_LIMIT_EXCEEDED;
  owned = join_path(staging_directory, "input.pack");
  target_pack = join_path(staging_directory, "objects.pack");
  target_index = join_path(staging_directory, "objects.idx");
  if (owned == NULL || target_pack == NULL || target_index == NULL ||
      file_exists(owned) || file_exists(target_pack) || file_exists(target_index)) {
    result = SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
    goto cleanup;
  }
  result = copy_bounded_pack_file(pack_path, owned, (uint64_t)maximum_total_bytes, cancel_flag);
  if (result != SKILLS_WORKSPACE_REVISION_OK) goto cleanup;
  // Before an index exists, validate every declared/inflated/delta-result size
  // and their aggregate in fixed buffers. The indexer receives only this owned
  // copy; a thin pack has no external ODB to resolve against.
  result = preflight_pack(owned, NULL, maximum_object_count, maximum_object_bytes,
      maximum_total_bytes, maximum_commit_bytes, maximum_delta_depth, cancel_flag);
  if (result != SKILLS_WORKSPACE_REVISION_OK) goto cleanup;
  options.verify = 1;
  options.progress_cb = revision_index_cancel;
  options.progress_cb_payload = (void *)cancel_flag;
  if (git_indexer_new(&indexer, staging_directory, 0, NULL, &options) < 0 ||
      (input = path_fopen(owned, "rb")) == NULL) {
    result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup;
  }
  while ((count = fread(bytes, 1, sizeof(bytes), input)) > 0) {
    if (revision_import_cancelled(cancel_flag) || git_indexer_append(indexer, bytes, count, &progress) < 0) {
      result = revision_import_cancelled(cancel_flag) ? SKILLS_WORKSPACE_REVISION_CANCELLED : SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
      goto cleanup;
    }
  }
  if (ferror(input) || git_indexer_commit(indexer, &progress) < 0 ||
      (name = git_indexer_name(indexer)) == NULL) {
    result = revision_import_cancelled(cancel_flag) ? SKILLS_WORKSPACE_REVISION_CANCELLED : SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup;
  }
  snprintf(pack_name, sizeof(pack_name), "pack-%s.pack", name);
  snprintf(index_name, sizeof(index_name), "pack-%s.idx", name);
  generated_pack = join_path(staging_directory, pack_name);
  generated_index = join_path(staging_directory, index_name);
  if (generated_pack == NULL || generated_index == NULL) {
    result = SKILLS_WORKSPACE_REVISION_OBJECT_FAILURE;
    goto cleanup;
  }
  git_indexer_free(indexer);
  indexer = NULL;
  result = preflight_pack(generated_pack, generated_index, maximum_object_count,
      maximum_object_bytes, maximum_total_bytes, maximum_commit_bytes, maximum_delta_depth, cancel_flag);
  if (result != SKILLS_WORKSPACE_REVISION_OK) goto cleanup;
  if (path_rename(generated_pack, target_pack) != 0 ||
      path_rename(generated_index, target_index) != 0) {
    result = SKILLS_WORKSPACE_REVISION_BUNDLE_FAILURE;
    goto cleanup;
  }
  result = SKILLS_WORKSPACE_REVISION_OK;
cleanup:
  if (input != NULL) fclose(input);
  git_indexer_free(indexer);
  if (owned != NULL) path_remove(owned);
  free(generated_pack); free(generated_index);
  free(owned); free(target_pack); free(target_index);
  return result;
}

static int retention_ref_name_is_valid(const char *name) {
  int valid = 0;
  const char prefix[] = "refs/skills-workspace/";
  if (name == NULL || strncmp(name, prefix, sizeof(prefix) - 1) != 0 ||
      name[sizeof(prefix) - 1] == '\0' ||
      git_reference_name_is_valid(&valid, name) < 0 || !valid) {
    return 0;
  }
  // Retention names are generated internally.  Keep the ABI fail-closed even
  // if a future caller accidentally passes a path-like or NUL-containing name.
  if (strstr(name, "..") != NULL || strchr(name, '\\') != NULL) {
    return 0;
  }
  return 1;
}

static int retention_ref_name_is_owned(const char *name) {
  static const char prefix[] = "refs/skills-workspace/";
  return name != NULL && strncmp(name, prefix, sizeof(prefix) - 1) == 0;
}

int32_t skills_workspace_revision_retention_refs_replace(
    const char *repository_path, const char *const *ref_names,
    const char *const *target_oid_hex, intptr_t ref_count) {
  git_repository *repository = NULL;
  git_transaction *transaction = NULL;
  git_strarray existing = {0};
  intptr_t index;
  int32_t result = require_initialized();

  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }
  if (repository_path == NULL || repository_path[0] == '\0' || ref_count < 0 ||
      (ref_count > 0 && (ref_names == NULL || target_oid_hex == NULL))) {
    return SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
  }
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    return result;
  }

  // Validate the complete desired set before mutating any ref.  This keeps a
  // malformed request from partially replacing a healthy derived set.
  for (index = 0; index < ref_count; index += 1) {
    git_oid target_oid;
    git_commit *commit = NULL;
    intptr_t previous;
    if (!retention_ref_name_is_valid(ref_names[index]) ||
        !parse_oid(&target_oid, target_oid_hex[index]) ||
        git_commit_lookup(&commit, repository, &target_oid) < 0) {
      git_commit_free(commit);
      result = SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
      goto cleanup_retention_refs;
    }
    git_commit_free(commit);
    for (previous = 0; previous < index; previous += 1) {
      if (strcmp(ref_names[previous], ref_names[index]) == 0) {
        result = SKILLS_WORKSPACE_REVISION_INVALID_ARGUMENT;
        goto cleanup_retention_refs;
      }
    }
  }

  if (git_reference_list(&existing, repository) < 0) {
    result = SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
    goto cleanup_retention_refs;
  }
  if (git_transaction_new(&transaction, repository) < 0) {
    result = SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
    goto cleanup_retention_refs;
  }
  for (index = 0; index < ref_count; index += 1) {
    if (git_transaction_lock_ref(transaction, ref_names[index]) < 0) {
      result = SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
      goto cleanup_retention_refs;
    }
  }
  for (index = 0; index < (intptr_t)existing.count; index += 1) {
    intptr_t desired;
    const char *name = existing.strings[index];
    if (!retention_ref_name_is_owned(name)) {
      continue;
    }
    for (desired = 0; desired < ref_count; desired += 1) {
      if (strcmp(name, ref_names[desired]) == 0) {
        break;
      }
    }
    if (desired == ref_count && git_transaction_lock_ref(transaction, name) < 0) {
      result = SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
      goto cleanup_retention_refs;
    }
  }
  for (index = 0; index < ref_count; index += 1) {
    git_oid target_oid;
    if (!parse_oid(&target_oid, target_oid_hex[index]) ||
        git_transaction_set_target(transaction, ref_names[index], &target_oid,
                                   NULL,
                                   "skills-workspace:reconcile") < 0) {
      result = SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
      goto cleanup_retention_refs;
    }
  }
  for (index = 0; index < (intptr_t)existing.count; index += 1) {
    intptr_t desired;
    const char *name = existing.strings[index];
    if (!retention_ref_name_is_owned(name)) {
      continue;
    }
    for (desired = 0; desired < ref_count; desired += 1) {
      if (strcmp(name, ref_names[desired]) == 0) {
        break;
      }
    }
    if (desired == ref_count && git_transaction_remove(transaction, name) < 0) {
      result = SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
      goto cleanup_retention_refs;
    }
  }
  if (git_transaction_commit(transaction) < 0) {
    result = SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
    goto cleanup_retention_refs;
  }
  git_transaction_free(transaction);
  transaction = NULL;
  git_strarray_dispose(&existing);
  git_repository_free(repository);
  repository = NULL;
  result = open_bare_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_REVISION_OK) {
    goto cleanup_retention_refs;
  }
  for (index = 0; index < ref_count; index += 1) {
    git_oid expected_oid;
    git_oid actual_oid;
    if (!parse_oid(&expected_oid, target_oid_hex[index]) ||
        git_reference_name_to_id(&actual_oid, repository, ref_names[index]) <
            0 ||
        !git_oid_equal(&expected_oid, &actual_oid)) {
      result = SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
      goto cleanup_retention_refs;
    }
  }
  if (git_reference_list(&existing, repository) < 0) {
    result = SKILLS_WORKSPACE_REVISION_REPOSITORY_FAILURE;
    goto cleanup_retention_refs;
  }
  {
    intptr_t owned_count = 0;
    for (index = 0; index < (intptr_t)existing.count; index += 1) {
      intptr_t desired;
      const char *name = existing.strings[index];
      if (!retention_ref_name_is_owned(name)) {
        continue;
      }
      owned_count += 1;
      for (desired = 0; desired < ref_count; desired += 1) {
        if (strcmp(name, ref_names[desired]) == 0) {
          break;
        }
      }
      if (desired == ref_count) {
        result = SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
        goto cleanup_retention_refs;
      }
    }
    if (owned_count != ref_count) {
      result = SKILLS_WORKSPACE_REVISION_VERIFICATION_FAILURE;
      goto cleanup_retention_refs;
    }
  }
  result = SKILLS_WORKSPACE_REVISION_OK;

cleanup_retention_refs:
  git_transaction_free(transaction);
  git_strarray_dispose(&existing);
  git_repository_free(repository);
  return result;
}
