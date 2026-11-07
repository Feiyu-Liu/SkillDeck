#include "skills_workspace_native.h"

#if defined(_WIN32)

#define SKILLS_WORKSPACE_WINDOWS_ERROR_NOT_SUPPORTED 50

int32_t skills_workspace_posix_write_new_at(const char *parent_path,
                                             const char *entry_name,
                                             const uint8_t *bytes,
                                             intptr_t byte_count) {
  (void)parent_path;
  (void)entry_name;
  (void)bytes;
  (void)byte_count;
  return SKILLS_WORKSPACE_WINDOWS_ERROR_NOT_SUPPORTED;
}

int32_t skills_workspace_posix_flush_path(const char *path,
                                          int32_t directory) {
  (void)path;
  (void)directory;
  return SKILLS_WORKSPACE_WINDOWS_ERROR_NOT_SUPPORTED;
}

int32_t skills_workspace_posix_flush_at(const char *parent_path,
                                        const char *entry_name,
                                        int32_t directory) {
  (void)parent_path;
  (void)entry_name;
  (void)directory;
  return SKILLS_WORKSPACE_WINDOWS_ERROR_NOT_SUPPORTED;
}

int32_t skills_workspace_posix_stat(const char *path, int32_t follow_links,
                                    uint64_t *device, uint64_t *inode,
                                    uint32_t *mode, int32_t *kind) {
  (void)path;
  (void)follow_links;
  (void)device;
  (void)inode;
  (void)mode;
  (void)kind;
  return SKILLS_WORKSPACE_WINDOWS_ERROR_NOT_SUPPORTED;
}

int32_t skills_workspace_posix_chmod(const char *path, uint32_t mode) {
  (void)path;
  (void)mode;
  return SKILLS_WORKSPACE_WINDOWS_ERROR_NOT_SUPPORTED;
}

int32_t skills_workspace_posix_rename_at(const char *parent_path,
                                         const char *old_name,
                                         const char *new_name) {
  (void)parent_path;
  (void)old_name;
  (void)new_name;
  return SKILLS_WORKSPACE_WINDOWS_ERROR_NOT_SUPPORTED;
}

int32_t skills_workspace_posix_exchange_at(const char *parent_path,
                                           const char *first_name,
                                           const char *second_name) {
  (void)parent_path;
  (void)first_name;
  (void)second_name;
  return SKILLS_WORKSPACE_WINDOWS_ERROR_NOT_SUPPORTED;
}

#else

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

#if defined(__linux__)
#include <sys/syscall.h>
#endif

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif

#ifndef O_DIRECTORY
#define O_DIRECTORY 0
#endif

#ifndef O_NOFOLLOW
#define O_NOFOLLOW 0
#endif

static int32_t close_preserving_error(int descriptor, int32_t result) {
  if (close(descriptor) != 0 && result == 0) {
    return (int32_t)errno;
  }
  return result;
}

static int32_t flush_descriptor(int descriptor) {
  int32_t result = 0;
  if (fsync(descriptor) != 0) {
    result = (int32_t)errno;
  }
  return close_preserving_error(descriptor, result);
}

int32_t skills_workspace_posix_write_new_at(const char *parent_path,
                                             const char *entry_name,
                                             const uint8_t *bytes,
                                             intptr_t byte_count) {
  int parent_descriptor;
  int file_descriptor;
  intptr_t offset = 0;
  int32_t result = 0;
  if (parent_path == NULL || parent_path[0] == '\0' || entry_name == NULL ||
      entry_name[0] == '\0' || byte_count < 0 ||
      (byte_count > 0 && bytes == NULL)) {
    return EINVAL;
  }
  parent_descriptor =
      open(parent_path, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW);
  if (parent_descriptor < 0) {
    return (int32_t)errno;
  }
  file_descriptor = openat(parent_descriptor, entry_name,
                           O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC |
                               O_NOFOLLOW,
                           S_IRUSR | S_IWUSR);
  if (file_descriptor < 0) {
    result = (int32_t)errno;
    return close_preserving_error(parent_descriptor, result);
  }
  while (offset < byte_count) {
    ssize_t written =
        write(file_descriptor, bytes + offset, (size_t)(byte_count - offset));
    if (written < 0 && errno == EINTR) {
      continue;
    }
    if (written <= 0) {
      result = written == 0 ? EIO : (int32_t)errno;
      break;
    }
    offset += (intptr_t)written;
  }
  result = close_preserving_error(file_descriptor, result);
  return close_preserving_error(parent_descriptor, result);
}

int32_t skills_workspace_posix_flush_path(const char *path,
                                          int32_t directory) {
  int descriptor;
  int flags;
  if (path == NULL || path[0] == '\0') {
    return EINVAL;
  }
  flags = O_RDONLY | O_CLOEXEC;
  if (directory != 0) {
    flags |= O_DIRECTORY;
  }
  descriptor = open(path, flags);
  if (descriptor < 0) {
    return (int32_t)errno;
  }
  return flush_descriptor(descriptor);
}

int32_t skills_workspace_posix_flush_at(const char *parent_path,
                                        const char *entry_name,
                                        int32_t directory) {
  int parent_descriptor;
  int entry_descriptor;
  int flags;
  int32_t result;
  if (parent_path == NULL || parent_path[0] == '\0' || entry_name == NULL ||
      entry_name[0] == '\0') {
    return EINVAL;
  }
  parent_descriptor = open(parent_path, O_RDONLY | O_CLOEXEC | O_DIRECTORY);
  if (parent_descriptor < 0) {
    return (int32_t)errno;
  }
  flags = O_RDONLY | O_CLOEXEC;
  if (directory != 0) {
    flags |= O_DIRECTORY;
  }
  entry_descriptor = openat(parent_descriptor, entry_name, flags);
  if (entry_descriptor < 0) {
    result = (int32_t)errno;
    return close_preserving_error(parent_descriptor, result);
  }
  result = flush_descriptor(entry_descriptor);
  return close_preserving_error(parent_descriptor, result);
}

int32_t skills_workspace_posix_stat(const char *path, int32_t follow_links,
                                    uint64_t *device, uint64_t *inode,
                                    uint32_t *mode, int32_t *kind) {
  struct stat information;
  int result;
  if (path == NULL || path[0] == '\0' || device == NULL || inode == NULL ||
      mode == NULL || kind == NULL) {
    return EINVAL;
  }
  result = follow_links != 0 ? stat(path, &information)
                             : lstat(path, &information);
  if (result != 0) {
    return (int32_t)errno;
  }
  *device = (uint64_t)information.st_dev;
  *inode = (uint64_t)information.st_ino;
  *mode = (uint32_t)information.st_mode;
  if (S_ISREG(information.st_mode)) {
    *kind = SKILLS_WORKSPACE_FILESYSTEM_FILE;
  } else if (S_ISDIR(information.st_mode)) {
    *kind = SKILLS_WORKSPACE_FILESYSTEM_DIRECTORY;
  } else if (S_ISLNK(information.st_mode)) {
    *kind = SKILLS_WORKSPACE_FILESYSTEM_SYMBOLIC_LINK;
  } else {
    *kind = SKILLS_WORKSPACE_FILESYSTEM_OTHER;
  }
  return 0;
}

int32_t skills_workspace_posix_chmod(const char *path, uint32_t mode) {
  if (path == NULL || path[0] == '\0') {
    return EINVAL;
  }
  if (chmod(path, (mode_t)mode) != 0) {
    return (int32_t)errno;
  }
  return 0;
}

static int32_t open_parent(const char *parent_path) {
  if (parent_path == NULL || parent_path[0] == '\0') {
    errno = EINVAL;
    return -1;
  }
  return open(parent_path, O_RDONLY | O_CLOEXEC | O_DIRECTORY);
}

int32_t skills_workspace_posix_rename_at(const char *parent_path,
                                         const char *old_name,
                                         const char *new_name) {
  int descriptor;
  int32_t result = 0;
  if (old_name == NULL || old_name[0] == '\0' || new_name == NULL ||
      new_name[0] == '\0') {
    return EINVAL;
  }
  descriptor = open_parent(parent_path);
  if (descriptor < 0) {
    return (int32_t)errno;
  }
  if (renameat(descriptor, old_name, descriptor, new_name) != 0) {
    result = (int32_t)errno;
  }
  return close_preserving_error(descriptor, result);
}

int32_t skills_workspace_posix_exchange_at(const char *parent_path,
                                           const char *first_name,
                                           const char *second_name) {
  int descriptor;
  int result;
  int32_t error = 0;
  if (first_name == NULL || first_name[0] == '\0' || second_name == NULL ||
      second_name[0] == '\0') {
    return EINVAL;
  }
  descriptor = open_parent(parent_path);
  if (descriptor < 0) {
    return (int32_t)errno;
  }
#if defined(__APPLE__)
  result = renameatx_np(descriptor, first_name, descriptor, second_name,
                        RENAME_SWAP);
#elif defined(__linux__) && defined(SYS_renameat2)
  result = (int)syscall(SYS_renameat2, descriptor, first_name, descriptor,
                        second_name, 0x2);
#else
  result = -1;
  errno = ENOTSUP;
#endif
  if (result != 0) {
    error = (int32_t)errno;
  }
  return close_preserving_error(descriptor, error);
}

#endif

int32_t skills_workspace_native_ping(void) { return 0x5357; }
