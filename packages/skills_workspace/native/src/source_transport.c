#include "skills_workspace_native.h"
#include "skills_workspace_runtime.h"

#include <git2.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#include <winhttp.h>
#endif

typedef struct transport_buffer {
  uint8_t *bytes;
  size_t length;
  size_t capacity;
} transport_buffer;

typedef struct fetch_context {
  const int32_t *cancel_flag;
} fetch_context;

typedef struct fetch_head_context {
  git_oid oid;
  int found;
} fetch_head_context;

typedef struct tree_list_context {
  transport_buffer output;
  const char *prefix;
  int failed;
} tree_list_context;

static int is_cancelled(const fetch_context *context) {
  return context != NULL && context->cancel_flag != NULL &&
         *(const volatile int32_t *)context->cancel_flag != 0;
}

static int buffer_append(transport_buffer *buffer, const void *bytes,
                         size_t length) {
  size_t required;
  size_t next_capacity;
  uint8_t *next;

  if (length == 0) {
    return 0;
  }
  if (buffer == NULL || bytes == NULL ||
      length > SIZE_MAX - buffer->length) {
    return -1;
  }
  required = buffer->length + length;
  if (required > buffer->capacity) {
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
  }
  memcpy(buffer->bytes + buffer->length, bytes, length);
  buffer->length += length;
  return 0;
}

static int buffer_append_cstr(transport_buffer *buffer, const char *value) {
  return buffer_append(buffer, value, value == NULL ? 0 : strlen(value));
}

static void buffer_dispose(transport_buffer *buffer) {
  if (buffer != NULL) {
    free(buffer->bytes);
    buffer->bytes = NULL;
    buffer->length = 0;
    buffer->capacity = 0;
  }
}

static int32_t copy_output(const void *bytes, size_t length, uint8_t *output,
                           intptr_t output_capacity,
                           intptr_t *required_capacity) {
  if (required_capacity == NULL || output_capacity < 0) {
    return SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT;
  }
  if (length > (size_t)INTPTR_MAX) {
    return SKILLS_WORKSPACE_TRANSPORT_LIMIT_EXCEEDED;
  }
  *required_capacity = (intptr_t)length;
  if ((size_t)output_capacity < length) {
    return SKILLS_WORKSPACE_TRANSPORT_BUFFER_TOO_SMALL;
  }
  if (length > 0) {
    if (output == NULL || bytes == NULL) {
      return SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT;
    }
    memcpy(output, bytes, length);
  }
  return SKILLS_WORKSPACE_TRANSPORT_OK;
}

static int is_empty(const char *value) {
  return value == NULL || value[0] == '\0';
}

// Classifies a failed fetch from libgit2's error code and class only.
static int32_t classify_fetch_failure(int code,
                                      const fetch_context *context) {
  const git_error *error = git_error_last();
  int error_class = error == NULL ? GIT_ERROR_NONE : error->klass;

  if (code == GIT_EUSER || is_cancelled(context)) {
    return SKILLS_WORKSPACE_TRANSPORT_CANCELLED;
  }
  if (code == GIT_EAUTH) {
    return SKILLS_WORKSPACE_TRANSPORT_AUTHENTICATION_REQUIRED;
  }
  if (code == GIT_ECERTIFICATE) {
    return SKILLS_WORKSPACE_TRANSPORT_CERTIFICATE_FAILURE;
  }
  if (code == GIT_TIMEOUT) {
    return SKILLS_WORKSPACE_TRANSPORT_TIMED_OUT;
  }
  if (code == GIT_ENOTFOUND && error_class == GIT_ERROR_REFERENCE) {
    return SKILLS_WORKSPACE_TRANSPORT_REF_NOT_FOUND;
  }
  if (error_class == GIT_ERROR_SSL) {
    return SKILLS_WORKSPACE_TRANSPORT_TLS_FAILURE;
  }
  if (error_class == GIT_ERROR_INVALID || code == GIT_EINVALIDSPEC) {
    return SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT;
  }
  return SKILLS_WORKSPACE_TRANSPORT_NETWORK_FAILURE;
}

static int fetch_sideband(const char *text, int length, void *payload) {
  (void)text;
  (void)length;
  return is_cancelled((const fetch_context *)payload) ? GIT_EUSER : 0;
}

static int fetch_transfer(const git_indexer_progress *stats, void *payload) {
  (void)stats;
  return is_cancelled((const fetch_context *)payload) ? GIT_EUSER : 0;
}

static int fetch_ready(git_remote *remote, int direction, void *payload) {
  (void)remote;
  (void)direction;
  return is_cancelled((const fetch_context *)payload) ? GIT_EUSER : 0;
}

static int fetch_update_refs(const char *refname, const git_oid *a,
                             const git_oid *b, git_refspec *spec,
                             void *payload) {
  (void)refname;
  (void)a;
  (void)b;
  (void)spec;
  return is_cancelled((const fetch_context *)payload) ? GIT_EUSER : 0;
}

// Public Sources are anonymous. Explicitly refuse credential acquisition so
// every backend returns GIT_EAUTH instead of attempting default credentials
// or reporting an unhandled HTTP 401 as a generic network failure (WinHTTP).
// Third-party authentication remains delegated to the system Git transport.
static int refuse_source_credentials(git_credential **out, const char *url,
                                      const char *username_from_url,
                                      unsigned int allowed_types,
                                      void *payload) {
  (void)url;
  (void)username_from_url;
  (void)allowed_types;
  *out = NULL;
  return is_cancelled((const fetch_context *)payload) ? GIT_EUSER : GIT_EAUTH;
}

static int remember_fetch_head(const char *ref_name, const char *remote_url,
                               const git_oid *oid, unsigned int is_merge,
                               void *payload) {
  fetch_head_context *context = (fetch_head_context *)payload;

  (void)ref_name;
  (void)remote_url;
  (void)is_merge;
  if (context == NULL || oid == NULL) {
    return -1;
  }
  git_oid_cpy(&context->oid, oid);
  context->found = 1;
  return 1;
}

static int32_t resolve_fetched_commit(git_repository *repository,
                                      const char *ref, git_oid *commit_oid) {
  fetch_head_context head;
  git_object *object = NULL;
  git_object *commit = NULL;

  memset(&head, 0, sizeof(head));
  // The callback stops after the first record; a missing FETCH_HEAD simply
  // leaves `found` unset.
  (void)git_repository_fetchhead_foreach(repository, remember_fetch_head,
                                         &head);
  if (!head.found) {
    // A commit object ID that was fetched directly may be absent from
    // FETCH_HEAD; accept it only when the object itself arrived.
    if (ref == NULL || git_oid_fromstr(&head.oid, ref) != 0) {
      return SKILLS_WORKSPACE_TRANSPORT_REF_NOT_FOUND;
    }
  }
  if (git_object_lookup(&object, repository, &head.oid, GIT_OBJECT_ANY) < 0) {
    return SKILLS_WORKSPACE_TRANSPORT_REF_NOT_FOUND;
  }
  if (git_object_peel(&commit, object, GIT_OBJECT_COMMIT) < 0) {
    git_object_free(object);
    return SKILLS_WORKSPACE_TRANSPORT_REF_NOT_FOUND;
  }
  git_oid_cpy(commit_oid, git_object_id(commit));
  git_object_free(commit);
  git_object_free(object);
  return SKILLS_WORKSPACE_TRANSPORT_OK;
}

static int32_t transport_fetch(const char *repository_path,
                               const char *url, const char *ref,
                               int32_t proxy_mode, const char *proxy_url,
                               const int32_t *cancel_flag, char *oid_hex,
                               intptr_t oid_hex_capacity) {
  git_repository_init_options init = GIT_REPOSITORY_INIT_OPTIONS_INIT;
  git_fetch_options options = GIT_FETCH_OPTIONS_INIT;
  git_repository *repository = NULL;
  git_remote *remote = NULL;
  fetch_context context;
  git_oid commit_oid;
  char *refspec_values[1];
  git_strarray refspecs;
  int code;
  int32_t result;

  if (is_empty(repository_path) || is_empty(url) || oid_hex == NULL ||
      (ref != NULL && ref[0] == '\0')) {
    return SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT;
  }
  if (proxy_mode != SKILLS_WORKSPACE_TRANSPORT_PROXY_NONE &&
      proxy_mode != SKILLS_WORKSPACE_TRANSPORT_PROXY_ENVIRONMENT &&
      proxy_mode != SKILLS_WORKSPACE_TRANSPORT_PROXY_SPECIFIED) {
    return SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT;
  }
  if ((proxy_mode == SKILLS_WORKSPACE_TRANSPORT_PROXY_SPECIFIED) ==
      is_empty(proxy_url)) {
    return SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT;
  }
  if (oid_hex_capacity < GIT_OID_SHA1_HEXSIZE + 1) {
    return SKILLS_WORKSPACE_TRANSPORT_BUFFER_TOO_SMALL;
  }
  context.cancel_flag = cancel_flag;
  if (is_cancelled(&context)) {
    return SKILLS_WORKSPACE_TRANSPORT_CANCELLED;
  }

  init.flags = GIT_REPOSITORY_INIT_BARE | GIT_REPOSITORY_INIT_NO_REINIT |
               GIT_REPOSITORY_INIT_MKPATH;
  if (git_repository_init_ext(&repository, repository_path, &init) < 0) {
    return SKILLS_WORKSPACE_TRANSPORT_REPOSITORY_FAILURE;
  }
  if (git_remote_create_anonymous(&remote, repository, url) < 0) {
    git_repository_free(repository);
    return SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT;
  }

  options.depth = 1;
  options.download_tags = GIT_REMOTE_DOWNLOAD_TAGS_NONE;
  options.follow_redirects = GIT_REMOTE_REDIRECT_INITIAL;
  options.update_fetchhead = 1;
  options.prune = GIT_FETCH_NO_PRUNE;
  options.callbacks.sideband_progress = fetch_sideband;
  options.callbacks.transfer_progress = fetch_transfer;
  options.callbacks.remote_ready = fetch_ready;
  options.callbacks.update_refs = fetch_update_refs;
  options.callbacks.credentials = refuse_source_credentials;
  options.callbacks.payload = &context;
  switch (proxy_mode) {
    case SKILLS_WORKSPACE_TRANSPORT_PROXY_ENVIRONMENT:
      options.proxy_opts.type = GIT_PROXY_AUTO;
      break;
    case SKILLS_WORKSPACE_TRANSPORT_PROXY_SPECIFIED:
      options.proxy_opts.type = GIT_PROXY_SPECIFIED;
      options.proxy_opts.url = proxy_url;
      break;
    default:
      options.proxy_opts.type = GIT_PROXY_NONE;
      break;
  }

  refspec_values[0] = (char *)(ref == NULL ? "HEAD" : ref);
  refspecs.strings = refspec_values;
  refspecs.count = 1;
  code = git_remote_fetch(remote, &refspecs, &options, NULL);
  if (code < 0) {
    result = classify_fetch_failure(code, &context);
  } else if (is_cancelled(&context)) {
    result = SKILLS_WORKSPACE_TRANSPORT_CANCELLED;
  } else {
    result = resolve_fetched_commit(repository, ref, &commit_oid);
    if (result == SKILLS_WORKSPACE_TRANSPORT_OK &&
        git_oid_tostr(oid_hex, (size_t)oid_hex_capacity, &commit_oid) ==
            NULL) {
      result = SKILLS_WORKSPACE_TRANSPORT_OBJECT_FAILURE;
    }
  }
  git_remote_free(remote);
  git_repository_free(repository);
  return result;
}

static int32_t open_repository(git_repository **repository,
                               const char *repository_path) {
  if (is_empty(repository_path)) {
    return SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT;
  }
  if (git_repository_open_bare(repository, repository_path) < 0) {
    return SKILLS_WORKSPACE_TRANSPORT_REPOSITORY_FAILURE;
  }
  return SKILLS_WORKSPACE_TRANSPORT_OK;
}

static int append_tree_record(tree_list_context *context, const char *root,
                              const git_tree_entry *entry) {
  char metadata[96];
  char oid_hex[GIT_OID_MAX_HEXSIZE + 1];
  const char *type = git_object_type2string(git_tree_entry_type(entry));
  int length;

  if (git_oid_tostr(oid_hex, sizeof(oid_hex), git_tree_entry_id(entry)) ==
      NULL) {
    return -1;
  }
  length = snprintf(metadata, sizeof(metadata), "%06o %s %s\t",
                    (unsigned int)git_tree_entry_filemode(entry),
                    type == NULL ? "unknown" : type, oid_hex);
  if (length < 0 || (size_t)length >= sizeof(metadata)) {
    return -1;
  }
  if (buffer_append(&context->output, metadata, (size_t)length) < 0 ||
      buffer_append_cstr(&context->output, context->prefix) < 0 ||
      buffer_append_cstr(&context->output, root) < 0 ||
      buffer_append_cstr(&context->output, git_tree_entry_name(entry)) < 0 ||
      buffer_append(&context->output, "", 1) < 0) {
    return -1;
  }
  return 0;
}

static int tree_list_callback(const char *root, const git_tree_entry *entry,
                              void *payload) {
  tree_list_context *context = (tree_list_context *)payload;

  if (context == NULL || entry == NULL) {
    return -1;
  }
  if (git_tree_entry_type(entry) == GIT_OBJECT_TREE) {
    return 0;
  }
  if (append_tree_record(context, root, entry) < 0) {
    context->failed = 1;
    return -1;
  }
  return 0;
}

static int32_t transport_tree_list(
    const char *repository_path, const char *commit_oid_hex,
    const char *subpath, uint8_t *output, intptr_t output_capacity,
    intptr_t *required_capacity) {
  git_repository *repository = NULL;
  git_commit *commit = NULL;
  git_tree *root = NULL;
  git_tree *selected = NULL;
  git_tree_entry *entry = NULL;
  tree_list_context context;
  git_oid commit_oid;
  char *prefix = NULL;
  int32_t result;

  if (commit_oid_hex == NULL || subpath == NULL || required_capacity == NULL ||
      git_oid_fromstr(&commit_oid, commit_oid_hex) != 0) {
    return SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT;
  }
  result = open_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_TRANSPORT_OK) {
    return result;
  }
  memset(&context, 0, sizeof(context));
  context.prefix = "";
  if (git_commit_lookup(&commit, repository, &commit_oid) < 0 ||
      git_commit_tree(&root, commit) < 0) {
    result = SKILLS_WORKSPACE_TRANSPORT_OBJECT_FAILURE;
    goto cleanup;
  }
  if (subpath[0] == '\0') {
    selected = root;
  } else {
    int lookup = git_tree_entry_bypath(&entry, root, subpath);
    if (lookup == GIT_ENOTFOUND) {
      // Like `git ls-tree`, a missing selection lists nothing.
      result = copy_output(NULL, 0, output, output_capacity,
                           required_capacity);
      goto cleanup;
    }
    if (lookup < 0) {
      result = SKILLS_WORKSPACE_TRANSPORT_OBJECT_FAILURE;
      goto cleanup;
    }
    if (git_tree_entry_type(entry) != GIT_OBJECT_TREE) {
      // A non-tree selection is reported as itself so the caller can reject
      // it as outside the selection.
      const char *slash = strrchr(subpath, '/');
      size_t parent_length = slash == NULL ? 0 : (size_t)(slash - subpath) + 1;
      prefix = (char *)malloc(parent_length + 1);
      if (prefix == NULL) {
        result = SKILLS_WORKSPACE_TRANSPORT_OBJECT_FAILURE;
        goto cleanup;
      }
      memcpy(prefix, subpath, parent_length);
      prefix[parent_length] = '\0';
      context.prefix = prefix;
      result = append_tree_record(&context, "", entry) < 0
                   ? SKILLS_WORKSPACE_TRANSPORT_OBJECT_FAILURE
                   : copy_output(context.output.bytes, context.output.length,
                                 output, output_capacity, required_capacity);
      goto cleanup;
    }
    if (git_tree_lookup(&selected, repository, git_tree_entry_id(entry)) <
        0) {
      result = SKILLS_WORKSPACE_TRANSPORT_OBJECT_FAILURE;
      goto cleanup;
    }
    prefix = (char *)malloc(strlen(subpath) + 2);
    if (prefix == NULL) {
      result = SKILLS_WORKSPACE_TRANSPORT_OBJECT_FAILURE;
      goto cleanup;
    }
    snprintf(prefix, strlen(subpath) + 2, "%s/", subpath);
    context.prefix = prefix;
  }
  if (git_tree_walk(selected, GIT_TREEWALK_PRE, tree_list_callback,
                    &context) < 0 ||
      context.failed) {
    result = SKILLS_WORKSPACE_TRANSPORT_OBJECT_FAILURE;
  } else {
    result = copy_output(context.output.bytes, context.output.length, output,
                         output_capacity, required_capacity);
  }

cleanup:
  if (selected != root) {
    git_tree_free(selected);
  }
  git_tree_entry_free(entry);
  git_tree_free(root);
  git_commit_free(commit);
  git_repository_free(repository);
  buffer_dispose(&context.output);
  free(prefix);
  return result;
}

static int32_t transport_blob_read(
    const char *repository_path, const char *blob_oid_hex,
    int64_t maximum_bytes, uint8_t *output, intptr_t output_capacity,
    intptr_t *required_capacity) {
  git_repository *repository = NULL;
  git_blob *blob = NULL;
  git_oid blob_oid;
  git_object_size_t size;
  int32_t result;

  if (blob_oid_hex == NULL || required_capacity == NULL || maximum_bytes < 0 ||
      git_oid_fromstr(&blob_oid, blob_oid_hex) != 0) {
    return SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT;
  }
  result = open_repository(&repository, repository_path);
  if (result != SKILLS_WORKSPACE_TRANSPORT_OK) {
    return result;
  }
  if (git_blob_lookup(&blob, repository, &blob_oid) < 0) {
    result = SKILLS_WORKSPACE_TRANSPORT_OBJECT_FAILURE;
  } else {
    size = git_blob_rawsize(blob);
    if (size > (git_object_size_t)maximum_bytes || size > (size_t)SIZE_MAX) {
      result = SKILLS_WORKSPACE_TRANSPORT_LIMIT_EXCEEDED;
    } else {
      result = copy_output(git_blob_rawcontent(blob), (size_t)size, output,
                           output_capacity, required_capacity);
    }
  }
  git_blob_free(blob);
  git_repository_free(repository);
  return result;
}

// Keep a runtime reference across every path, including validation failures
// and output sizing probes. None of the implementations retain native objects
// after returning, so the lease can be released before crossing the ABI.
int32_t skills_workspace_transport_fetch(
    const char *repository_path, const char *url, const char *ref,
    int32_t proxy_mode, const char *proxy_url, const int32_t *cancel_flag,
    char *oid_hex, intptr_t oid_hex_capacity) {
  int32_t result;
  if (skills_workspace_runtime_acquire() != 0) {
    return SKILLS_WORKSPACE_TRANSPORT_RUNTIME_FAILURE;
  }
  result = transport_fetch(repository_path, url, ref, proxy_mode, proxy_url,
                           cancel_flag, oid_hex, oid_hex_capacity);
  skills_workspace_runtime_release();
  return result;
}

int32_t skills_workspace_transport_tree_list(
    const char *repository_path, const char *commit_oid_hex,
    const char *subpath, uint8_t *output, intptr_t output_capacity,
    intptr_t *required_capacity) {
  int32_t result;
  if (skills_workspace_runtime_acquire() != 0) {
    return SKILLS_WORKSPACE_TRANSPORT_RUNTIME_FAILURE;
  }
  result = transport_tree_list(repository_path, commit_oid_hex, subpath, output,
                               output_capacity, required_capacity);
  skills_workspace_runtime_release();
  return result;
}

int32_t skills_workspace_transport_blob_read(
    const char *repository_path, const char *blob_oid_hex,
    int64_t maximum_bytes, uint8_t *output, intptr_t output_capacity,
    intptr_t *required_capacity) {
  int32_t result;
  if (skills_workspace_runtime_acquire() != 0) {
    return SKILLS_WORKSPACE_TRANSPORT_RUNTIME_FAILURE;
  }
  result = transport_blob_read(repository_path, blob_oid_hex, maximum_bytes,
                               output, output_capacity, required_capacity);
  skills_workspace_runtime_release();
  return result;
}

#if defined(_WIN32)
static int append_wide_utf8(transport_buffer *buffer, const wchar_t *value) {
  int length;
  char *converted;
  int result;

  if (value == NULL || value[0] == L'\0') {
    return 0;
  }
  length = WideCharToMultiByte(CP_UTF8, 0, value, -1, NULL, 0, NULL, NULL);
  if (length <= 1) {
    return length == 1 ? 0 : -1;
  }
  converted = (char *)malloc((size_t)length);
  if (converted == NULL) {
    return -1;
  }
  if (WideCharToMultiByte(CP_UTF8, 0, value, -1, converted, length, NULL,
                          NULL) != length) {
    free(converted);
    return -1;
  }
  result = buffer_append(buffer, converted, (size_t)length - 1);
  free(converted);
  return result;
}

int32_t skills_workspace_transport_windows_proxy(uint8_t *output,
                                                 intptr_t output_capacity,
                                                 intptr_t *required_capacity) {
  WINHTTP_CURRENT_USER_IE_PROXY_CONFIG config;
  transport_buffer buffer;
  int32_t result;

  if (required_capacity == NULL) {
    return SKILLS_WORKSPACE_TRANSPORT_INVALID_ARGUMENT;
  }
  memset(&config, 0, sizeof(config));
  memset(&buffer, 0, sizeof(buffer));
  if (!WinHttpGetIEProxyConfigForCurrentUser(&config)) {
    return SKILLS_WORKSPACE_TRANSPORT_RUNTIME_FAILURE;
  }
  if (append_wide_utf8(&buffer, config.lpszProxy) < 0 ||
      buffer_append(&buffer, "\t", 1) < 0 ||
      append_wide_utf8(&buffer, config.lpszProxyBypass) < 0 ||
      buffer_append(&buffer, "\t", 1) < 0 ||
      buffer_append(&buffer,
                    (config.fAutoDetect || config.lpszAutoConfigUrl != NULL)
                        ? "1"
                        : "0",
                    1) < 0) {
    result = SKILLS_WORKSPACE_TRANSPORT_RUNTIME_FAILURE;
  } else {
    result = copy_output(buffer.bytes, buffer.length, output, output_capacity,
                         required_capacity);
  }
  if (config.lpszProxy != NULL) GlobalFree(config.lpszProxy);
  if (config.lpszProxyBypass != NULL) GlobalFree(config.lpszProxyBypass);
  if (config.lpszAutoConfigUrl != NULL) GlobalFree(config.lpszAutoConfigUrl);
  buffer_dispose(&buffer);
  return result;
}
#else
int32_t skills_workspace_transport_windows_proxy(uint8_t *output,
                                                 intptr_t output_capacity,
                                                 intptr_t *required_capacity) {
  (void)output;
  (void)output_capacity;
  (void)required_capacity;
  return SKILLS_WORKSPACE_TRANSPORT_UNSUPPORTED;
}
#endif
