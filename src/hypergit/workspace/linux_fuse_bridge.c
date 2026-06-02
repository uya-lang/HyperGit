#define _GNU_SOURCE 1

#include <errno.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/types.h>
#include <unistd.h>

struct fuse;
struct fuse_session;
struct fuse_conn_info;
struct fuse_config;

enum fuse_readdir_flags {
  FUSE_READDIR_DEFAULTS = 0,
  FUSE_READDIR_PLUS = 1
};

enum fuse_fill_dir_flags {
  FUSE_FILL_DIR_DEFAULTS = 0,
  FUSE_FILL_DIR_PLUS = 1
};

typedef int (*fuse_fill_dir_t)(void *buf, const char *name, const struct stat *stbuf, off_t off, enum fuse_fill_dir_flags flags);

struct fuse_args {
  int argc;
  char **argv;
  int allocated;
};

struct fuse_file_info {
  int32_t flags;
  uint32_t writepage : 1;
  uint32_t direct_io : 1;
  uint32_t keep_cache : 1;
  uint32_t flush : 1;
  uint32_t nonseekable : 1;
  uint32_t flock_release : 1;
  uint32_t cache_readdir : 1;
  uint32_t noflush : 1;
  uint32_t parallel_direct_writes : 1;
  uint32_t padding : 23;
  uint32_t padding2 : 32;
  uint32_t padding3 : 32;
  uint64_t fh;
  uint64_t lock_owner;
  uint32_t poll_events;
  int32_t backing_id;
  uint64_t compat_flags;
  uint64_t reserved[2];
};

struct fuse_context {
  struct fuse *fuse;
  uid_t uid;
  gid_t gid;
  pid_t pid;
  void *private_data;
  mode_t umask;
};

struct fuse_operations {
  int (*getattr)(const char *, struct stat *, struct fuse_file_info *fi);
  int (*readlink)(const char *, char *, size_t);
  int (*mknod)(const char *, mode_t, dev_t);
  int (*mkdir)(const char *, mode_t);
  int (*unlink)(const char *);
  int (*rmdir)(const char *);
  int (*symlink)(const char *, const char *);
  int (*rename)(const char *, const char *, unsigned int flags);
  int (*link)(const char *, const char *);
  int (*chmod)(const char *, mode_t, struct fuse_file_info *fi);
  int (*chown)(const char *, uid_t, gid_t, struct fuse_file_info *fi);
  int (*truncate)(const char *, off_t, struct fuse_file_info *fi);
  int (*open)(const char *, struct fuse_file_info *);
  int (*read)(const char *, char *, size_t, off_t, struct fuse_file_info *);
  int (*write)(const char *, const char *, size_t, off_t, struct fuse_file_info *);
  int (*statfs)(const char *, struct statvfs *);
  int (*flush)(const char *, struct fuse_file_info *);
  int (*release)(const char *, struct fuse_file_info *);
  int (*fsync)(const char *, int, struct fuse_file_info *);
  int (*setxattr)(const char *, const char *, const char *, size_t, int);
  int (*getxattr)(const char *, const char *, char *, size_t);
  int (*listxattr)(const char *, char *, size_t);
  int (*removexattr)(const char *, const char *);
  int (*opendir)(const char *, struct fuse_file_info *);
  int (*readdir)(const char *, void *, fuse_fill_dir_t, off_t, struct fuse_file_info *, enum fuse_readdir_flags);
  int (*releasedir)(const char *, struct fuse_file_info *);
  int (*fsyncdir)(const char *, int, struct fuse_file_info *);
  void *(*init)(struct fuse_conn_info *, struct fuse_config *);
  void (*destroy)(void *private_data);
};

typedef struct fuse *(*hypergit_linux_fuse_new_fn)(struct fuse_args *args, const struct fuse_operations *op, size_t op_size, void *private_data);
typedef struct fuse_session *(*hypergit_linux_fuse_get_session_fn)(struct fuse *fuse);
typedef int (*hypergit_linux_fuse_session_mount_fn)(struct fuse_session *session, const char *mountpoint);
typedef void (*hypergit_linux_fuse_session_unmount_fn)(struct fuse_session *session);
typedef int (*hypergit_linux_fuse_session_loop_fn)(struct fuse_session *session);
typedef void (*hypergit_linux_fuse_session_exit_fn)(struct fuse_session *session);
typedef void (*hypergit_linux_fuse_destroy_fn)(struct fuse *fuse);
typedef struct fuse_context *(*hypergit_linux_fuse_get_context_fn)(void);

struct hypergit_linux_fuse_api {
  void *library_handle;
  hypergit_linux_fuse_new_fn fuse_new;
  hypergit_linux_fuse_get_session_fn fuse_get_session;
  hypergit_linux_fuse_session_mount_fn fuse_session_mount;
  hypergit_linux_fuse_session_unmount_fn fuse_session_unmount;
  hypergit_linux_fuse_session_loop_fn fuse_session_loop;
  hypergit_linux_fuse_session_exit_fn fuse_session_exit;
  hypergit_linux_fuse_destroy_fn fuse_destroy;
  hypergit_linux_fuse_get_context_fn fuse_get_context;
};

enum hypergit_linux_fuse_placeholder_state {
  HYPERGIT_LINUX_FUSE_PLACEHOLDER_VIRTUAL_ONLY = 0,
  HYPERGIT_LINUX_FUSE_PLACEHOLDER_MATERIALIZED = 1,
  HYPERGIT_LINUX_FUSE_PLACEHOLDER_DIRTY_MATERIALIZED = 2
};

struct hypergit_linux_fuse_byte_list {
  const unsigned char *ptr;
  size_t len;
};

struct hypergit_linux_fuse_entry {
  struct hypergit_linux_fuse_byte_list path;
  struct hypergit_linux_fuse_byte_list backing_path;
  uint32_t mode;
  uint64_t logical_size;
  int32_t placeholder_state;
};

struct hypergit_linux_fuse_entry_list {
  struct hypergit_linux_fuse_entry *ptr;
  size_t len;
};

struct hypergit_linux_fuse_snapshot {
  struct hypergit_linux_fuse_byte_list repo_root;
  struct hypergit_linux_fuse_entry_list entries;
};

struct hypergit_linux_fuse_entry_runtime {
  char *path;
  size_t path_len;
  char *backing_path;
  size_t backing_path_len;
  uint32_t mode;
  uint64_t logical_size;
  int32_t placeholder_state;
};

struct hypergit_linux_fuse_mount_handle {
  struct fuse *fuse;
  struct fuse_session *session;
  pthread_t thread;
  int thread_started;
  int thread_joined;
  int mounted;
  int stop_requested;
  int loop_result;
  char *mountpoint;
  struct hypergit_linux_fuse_entry_runtime *entries;
  size_t entry_count;
};

static struct hypergit_linux_fuse_api hypergit_linux_fuse_api_state = {0};
static int hypergit_linux_fuse_api_ready = 0;

#define HYPERGIT_LINUX_FUSE_INVALID_FH UINT64_MAX

static int hypergit_linux_fuse_load_api(void) {
  static const char *const candidates[] = {
    "libfuse3.so.3",
    "libfuse3.so",
    NULL
  };
  void *library_handle = NULL;
  size_t i = 0;
  if (hypergit_linux_fuse_api_ready) {
    return 0;
  }
  while (candidates[i] != NULL) {
    library_handle = dlopen(candidates[i], RTLD_NOW | RTLD_LOCAL);
    if (library_handle != NULL) {
      break;
    }
    i += 1;
  }
  if (library_handle == NULL) {
    return -ENOENT;
  }

  hypergit_linux_fuse_api_state.library_handle = library_handle;
  hypergit_linux_fuse_api_state.fuse_new = (hypergit_linux_fuse_new_fn)dlsym(library_handle, "fuse_new");
  if (hypergit_linux_fuse_api_state.fuse_new == NULL) {
    hypergit_linux_fuse_api_state.fuse_new = (hypergit_linux_fuse_new_fn)dlsym(library_handle, "fuse_new_31");
  }
  if (hypergit_linux_fuse_api_state.fuse_new == NULL) {
    hypergit_linux_fuse_api_state.fuse_new = (hypergit_linux_fuse_new_fn)dlsym(library_handle, "fuse_new_30");
  }
  hypergit_linux_fuse_api_state.fuse_session_mount = (hypergit_linux_fuse_session_mount_fn)dlsym(library_handle, "fuse_session_mount");
  hypergit_linux_fuse_api_state.fuse_session_unmount = (hypergit_linux_fuse_session_unmount_fn)dlsym(library_handle, "fuse_session_unmount");
  hypergit_linux_fuse_api_state.fuse_session_loop = (hypergit_linux_fuse_session_loop_fn)dlsym(library_handle, "fuse_session_loop");
  hypergit_linux_fuse_api_state.fuse_session_exit = (hypergit_linux_fuse_session_exit_fn)dlsym(library_handle, "fuse_session_exit");
  hypergit_linux_fuse_api_state.fuse_destroy = (hypergit_linux_fuse_destroy_fn)dlsym(library_handle, "fuse_destroy");
  hypergit_linux_fuse_api_state.fuse_get_session = (hypergit_linux_fuse_get_session_fn)dlsym(library_handle, "fuse_get_session");
  hypergit_linux_fuse_api_state.fuse_get_context = (hypergit_linux_fuse_get_context_fn)dlsym(library_handle, "fuse_get_context");

  if (hypergit_linux_fuse_api_state.fuse_new == NULL ||
      hypergit_linux_fuse_api_state.fuse_get_session == NULL ||
      hypergit_linux_fuse_api_state.fuse_session_mount == NULL ||
      hypergit_linux_fuse_api_state.fuse_session_unmount == NULL ||
      hypergit_linux_fuse_api_state.fuse_session_loop == NULL ||
      hypergit_linux_fuse_api_state.fuse_session_exit == NULL ||
      hypergit_linux_fuse_api_state.fuse_destroy == NULL ||
      hypergit_linux_fuse_api_state.fuse_get_context == NULL) {
    dlclose(library_handle);
    hypergit_linux_fuse_api_state = (struct hypergit_linux_fuse_api){0};
    return -ENOENT;
  }

  hypergit_linux_fuse_api_ready = 1;
  return 0;
}

static int hypergit_linux_fuse_path_compare(const char *left, size_t left_len, const char *right, size_t right_len) {
  size_t limit = left_len < right_len ? left_len : right_len;
  size_t i = 0;
  while (i < limit) {
    const unsigned char left_byte = (const unsigned char)left[i];
    const unsigned char right_byte = (const unsigned char)right[i];
    if (left_byte < right_byte) {
      return -1;
    }
    if (left_byte > right_byte) {
      return 1;
    }
    i += 1;
  }
  if (left_len < right_len) {
    return -1;
  }
  if (left_len > right_len) {
    return 1;
  }
  return 0;
}

static int hypergit_linux_fuse_path_is_valid(const char *path, size_t len) {
  size_t segment_start = 0;
  size_t i = 0;
  if (path == NULL || len == 0) {
    return -EINVAL;
  }
  while (i < len) {
    if (path[i] == '\0') {
      return -EINVAL;
    }
    if (path[i] == '/') {
      const size_t segment_len = i - segment_start;
      if (segment_len == 0) {
        return -EINVAL;
      }
      if (segment_len == 1 && path[segment_start] == '.') {
        return -EINVAL;
      }
      if (segment_len == 2 && path[segment_start] == '.' && path[segment_start + 1] == '.') {
        return -EINVAL;
      }
      segment_start = i + 1;
    }
    i += 1;
  }
  if (segment_start >= len) {
    return -EINVAL;
  }
  {
    const size_t segment_len = len - segment_start;
    if (segment_len == 1 && path[segment_start] == '.') {
      return -EINVAL;
    }
    if (segment_len == 2 && path[segment_start] == '.' && path[segment_start + 1] == '.') {
      return -EINVAL;
    }
  }
  return 0;
}

static int hypergit_linux_fuse_copy_string(const unsigned char *src, size_t len, char **out) {
  char *copy;
  size_t i;
  if (len == 0) {
    *out = NULL;
    return 0;
  }
  if (src == NULL) {
    return -EINVAL;
  }
  copy = (char *)malloc(len + 1);
  if (copy == NULL) {
    return -ENOMEM;
  }
  i = 0;
  while (i < len) {
    if (src[i] == '\0') {
      free(copy);
      return -EINVAL;
    }
    copy[i] = (char)src[i];
    i += 1;
  }
  copy[len] = '\0';
  *out = copy;
  return 0;
}

static void hypergit_linux_fuse_free_entry_runtime(struct hypergit_linux_fuse_entry_runtime *entry) {
  if (entry == NULL) {
    return;
  }
  free(entry->path);
  free(entry->backing_path);
  entry->path = NULL;
  entry->backing_path = NULL;
}

static int hypergit_linux_fuse_entry_runtime_compare(const void *left_ptr, const void *right_ptr) {
  const struct hypergit_linux_fuse_entry_runtime *left = (const struct hypergit_linux_fuse_entry_runtime *)left_ptr;
  const struct hypergit_linux_fuse_entry_runtime *right = (const struct hypergit_linux_fuse_entry_runtime *)right_ptr;
  return hypergit_linux_fuse_path_compare(left->path, left->path_len, right->path, right->path_len);
}

static int hypergit_linux_fuse_handle_validate_entries(struct hypergit_linux_fuse_mount_handle *handle, const struct hypergit_linux_fuse_snapshot *snapshot) {
  size_t i;
  if (snapshot->entries.len == 0) {
    handle->entries = NULL;
    handle->entry_count = 0;
    return 0;
  }
  handle->entries = (struct hypergit_linux_fuse_entry_runtime *)calloc(snapshot->entries.len, sizeof(struct hypergit_linux_fuse_entry_runtime));
  if (handle->entries == NULL) {
    return -ENOMEM;
  }
  handle->entry_count = snapshot->entries.len;
  i = 0;
  while (i < snapshot->entries.len) {
    const struct hypergit_linux_fuse_entry *input = &snapshot->entries.ptr[i];
    struct hypergit_linux_fuse_entry_runtime *out = &handle->entries[i];
    int rc;
    if (hypergit_linux_fuse_path_is_valid((const char *)input->path.ptr, input->path.len) != 0) {
      return -EINVAL;
    }
    if (input->placeholder_state < HYPERGIT_LINUX_FUSE_PLACEHOLDER_VIRTUAL_ONLY ||
        input->placeholder_state > HYPERGIT_LINUX_FUSE_PLACEHOLDER_DIRTY_MATERIALIZED) {
      return -EINVAL;
    }
    rc = hypergit_linux_fuse_copy_string(input->path.ptr, input->path.len, &out->path);
    if (rc != 0) {
      return rc;
    }
    out->path_len = input->path.len;
    out->mode = input->mode;
    out->logical_size = input->logical_size;
    out->placeholder_state = input->placeholder_state;
    if (input->placeholder_state == HYPERGIT_LINUX_FUSE_PLACEHOLDER_VIRTUAL_ONLY) {
      if (input->backing_path.len != 0) {
        return -EINVAL;
      }
      out->backing_path = NULL;
      out->backing_path_len = 0;
    } else {
      if (input->backing_path.len == 0 || input->backing_path.ptr == NULL) {
        return -EINVAL;
      }
      rc = hypergit_linux_fuse_copy_string(input->backing_path.ptr, input->backing_path.len, &out->backing_path);
      if (rc != 0) {
        return rc;
      }
      out->backing_path_len = input->backing_path.len;
    }
    i += 1;
  }
  qsort(handle->entries, handle->entry_count, sizeof(struct hypergit_linux_fuse_entry_runtime), hypergit_linux_fuse_entry_runtime_compare);
  i = 1;
  while (i < handle->entry_count) {
    const struct hypergit_linux_fuse_entry_runtime *prev = &handle->entries[i - 1];
    const struct hypergit_linux_fuse_entry_runtime *curr = &handle->entries[i];
    if (hypergit_linux_fuse_path_compare(prev->path, prev->path_len, curr->path, curr->path_len) == 0) {
      return -EINVAL;
    }
    if (curr->path_len > prev->path_len &&
        strncmp(curr->path, prev->path, prev->path_len) == 0 &&
        curr->path[prev->path_len] == '/') {
      return -ENOTDIR;
    }
    i += 1;
  }
  return 0;
}

static struct hypergit_linux_fuse_mount_handle *hypergit_linux_fuse_from_private_data(void) {
  struct fuse_context *context;
  if (!hypergit_linux_fuse_api_ready || hypergit_linux_fuse_api_state.fuse_get_context == NULL) {
    return NULL;
  }
  context = hypergit_linux_fuse_api_state.fuse_get_context();
  if (context == NULL || context->private_data == NULL) {
    return NULL;
  }
  return (struct hypergit_linux_fuse_mount_handle *)context->private_data;
}

static int hypergit_linux_fuse_path_view_from_callback(const char *path, const char **out_ptr, size_t *out_len) {
  const char *start;
  size_t len;
  if (path == NULL || path[0] != '/') {
    return -ENOENT;
  }
  start = path + 1;
  len = strlen(start);
  while (len > 0 && start[len - 1] == '/') {
    len -= 1;
  }
  *out_ptr = start;
  *out_len = len;
  return 0;
}

static ssize_t hypergit_linux_fuse_find_entry_index(const struct hypergit_linux_fuse_mount_handle *handle, const char *path, size_t path_len) {
  size_t low = 0;
  size_t high = handle->entry_count;
  while (low < high) {
    const size_t mid = low + ((high - low) / 2);
    const int cmp = hypergit_linux_fuse_path_compare(handle->entries[mid].path, handle->entries[mid].path_len, path, path_len);
    if (cmp < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  if (low < handle->entry_count &&
      hypergit_linux_fuse_path_compare(handle->entries[low].path, handle->entries[low].path_len, path, path_len) == 0) {
    return (ssize_t)low;
  }
  return -1;
}

static int hypergit_linux_fuse_path_has_prefix(const char *path, size_t path_len, const char *prefix, size_t prefix_len) {
  if (path_len < prefix_len) {
    return 0;
  }
  if (prefix_len == 0) {
    return 1;
  }
  return memcmp(path, prefix, prefix_len) == 0;
}

static size_t hypergit_linux_fuse_prefix_lower_bound(const struct hypergit_linux_fuse_mount_handle *handle, const char *prefix, size_t prefix_len) {
  size_t low = 0;
  size_t high = handle->entry_count;
  while (low < high) {
    const size_t mid = low + ((high - low) / 2);
    const int cmp = hypergit_linux_fuse_path_compare(handle->entries[mid].path, handle->entries[mid].path_len, prefix, prefix_len);
    if (cmp < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

static int hypergit_linux_fuse_path_is_directory(const struct hypergit_linux_fuse_mount_handle *handle, const char *path, size_t path_len) {
  const size_t prefix_len = path_len == 0 ? 0 : path_len + 1;
  char *prefix;
  size_t index;
  if (path_len == 0) {
    return 1;
  }
  index = hypergit_linux_fuse_find_entry_index(handle, path, path_len);
  if (index >= 0) {
    return 0;
  }
  prefix = (char *)malloc(prefix_len + 1);
  if (prefix == NULL) {
    return 0;
  }
  memcpy(prefix, path, path_len);
  prefix[path_len] = '/';
  prefix[prefix_len] = '\0';
  index = hypergit_linux_fuse_prefix_lower_bound(handle, prefix, prefix_len);
  if (index < handle->entry_count &&
      hypergit_linux_fuse_path_has_prefix(handle->entries[index].path, handle->entries[index].path_len, prefix, prefix_len)) {
    free(prefix);
    return 1;
  }
  free(prefix);
  return 0;
}

static void hypergit_linux_fuse_fill_dir_stat(struct stat *stbuf, mode_t mode, off_t size) {
  memset(stbuf, 0, sizeof(*stbuf));
  stbuf->st_mode = mode;
  stbuf->st_nlink = 2;
  stbuf->st_size = size;
}

static struct hypergit_linux_fuse_entry_runtime *hypergit_linux_fuse_lookup_entry(struct hypergit_linux_fuse_mount_handle *handle, const char *path, size_t path_len) {
  const ssize_t index = hypergit_linux_fuse_find_entry_index(handle, path, path_len);
  if (index < 0) {
    return NULL;
  }
  return &handle->entries[index];
}

static int hypergit_linux_fuse_getattr(const char *path, struct stat *stbuf, struct fuse_file_info *fi) {
  struct hypergit_linux_fuse_mount_handle *handle;
  const char *view_ptr;
  size_t view_len;
  struct hypergit_linux_fuse_entry_runtime *entry;
  (void)fi;
  handle = hypergit_linux_fuse_from_private_data();
  if (handle == NULL) {
    return -EIO;
  }
  if (hypergit_linux_fuse_path_view_from_callback(path, &view_ptr, &view_len) != 0) {
    return -ENOENT;
  }
  if (view_len == 0) {
    hypergit_linux_fuse_fill_dir_stat(stbuf, S_IFDIR | 0555, 0);
    return 0;
  }
  entry = hypergit_linux_fuse_lookup_entry(handle, view_ptr, view_len);
  if (entry != NULL) {
    const off_t size = entry->placeholder_state == HYPERGIT_LINUX_FUSE_PLACEHOLDER_VIRTUAL_ONLY ? 0 : (off_t)entry->logical_size;
    memset(stbuf, 0, sizeof(*stbuf));
    stbuf->st_mode = (mode_t)entry->mode;
    stbuf->st_nlink = 1;
    stbuf->st_size = size;
    return 0;
  }
  if (hypergit_linux_fuse_path_is_directory(handle, view_ptr, view_len)) {
    hypergit_linux_fuse_fill_dir_stat(stbuf, S_IFDIR | 0555, 0);
    return 0;
  }
  return -ENOENT;
}

static int hypergit_linux_fuse_open(const char *path, struct fuse_file_info *fi) {
  struct hypergit_linux_fuse_mount_handle *handle;
  const char *view_ptr;
  size_t view_len;
  struct hypergit_linux_fuse_entry_runtime *entry;
  int fd;
  if (fi != NULL && (fi->flags & O_ACCMODE) != O_RDONLY) {
    return -EROFS;
  }
  handle = hypergit_linux_fuse_from_private_data();
  if (handle == NULL) {
    return -EIO;
  }
  if (hypergit_linux_fuse_path_view_from_callback(path, &view_ptr, &view_len) != 0) {
    return -ENOENT;
  }
  entry = hypergit_linux_fuse_lookup_entry(handle, view_ptr, view_len);
  if (entry == NULL) {
    if (hypergit_linux_fuse_path_is_directory(handle, view_ptr, view_len)) {
      return -EISDIR;
    }
    return -ENOENT;
  }
  if (entry->placeholder_state == HYPERGIT_LINUX_FUSE_PLACEHOLDER_VIRTUAL_ONLY) {
    if (fi != NULL) {
      fi->fh = HYPERGIT_LINUX_FUSE_INVALID_FH;
    }
    return 0;
  }
  fd = open(entry->backing_path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    return -errno;
  }
  if (fi != NULL) {
    fi->fh = (uint64_t)fd;
  } else {
    close(fd);
  }
  return 0;
}

static int hypergit_linux_fuse_read(const char *path, char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
  struct hypergit_linux_fuse_mount_handle *handle;
  const char *view_ptr;
  size_t view_len;
  struct hypergit_linux_fuse_entry_runtime *entry;
  int fd;
  int must_close;
  ssize_t read_count;
  handle = hypergit_linux_fuse_from_private_data();
  if (handle == NULL) {
    return -EIO;
  }
  if (hypergit_linux_fuse_path_view_from_callback(path, &view_ptr, &view_len) != 0) {
    return -ENOENT;
  }
  entry = hypergit_linux_fuse_lookup_entry(handle, view_ptr, view_len);
  if (entry == NULL) {
    if (hypergit_linux_fuse_path_is_directory(handle, view_ptr, view_len)) {
      return -EISDIR;
    }
    return -ENOENT;
  }
  if (entry->placeholder_state == HYPERGIT_LINUX_FUSE_PLACEHOLDER_VIRTUAL_ONLY) {
    return 0;
  }
  fd = -1;
  must_close = 0;
  if (fi != NULL && fi->fh != HYPERGIT_LINUX_FUSE_INVALID_FH) {
    fd = (int)fi->fh;
  } else {
    fd = open(entry->backing_path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
      return -errno;
    }
    must_close = 1;
  }
  read_count = pread(fd, buf, size, offset);
  if (must_close) {
    close(fd);
  }
  if (read_count < 0) {
    return -errno;
  }
  if (read_count > (ssize_t)INT_MAX) {
    return INT_MAX;
  }
  return (int)read_count;
}

static int hypergit_linux_fuse_release(const char *path, struct fuse_file_info *fi) {
  struct hypergit_linux_fuse_mount_handle *handle;
  const char *view_ptr;
  size_t view_len;
  struct hypergit_linux_fuse_entry_runtime *entry;
  (void)path;
  handle = hypergit_linux_fuse_from_private_data();
  if (handle == NULL || fi == NULL || fi->fh == HYPERGIT_LINUX_FUSE_INVALID_FH) {
    return 0;
  }
  if (hypergit_linux_fuse_path_view_from_callback(path, &view_ptr, &view_len) != 0) {
    return 0;
  }
  entry = hypergit_linux_fuse_lookup_entry(handle, view_ptr, view_len);
  if (entry == NULL || entry->placeholder_state == HYPERGIT_LINUX_FUSE_PLACEHOLDER_VIRTUAL_ONLY) {
    return 0;
  }
  close((int)fi->fh);
  fi->fh = HYPERGIT_LINUX_FUSE_INVALID_FH;
  return 0;
}

static int hypergit_linux_fuse_opendir(const char *path, struct fuse_file_info *fi) {
  struct hypergit_linux_fuse_mount_handle *handle;
  const char *view_ptr;
  size_t view_len;
  (void)fi;
  handle = hypergit_linux_fuse_from_private_data();
  if (handle == NULL) {
    return -EIO;
  }
  if (hypergit_linux_fuse_path_view_from_callback(path, &view_ptr, &view_len) != 0) {
    return -ENOENT;
  }
  if (view_len == 0 || hypergit_linux_fuse_path_is_directory(handle, view_ptr, view_len)) {
    return 0;
  }
  return -ENOTDIR;
}

static int hypergit_linux_fuse_readdir(const char *path, void *buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info *fi, enum fuse_readdir_flags flags) {
  struct hypergit_linux_fuse_mount_handle *handle;
  const char *view_ptr;
  size_t view_len;
  size_t prefix_len;
  char *prefix;
  size_t index;
  struct stat dir_stat;
  (void)offset;
  (void)fi;
  (void)flags;
  handle = hypergit_linux_fuse_from_private_data();
  if (handle == NULL) {
    return -EIO;
  }
  if (hypergit_linux_fuse_path_view_from_callback(path, &view_ptr, &view_len) != 0) {
    return -ENOENT;
  }
  if (!(view_len == 0 || hypergit_linux_fuse_path_is_directory(handle, view_ptr, view_len))) {
    return -ENOTDIR;
  }
  hypergit_linux_fuse_fill_dir_stat(&dir_stat, S_IFDIR | 0555, 0);
  if (filler(buf, ".", &dir_stat, 0, FUSE_FILL_DIR_DEFAULTS) != 0) {
    return 0;
  }
  if (filler(buf, "..", &dir_stat, 0, FUSE_FILL_DIR_DEFAULTS) != 0) {
    return 0;
  }
  if (view_len == 0) {
    prefix = NULL;
    prefix_len = 0;
    index = 0;
  } else {
    prefix_len = view_len + 1;
    prefix = (char *)malloc(prefix_len + 1);
    if (prefix == NULL) {
      return -ENOMEM;
    }
    memcpy(prefix, view_ptr, view_len);
    prefix[view_len] = '/';
    prefix[prefix_len] = '\0';
    index = hypergit_linux_fuse_prefix_lower_bound(handle, prefix, prefix_len);
  }
  {
    const char *last_child = NULL;
    size_t last_child_len = 0;
  while (index < handle->entry_count) {
    const struct hypergit_linux_fuse_entry_runtime *entry = &handle->entries[index];
    const char *suffix;
    const char *slash;
    size_t child_len;
    size_t suffix_len;
    char *child_name;
    struct stat child_stat;
    int child_is_dir;
    if (view_len != 0 && !hypergit_linux_fuse_path_has_prefix(entry->path, entry->path_len, prefix, prefix_len)) {
      break;
    }
    suffix = entry->path + (view_len == 0 ? 0 : prefix_len);
    suffix_len = entry->path_len - (view_len == 0 ? 0 : prefix_len);
    slash = memchr(suffix, '/', suffix_len);
    if (slash != NULL) {
      child_len = (size_t)(slash - suffix);
      child_is_dir = 1;
    } else {
      child_len = suffix_len;
      child_is_dir = 0;
    }
    if (child_len == 0) {
      index += 1;
      continue;
    }
    if (last_child != NULL && last_child_len == child_len && strncmp(last_child, suffix, child_len) == 0) {
      index += 1;
      continue;
    }
    child_name = (char *)malloc(child_len + 1);
    if (child_name == NULL) {
      if (prefix != NULL) {
        free(prefix);
      }
      return -ENOMEM;
    }
    memcpy(child_name, suffix, child_len);
    child_name[child_len] = '\0';
    if (child_is_dir) {
      hypergit_linux_fuse_fill_dir_stat(&child_stat, S_IFDIR | 0555, 0);
    } else {
      hypergit_linux_fuse_fill_dir_stat(&child_stat, (mode_t)entry->mode, entry->placeholder_state == HYPERGIT_LINUX_FUSE_PLACEHOLDER_VIRTUAL_ONLY ? 0 : (off_t)entry->logical_size);
      child_stat.st_nlink = 1;
    }
    if (filler(buf, child_name, &child_stat, 0, FUSE_FILL_DIR_DEFAULTS) != 0) {
      free(child_name);
      if (prefix != NULL) {
        free(prefix);
      }
      return 0;
    }
    free(child_name);
    last_child = suffix;
    last_child_len = child_len;
    index += 1;
  }
  }
  if (prefix != NULL) {
    free(prefix);
  }
  return 0;
}

static int hypergit_linux_fuse_releasedir(const char *path, struct fuse_file_info *fi) {
  (void)path;
  (void)fi;
  return 0;
}

static struct fuse_operations hypergit_linux_fuse_operations = {
  .getattr = hypergit_linux_fuse_getattr,
  .readlink = NULL,
  .mknod = NULL,
  .mkdir = NULL,
  .unlink = NULL,
  .rmdir = NULL,
  .symlink = NULL,
  .rename = NULL,
  .link = NULL,
  .chmod = NULL,
  .chown = NULL,
  .truncate = NULL,
  .open = hypergit_linux_fuse_open,
  .read = hypergit_linux_fuse_read,
  .write = NULL,
  .statfs = NULL,
  .flush = NULL,
  .release = hypergit_linux_fuse_release,
  .fsync = NULL,
  .setxattr = NULL,
  .getxattr = NULL,
  .listxattr = NULL,
  .removexattr = NULL,
  .opendir = hypergit_linux_fuse_opendir,
  .readdir = hypergit_linux_fuse_readdir,
  .releasedir = hypergit_linux_fuse_releasedir,
  .fsyncdir = NULL,
  .init = NULL,
  .destroy = NULL
};

static void hypergit_linux_fuse_free_args(struct fuse_args *args) {
  int i;
  if (args == NULL || args->argv == NULL) {
    return;
  }
  i = 0;
  while (i < args->argc) {
    free(args->argv[i]);
    i += 1;
  }
  free(args->argv);
  args->argv = NULL;
  args->argc = 0;
  args->allocated = 0;
}

static void hypergit_linux_fuse_request_stop(struct hypergit_linux_fuse_mount_handle *handle) {
  if (handle == NULL || handle->session == NULL || handle->stop_requested) {
    return;
  }
  handle->stop_requested = 1;
  if (!handle->mounted) {
    return;
  }
  hypergit_linux_fuse_api_state.fuse_session_exit(handle->session);
  hypergit_linux_fuse_api_state.fuse_session_unmount(handle->session);
  if (handle->mountpoint != NULL) {
    (void)umount2(handle->mountpoint, MNT_DETACH);
  }
  handle->mounted = 0;
}

static int hypergit_linux_fuse_join_thread(struct hypergit_linux_fuse_mount_handle *handle) {
  int pthread_rc;
  if (handle == NULL || !handle->thread_started || handle->thread_joined) {
    return 0;
  }
  pthread_rc = pthread_join(handle->thread, NULL);
  if (pthread_rc != 0) {
    return -pthread_rc;
  }
  handle->thread_joined = 1;
  if (!handle->stop_requested && handle->loop_result < 0) {
    return -EIO;
  }
  return 0;
}

static void hypergit_linux_fuse_free_handle(struct hypergit_linux_fuse_mount_handle *handle) {
  size_t i;
  if (handle == NULL) {
    return;
  }
  hypergit_linux_fuse_request_stop(handle);
  (void)hypergit_linux_fuse_join_thread(handle);
  if (handle->fuse != NULL) {
    hypergit_linux_fuse_api_state.fuse_destroy(handle->fuse);
    handle->fuse = NULL;
    handle->session = NULL;
  }
  i = 0;
  while (i < handle->entry_count) {
    hypergit_linux_fuse_free_entry_runtime(&handle->entries[i]);
    i += 1;
  }
  free(handle->entries);
  free(handle->mountpoint);
  free(handle);
}

static void *hypergit_linux_fuse_loop_thread_main(void *arg) {
  struct hypergit_linux_fuse_mount_handle *handle = (struct hypergit_linux_fuse_mount_handle *)arg;
  handle->loop_result = hypergit_linux_fuse_api_state.fuse_session_loop(handle->session);
  return NULL;
}

static int hypergit_linux_fuse_mount_handle_init(struct hypergit_linux_fuse_mount_handle *handle, const struct hypergit_linux_fuse_snapshot *snapshot, const unsigned char *mountpoint, size_t mountpoint_len) {
  int rc;
  struct fuse_args args;
  char **argv;
  char *program_name;
  char *option_ro;
  char *option_fsname;
  char debug_buf[256];
  int debug_len;
  rc = hypergit_linux_fuse_load_api();
  if (rc != 0) {
    return rc;
  }
  if (mountpoint == NULL || mountpoint_len == 0) {
    return -EINVAL;
  }
  if (mountpoint[mountpoint_len - 1] == '\0') {
    return -EINVAL;
  }
  rc = hypergit_linux_fuse_copy_string(mountpoint, mountpoint_len, &handle->mountpoint);
  if (rc != 0) {
    return rc;
  }
  {
    char *resolved_mountpoint = realpath(handle->mountpoint, NULL);
    if (resolved_mountpoint == NULL) {
      return -errno;
    }
    free(handle->mountpoint);
    handle->mountpoint = resolved_mountpoint;
  }
  rc = hypergit_linux_fuse_handle_validate_entries(handle, snapshot);
  if (rc != 0) {
    return rc;
  }
  program_name = (char *)malloc(strlen("hypergit-linux-fuse") + 1);
  if (program_name == NULL) {
    return -ENOMEM;
  }
  strcpy(program_name, "hypergit-linux-fuse");
  option_ro = (char *)malloc(strlen("-o") + 1);
  if (option_ro == NULL) {
    free(program_name);
    return -ENOMEM;
  }
  strcpy(option_ro, "-o");
  option_fsname = (char *)malloc(strlen("ro,fsname=hypergit-linux-fuse") + 1);
  if (option_fsname == NULL) {
    free(program_name);
    free(option_ro);
    return -ENOMEM;
  }
  strcpy(option_fsname, "ro,fsname=hypergit-linux-fuse");
  argv = (char **)calloc(4, sizeof(char *));
  if (argv == NULL) {
    free(program_name);
    free(option_ro);
    free(option_fsname);
    return -ENOMEM;
  }
  argv[0] = program_name;
  argv[1] = option_ro;
  argv[2] = option_fsname;
  argv[3] = NULL;
  args.argc = 3;
  args.argv = argv;
  args.allocated = 1;
  handle->fuse = hypergit_linux_fuse_api_state.fuse_new(&args, &hypergit_linux_fuse_operations, sizeof(hypergit_linux_fuse_operations), handle);
  if (handle->fuse == NULL) {
    return -EIO;
  }
  handle->session = hypergit_linux_fuse_api_state.fuse_get_session(handle->fuse);
  if (handle->session == NULL) {
    hypergit_linux_fuse_api_state.fuse_destroy(handle->fuse);
    handle->fuse = NULL;
    return -EIO;
  }
  rc = hypergit_linux_fuse_api_state.fuse_session_mount(handle->session, handle->mountpoint);
  if (rc != 0) {
    hypergit_linux_fuse_api_state.fuse_destroy(handle->fuse);
    handle->fuse = NULL;
    handle->session = NULL;
    return -EIO;
  }
  handle->mounted = 1;
  rc = pthread_create(&handle->thread, NULL, hypergit_linux_fuse_loop_thread_main, handle);
  if (rc != 0) {
    hypergit_linux_fuse_request_stop(handle);
    hypergit_linux_fuse_api_state.fuse_destroy(handle->fuse);
    handle->fuse = NULL;
    handle->session = NULL;
    return -rc;
  }
  handle->thread_started = 1;
  return 0;
}

unsigned char *hypergit_linux_fuse_mount_start(const struct hypergit_linux_fuse_snapshot *snapshot, const unsigned char *mountpoint, size_t mountpoint_len) {
  struct hypergit_linux_fuse_mount_handle *handle;
  int rc;
  if (snapshot == NULL || snapshot->entries.ptr == NULL && snapshot->entries.len != 0) {
    return NULL;
  }
  handle = (struct hypergit_linux_fuse_mount_handle *)calloc(1, sizeof(struct hypergit_linux_fuse_mount_handle));
  if (handle == NULL) {
    return NULL;
  }
  rc = hypergit_linux_fuse_mount_handle_init(handle, snapshot, mountpoint, mountpoint_len);
  if (rc != 0) {
    hypergit_linux_fuse_free_handle(handle);
    return NULL;
  }
  return (unsigned char *)handle;
}

void hypergit_linux_fuse_mount_stop(unsigned char *handle_ptr) {
  struct hypergit_linux_fuse_mount_handle *handle = (struct hypergit_linux_fuse_mount_handle *)handle_ptr;
  if (handle == NULL) {
    return;
  }
  hypergit_linux_fuse_request_stop(handle);
}

int hypergit_linux_fuse_mount_join(unsigned char *handle_ptr) {
  struct hypergit_linux_fuse_mount_handle *handle = (struct hypergit_linux_fuse_mount_handle *)handle_ptr;
  int rc;
  if (handle == NULL) {
    return 0;
  }
  if (!handle->stop_requested) {
    hypergit_linux_fuse_request_stop(handle);
  }
  rc = hypergit_linux_fuse_join_thread(handle);
  if (rc != 0) {
    return rc;
  }
  return 0;
}

void hypergit_linux_fuse_mount_destroy(unsigned char *handle_ptr) {
  struct hypergit_linux_fuse_mount_handle *handle = (struct hypergit_linux_fuse_mount_handle *)handle_ptr;
  hypergit_linux_fuse_free_handle(handle);
}
