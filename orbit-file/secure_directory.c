#include <moonbit.h>

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#include <winternl.h>
#else
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

#define ORBIT_DIRECTORY_STATUS_OK 0
#define ORBIT_DIRECTORY_STATUS_OPEN_FAILED 1
#define ORBIT_DIRECTORY_STATUS_INVALID_CHILD_NAME 2
#define ORBIT_DIRECTORY_STATUS_READ_FAILED 3
#define ORBIT_DIRECTORY_STATUS_TOO_LARGE 4

#define ORBIT_DIRECTORY_MAX_ENTRIES 128
#define ORBIT_DIRECTORY_MAX_NAME_BYTES 4096
#define ORBIT_DIRECTORY_MAX_RESPONSE_BYTES (192 * 1024)

typedef struct {
#if defined(_WIN32)
  void *handle;
#else
  int fd;
#endif
} orbit_directory_handle_t;

typedef struct {
#if defined(_WIN32)
  void *handle;
#else
  int fd;
#endif
} orbit_read_file_handle_t;

static void orbit_directory_finalize(void *self) {
  orbit_directory_handle_t *directory = (orbit_directory_handle_t *)self;
#if defined(_WIN32)
  if (directory->handle != NULL && directory->handle != (void *)(intptr_t)-1) {
    CloseHandle((HANDLE)directory->handle);
    directory->handle = NULL;
  }
#else
  if (directory->fd >= 0) {
    close(directory->fd);
    directory->fd = -1;
  }
#endif
}

static orbit_directory_handle_t *orbit_directory_wrap(void) {
  orbit_directory_handle_t *directory =
    (orbit_directory_handle_t *)moonbit_make_external_object(
      orbit_directory_finalize,
      sizeof(orbit_directory_handle_t)
    );
#if defined(_WIN32)
  directory->handle = NULL;
#else
  directory->fd = -1;
#endif
  return directory;
}

static void orbit_read_file_finalize(void *self) {
  orbit_read_file_handle_t *file = (orbit_read_file_handle_t *)self;
#if defined(_WIN32)
  if (file->handle != NULL && file->handle != (void *)(intptr_t)-1) {
    CloseHandle((HANDLE)file->handle);
    file->handle = NULL;
  }
#else
  if (file->fd >= 0) {
    close(file->fd);
    file->fd = -1;
  }
#endif
}

static orbit_read_file_handle_t *orbit_read_file_wrap(void) {
  orbit_read_file_handle_t *file =
    (orbit_read_file_handle_t *)moonbit_make_external_object(
      orbit_read_file_finalize,
      sizeof(orbit_read_file_handle_t)
    );
#if defined(_WIN32)
  file->handle = NULL;
#else
  file->fd = -1;
#endif
  return file;
}

static int orbit_directory_is_hidden_name(const char *name, size_t length) {
  return length > 0 && name[0] == '.';
}

static int orbit_directory_is_valid_child_name(const uint8_t *name, int32_t length) {
  if (name == NULL || length <= 0 || length > ORBIT_DIRECTORY_MAX_NAME_BYTES) {
    return 0;
  }
  if ((length == 1 && name[0] == '.') ||
      (length == 2 && name[0] == '.' && name[1] == '.')) {
    return 0;
  }
  for (int32_t index = 0; index < length; index++) {
    if (name[index] == 0 || name[index] == '/' || name[index] == '\\') {
      return 0;
    }
  }
  return 1;
}

typedef struct {
  uint8_t *data;
  size_t length;
  size_t capacity;
  int32_t count;
} orbit_directory_buffer_t;

static void orbit_directory_buffer_free(orbit_directory_buffer_t *buffer) {
  free(buffer->data);
  buffer->data = NULL;
  buffer->length = 0;
  buffer->capacity = 0;
}

static int orbit_directory_buffer_reserve(orbit_directory_buffer_t *buffer, size_t extra) {
  if (extra > ORBIT_DIRECTORY_MAX_RESPONSE_BYTES ||
      buffer->length > ORBIT_DIRECTORY_MAX_RESPONSE_BYTES - extra) {
    return 0;
  }
  size_t needed = buffer->length + extra;
  if (needed <= buffer->capacity) {
    return 1;
  }
  size_t capacity = buffer->capacity == 0 ? 1024 : buffer->capacity;
  while (capacity < needed) {
    if (capacity > ORBIT_DIRECTORY_MAX_RESPONSE_BYTES / 2) {
      capacity = ORBIT_DIRECTORY_MAX_RESPONSE_BYTES;
      break;
    }
    capacity *= 2;
  }
  uint8_t *data = (uint8_t *)realloc(buffer->data, capacity);
  if (data == NULL) {
    return 0;
  }
  buffer->data = data;
  buffer->capacity = capacity;
  return 1;
}

static int orbit_directory_buffer_append_u32(orbit_directory_buffer_t *buffer, uint32_t value) {
  if (!orbit_directory_buffer_reserve(buffer, 4)) {
    return 0;
  }
  buffer->data[buffer->length++] = (uint8_t)(value & 0xffU);
  buffer->data[buffer->length++] = (uint8_t)((value >> 8) & 0xffU);
  buffer->data[buffer->length++] = (uint8_t)((value >> 16) & 0xffU);
  buffer->data[buffer->length++] = (uint8_t)((value >> 24) & 0xffU);
  return 1;
}

static int orbit_directory_buffer_append_entry(
  orbit_directory_buffer_t *buffer,
  uint8_t kind,
  const uint8_t *name,
  size_t name_length
) {
  if (name_length == 0 || name_length > ORBIT_DIRECTORY_MAX_NAME_BYTES ||
      !orbit_directory_buffer_reserve(buffer, 5 + name_length)) {
    return 0;
  }
  buffer->data[buffer->length++] = kind;
  buffer->data[buffer->length++] = (uint8_t)(name_length & 0xffU);
  buffer->data[buffer->length++] = (uint8_t)((name_length >> 8) & 0xffU);
  buffer->data[buffer->length++] = (uint8_t)((name_length >> 16) & 0xffU);
  buffer->data[buffer->length++] = (uint8_t)((name_length >> 24) & 0xffU);
  memcpy(buffer->data + buffer->length, name, name_length);
  buffer->length += name_length;
  buffer->count += 1;
  return 1;
}

static moonbit_bytes_t orbit_directory_buffer_to_bytes(orbit_directory_buffer_t *buffer) {
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)buffer->length, 0);
  if (buffer->length > 0) {
    memcpy(bytes, buffer->data, buffer->length);
  }
  return bytes;
}

#if defined(_WIN32)

#ifndef OBJ_DONT_REPARSE
#define OBJ_DONT_REPARSE 0x00001000L
#endif

#ifndef FILE_OPEN_FOR_BACKUP_INTENT
#define FILE_OPEN_FOR_BACKUP_INTENT 0x00004000UL
#endif

typedef NTSTATUS(NTAPI *orbit_nt_create_file_fn)(
  PHANDLE,
  ACCESS_MASK,
  POBJECT_ATTRIBUTES,
  PIO_STATUS_BLOCK,
  PLARGE_INTEGER,
  ULONG,
  ULONG,
  ULONG,
  ULONG,
  PVOID,
  ULONG
);

typedef NTSTATUS(NTAPI *orbit_nt_query_directory_file_fn)(
  HANDLE,
  HANDLE,
  PIO_APC_ROUTINE,
  PVOID,
  PIO_STATUS_BLOCK,
  PVOID,
  ULONG,
  FILE_INFORMATION_CLASS,
  BOOLEAN,
  PUNICODE_STRING,
  BOOLEAN
);

typedef struct {
  ULONG NextEntryOffset;
  ULONG FileIndex;
  LARGE_INTEGER CreationTime;
  LARGE_INTEGER LastAccessTime;
  LARGE_INTEGER LastWriteTime;
  LARGE_INTEGER ChangeTime;
  LARGE_INTEGER EndOfFile;
  LARGE_INTEGER AllocationSize;
  ULONG FileAttributes;
  ULONG FileNameLength;
  WCHAR FileName[1];
} orbit_file_directory_information_t;

#define ORBIT_FILE_DIRECTORY_INFORMATION ((FILE_INFORMATION_CLASS)1)

static int orbit_directory_nt_functions(
  orbit_nt_create_file_fn *create_file,
  orbit_nt_query_directory_file_fn *query_directory
) {
  HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
  if (ntdll == NULL) {
    return 0;
  }
  *create_file = (orbit_nt_create_file_fn)GetProcAddress(ntdll, "NtCreateFile");
  *query_directory = (orbit_nt_query_directory_file_fn)GetProcAddress(
    ntdll,
    "NtQueryDirectoryFile"
  );
  return *create_file != NULL && *query_directory != NULL;
}

static wchar_t *orbit_directory_utf8_to_wide(
  const uint8_t *utf8,
  int32_t length,
  int32_t *wide_length
) {
  if (utf8 == NULL || length <= 0 || memchr(utf8, 0, (size_t)length) != NULL) {
    return NULL;
  }
  int needed = MultiByteToWideChar(
    CP_UTF8,
    MB_ERR_INVALID_CHARS,
    (const char *)utf8,
    length,
    NULL,
    0
  );
  if (needed <= 0) {
    return NULL;
  }
  wchar_t *wide = (wchar_t *)calloc((size_t)needed + 1, sizeof(wchar_t));
  if (wide == NULL) {
    return NULL;
  }
  if (MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        (const char *)utf8,
        length,
        wide,
        needed
      ) != needed) {
    free(wide);
    return NULL;
  }
  *wide_length = needed;
  return wide;
}

static int orbit_directory_handle_is_safe_directory(HANDLE handle) {
  BY_HANDLE_FILE_INFORMATION information;
  if (!GetFileInformationByHandle(handle, &information)) {
    return 0;
  }
  return (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0 &&
    (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
}

static int orbit_directory_handle_is_safe_regular_file(HANDLE handle) {
  BY_HANDLE_FILE_INFORMATION information;
  if (!GetFileInformationByHandle(handle, &information)) {
    return 0;
  }
  return (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 &&
    (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
}

static orbit_directory_handle_t *orbit_directory_open_windows_path(
  const uint8_t *path,
  int32_t length,
  int32_t *status
) {
  int32_t wide_length = 0;
  wchar_t *wide = orbit_directory_utf8_to_wide(path, length, &wide_length);
  (void)wide_length;
  if (wide == NULL) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  HANDLE handle = CreateFileW(
    wide,
    FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES | SYNCHRONIZE,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    NULL,
    OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
    NULL
  );
  free(wide);
  if (handle == INVALID_HANDLE_VALUE || !orbit_directory_handle_is_safe_directory(handle)) {
    if (handle != INVALID_HANDLE_VALUE) {
      CloseHandle(handle);
    }
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  orbit_directory_handle_t *directory = orbit_directory_wrap();
  directory->handle = handle;
  return directory;
}

static orbit_directory_handle_t *orbit_directory_open_windows_child(
  orbit_directory_handle_t *parent,
  const uint8_t *name,
  int32_t length,
  int32_t *status
) {
  if (!orbit_directory_is_valid_child_name(name, length)) {
    *status = ORBIT_DIRECTORY_STATUS_INVALID_CHILD_NAME;
    return NULL;
  }
  orbit_nt_create_file_fn create_file = NULL;
  orbit_nt_query_directory_file_fn query_directory = NULL;
  if (!orbit_directory_nt_functions(&create_file, &query_directory)) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  int32_t wide_length = 0;
  wchar_t *wide = orbit_directory_utf8_to_wide(name, length, &wide_length);
  if (wide == NULL || wide_length > 0x7fff / (int32_t)sizeof(wchar_t)) {
    free(wide);
    *status = ORBIT_DIRECTORY_STATUS_INVALID_CHILD_NAME;
    return NULL;
  }
  UNICODE_STRING object_name;
  object_name.Length = (USHORT)(wide_length * (int32_t)sizeof(wchar_t));
  object_name.MaximumLength = object_name.Length;
  object_name.Buffer = wide;
  OBJECT_ATTRIBUTES attributes;
  InitializeObjectAttributes(
    &attributes,
    &object_name,
    OBJ_CASE_INSENSITIVE | OBJ_DONT_REPARSE,
    (HANDLE)parent->handle,
    NULL
  );
  IO_STATUS_BLOCK io_status;
  HANDLE child = NULL;
  NTSTATUS result = create_file(
    &child,
    FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES | SYNCHRONIZE,
    &attributes,
    &io_status,
    NULL,
    0,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    FILE_OPEN,
    FILE_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT | FILE_OPEN_FOR_BACKUP_INTENT,
    NULL,
    0
  );
  free(wide);
  if (result < 0 || child == NULL || !orbit_directory_handle_is_safe_directory(child)) {
    if (child != NULL) {
      CloseHandle(child);
    }
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  orbit_directory_handle_t *directory = orbit_directory_wrap();
  directory->handle = child;
  return directory;
}

static orbit_read_file_handle_t *orbit_directory_open_windows_read_file(
  orbit_directory_handle_t *parent,
  const uint8_t *name,
  int32_t length,
  int32_t *status
) {
  if (!orbit_directory_is_valid_child_name(name, length)) {
    *status = ORBIT_DIRECTORY_STATUS_INVALID_CHILD_NAME;
    return NULL;
  }
  orbit_nt_create_file_fn create_file = NULL;
  orbit_nt_query_directory_file_fn query_directory = NULL;
  if (!orbit_directory_nt_functions(&create_file, &query_directory)) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  int32_t wide_length = 0;
  wchar_t *wide = orbit_directory_utf8_to_wide(name, length, &wide_length);
  if (wide == NULL || wide_length > 0x7fff / (int32_t)sizeof(wchar_t)) {
    free(wide);
    *status = ORBIT_DIRECTORY_STATUS_INVALID_CHILD_NAME;
    return NULL;
  }
  UNICODE_STRING object_name;
  object_name.Length = (USHORT)(wide_length * (int32_t)sizeof(wchar_t));
  object_name.MaximumLength = object_name.Length;
  object_name.Buffer = wide;
  OBJECT_ATTRIBUTES attributes;
  InitializeObjectAttributes(
    &attributes,
    &object_name,
    OBJ_CASE_INSENSITIVE | OBJ_DONT_REPARSE,
    (HANDLE)parent->handle,
    NULL
  );
  IO_STATUS_BLOCK io_status;
  HANDLE child = NULL;
  NTSTATUS result = create_file(
    &child,
    FILE_READ_DATA | FILE_READ_ATTRIBUTES | SYNCHRONIZE,
    &attributes,
    &io_status,
    NULL,
    0,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    FILE_OPEN,
    FILE_NON_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT |
      FILE_OPEN_FOR_BACKUP_INTENT,
    NULL,
    0
  );
  free(wide);
  if (result < 0 || child == NULL ||
      !orbit_directory_handle_is_safe_regular_file(child)) {
    if (child != NULL) {
      CloseHandle(child);
    }
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  orbit_read_file_handle_t *file = orbit_read_file_wrap();
  file->handle = child;
  return file;
}

static moonbit_bytes_t orbit_read_file_bytes_windows(
  orbit_read_file_handle_t *file,
  int32_t max_bytes,
  int32_t *status
) {
  LARGE_INTEGER size;
  if (!GetFileSizeEx((HANDLE)file->handle, &size) || size.QuadPart < 0) {
    *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
    return moonbit_make_bytes(0, 0);
  }
  if (size.QuadPart > max_bytes) {
    *status = ORBIT_DIRECTORY_STATUS_TOO_LARGE;
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)size.QuadPart, 0);
  LARGE_INTEGER origin;
  origin.QuadPart = 0;
  if (!SetFilePointerEx((HANDLE)file->handle, origin, NULL, FILE_BEGIN)) {
    *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
    return moonbit_make_bytes(0, 0);
  }
  size_t offset = 0;
  while (offset < (size_t)size.QuadPart) {
    DWORD read = 0;
    DWORD requested = (DWORD)((size_t)size.QuadPart - offset);
    if (!ReadFile((HANDLE)file->handle, bytes + offset, requested, &read, NULL) ||
        read == 0) {
      *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
      return moonbit_make_bytes(0, 0);
    }
    offset += read;
  }
  return bytes;
}

static int orbit_directory_append_windows_entry(
  orbit_directory_buffer_t *buffer,
  const orbit_file_directory_information_t *entry
) {
  if ((entry->FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0 ||
      (entry->FileAttributes & FILE_ATTRIBUTE_HIDDEN) != 0) {
    return 1;
  }
  if (entry->FileNameLength == 0 ||
      entry->FileNameLength > ORBIT_DIRECTORY_MAX_NAME_BYTES * sizeof(wchar_t) ||
      (entry->FileNameLength % sizeof(wchar_t)) != 0) {
    return 0;
  }
  size_t wide_length = entry->FileNameLength / sizeof(wchar_t);
  if ((wide_length == 1 && entry->FileName[0] == L'.') ||
      (wide_length == 2 && entry->FileName[0] == L'.' && entry->FileName[1] == L'.')) {
    return 1;
  }
  int utf8_length = WideCharToMultiByte(
    CP_UTF8,
    WC_ERR_INVALID_CHARS,
    entry->FileName,
    (int)wide_length,
    NULL,
    0,
    NULL,
    NULL
  );
  if (utf8_length <= 0 || utf8_length > ORBIT_DIRECTORY_MAX_NAME_BYTES) {
    return 0;
  }
  uint8_t utf8[ORBIT_DIRECTORY_MAX_NAME_BYTES];
  if (WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        entry->FileName,
        (int)wide_length,
        (char *)utf8,
        utf8_length,
        NULL,
        NULL
      ) != utf8_length) {
    return 0;
  }
  if (orbit_directory_is_hidden_name((const char *)utf8, (size_t)utf8_length)) {
    return 1;
  }
  if (buffer->count >= ORBIT_DIRECTORY_MAX_ENTRIES) {
    return -1;
  }
  return orbit_directory_buffer_append_entry(
    buffer,
    (entry->FileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ? 2 : 1,
    utf8,
    (size_t)utf8_length
  );
}

static moonbit_bytes_t orbit_directory_entries_windows(
  orbit_directory_handle_t *directory,
  int32_t max_entries,
  int32_t *status
) {
  orbit_nt_create_file_fn create_file = NULL;
  orbit_nt_query_directory_file_fn query_directory = NULL;
  if (directory->handle == NULL ||
      !orbit_directory_nt_functions(&create_file, &query_directory)) {
    *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
    return moonbit_make_bytes(0, 0);
  }
  uint8_t query_buffer[64 * 1024];
  orbit_directory_buffer_t output = { 0 };
  if (!orbit_directory_buffer_append_u32(&output, 0)) {
    *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
    return moonbit_make_bytes(0, 0);
  }
  BOOLEAN restart = TRUE;
  for (;;) {
    IO_STATUS_BLOCK io_status;
    NTSTATUS result = query_directory(
      (HANDLE)directory->handle,
      NULL,
      NULL,
      NULL,
      &io_status,
      query_buffer,
      (ULONG)sizeof(query_buffer),
      ORBIT_FILE_DIRECTORY_INFORMATION,
      FALSE,
      NULL,
      restart
    );
    restart = FALSE;
    if (result == (NTSTATUS)0x80000006L) {
      break;
    }
    if (result < 0 || io_status.Information == 0 ||
        io_status.Information > sizeof(query_buffer)) {
      orbit_directory_buffer_free(&output);
      *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
      return moonbit_make_bytes(0, 0);
    }
    size_t offset = 0;
    for (;;) {
      if (offset + offsetof(orbit_file_directory_information_t, FileName) > io_status.Information) {
        orbit_directory_buffer_free(&output);
        *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
        return moonbit_make_bytes(0, 0);
      }
      orbit_file_directory_information_t *entry =
        (orbit_file_directory_information_t *)(query_buffer + offset);
      size_t entry_bytes =
        offsetof(orbit_file_directory_information_t, FileName) + entry->FileNameLength;
      if (entry_bytes > io_status.Information - offset) {
        orbit_directory_buffer_free(&output);
        *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
        return moonbit_make_bytes(0, 0);
      }
      int appended = orbit_directory_append_windows_entry(&output, entry);
      if (appended < 0 || output.count > max_entries) {
        orbit_directory_buffer_free(&output);
        *status = ORBIT_DIRECTORY_STATUS_TOO_LARGE;
        return moonbit_make_bytes(0, 0);
      }
      if (appended == 0) {
        orbit_directory_buffer_free(&output);
        *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
        return moonbit_make_bytes(0, 0);
      }
      if (entry->NextEntryOffset == 0) {
        break;
      }
      if (entry->NextEntryOffset < entry_bytes ||
          entry->NextEntryOffset > io_status.Information - offset) {
        orbit_directory_buffer_free(&output);
        *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
        return moonbit_make_bytes(0, 0);
      }
      offset += entry->NextEntryOffset;
    }
  }
  output.data[0] = (uint8_t)(output.count & 0xff);
  output.data[1] = (uint8_t)((output.count >> 8) & 0xff);
  output.data[2] = (uint8_t)((output.count >> 16) & 0xff);
  output.data[3] = (uint8_t)((output.count >> 24) & 0xff);
  moonbit_bytes_t bytes = orbit_directory_buffer_to_bytes(&output);
  orbit_directory_buffer_free(&output);
  return bytes;
}

#else

static orbit_directory_handle_t *orbit_directory_open_posix_path(
  const uint8_t *path,
  int32_t length,
  int32_t *status
) {
  if (path == NULL || length <= 0 || memchr(path, 0, (size_t)length) != NULL) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  char *terminated = (char *)malloc((size_t)length + 1);
  if (terminated == NULL) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  memcpy(terminated, path, (size_t)length);
  terminated[length] = '\0';
  int fd = open(terminated, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  free(terminated);
  if (fd < 0) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  orbit_directory_handle_t *directory = orbit_directory_wrap();
  directory->fd = fd;
  return directory;
}

static orbit_directory_handle_t *orbit_directory_open_posix_child(
  orbit_directory_handle_t *parent,
  const uint8_t *name,
  int32_t length,
  int32_t *status
) {
  if (!orbit_directory_is_valid_child_name(name, length)) {
    *status = ORBIT_DIRECTORY_STATUS_INVALID_CHILD_NAME;
    return NULL;
  }
  char terminated[ORBIT_DIRECTORY_MAX_NAME_BYTES + 1];
  memcpy(terminated, name, (size_t)length);
  terminated[length] = '\0';
  int fd = openat(
    parent->fd,
    terminated,
    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
  );
  if (fd < 0) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  orbit_directory_handle_t *directory = orbit_directory_wrap();
  directory->fd = fd;
  return directory;
}

static orbit_read_file_handle_t *orbit_directory_open_posix_read_file(
  orbit_directory_handle_t *parent,
  const uint8_t *name,
  int32_t length,
  int32_t *status
) {
  if (!orbit_directory_is_valid_child_name(name, length)) {
    *status = ORBIT_DIRECTORY_STATUS_INVALID_CHILD_NAME;
    return NULL;
  }
  char terminated[ORBIT_DIRECTORY_MAX_NAME_BYTES + 1];
  memcpy(terminated, name, (size_t)length);
  terminated[length] = '\0';
  int fd = openat(parent->fd, terminated, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  struct stat information;
  if (fstat(fd, &information) != 0 || !S_ISREG(information.st_mode)) {
    close(fd);
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  orbit_read_file_handle_t *file = orbit_read_file_wrap();
  file->fd = fd;
  return file;
}

static moonbit_bytes_t orbit_read_file_bytes_posix(
  orbit_read_file_handle_t *file,
  int32_t max_bytes,
  int32_t *status
) {
  struct stat information;
  if (fstat(file->fd, &information) != 0 || information.st_size < 0) {
    *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
    return moonbit_make_bytes(0, 0);
  }
  if (information.st_size > max_bytes) {
    *status = ORBIT_DIRECTORY_STATUS_TOO_LARGE;
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)information.st_size, 0);
  size_t offset = 0;
  while (offset < (size_t)information.st_size) {
    ssize_t read = pread(
      file->fd,
      bytes + offset,
      (size_t)information.st_size - offset,
      (off_t)offset
    );
    if (read <= 0) {
      *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
      return moonbit_make_bytes(0, 0);
    }
    offset += (size_t)read;
  }
  return bytes;
}

static void orbit_directory_close_posix_stream(DIR *stream) {
  /* `dup` shares the open-file description with the held capability. Reset its
     directory position before closing so later listings always begin at root. */
  rewinddir(stream);
  closedir(stream);
}

static moonbit_bytes_t orbit_directory_entries_posix(
  orbit_directory_handle_t *directory,
  int32_t max_entries,
  int32_t *status
) {
  if (directory->fd < 0) {
    *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
    return moonbit_make_bytes(0, 0);
  }
  int duplicate = dup(directory->fd);
  if (duplicate < 0) {
    *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
    return moonbit_make_bytes(0, 0);
  }
  DIR *stream = fdopendir(duplicate);
  if (stream == NULL) {
    close(duplicate);
    *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
    return moonbit_make_bytes(0, 0);
  }
  orbit_directory_buffer_t output = { 0 };
  if (!orbit_directory_buffer_append_u32(&output, 0)) {
    orbit_directory_close_posix_stream(stream);
    *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
    return moonbit_make_bytes(0, 0);
  }
  for (;;) {
    errno = 0;
    struct dirent *entry = readdir(stream);
    if (entry == NULL) {
      if (errno != 0) {
        orbit_directory_buffer_free(&output);
        orbit_directory_close_posix_stream(stream);
        *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
        return moonbit_make_bytes(0, 0);
      }
      break;
    }
    const char *name = entry->d_name;
    size_t name_length = strlen(name);
    if (orbit_directory_is_hidden_name(name, name_length)) {
      continue;
    }
    if (name_length == 0 || name_length > ORBIT_DIRECTORY_MAX_NAME_BYTES) {
      orbit_directory_buffer_free(&output);
      orbit_directory_close_posix_stream(stream);
      *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
      return moonbit_make_bytes(0, 0);
    }
    struct stat information;
    if (fstatat(directory->fd, name, &information, AT_SYMLINK_NOFOLLOW) != 0) {
      if (errno == ENOENT) {
        continue;
      }
      orbit_directory_buffer_free(&output);
      orbit_directory_close_posix_stream(stream);
      *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
      return moonbit_make_bytes(0, 0);
    }
    if (S_ISLNK(information.st_mode)) {
      continue;
    }
    if (output.count >= max_entries) {
      orbit_directory_buffer_free(&output);
      orbit_directory_close_posix_stream(stream);
      *status = ORBIT_DIRECTORY_STATUS_TOO_LARGE;
      return moonbit_make_bytes(0, 0);
    }
    if (!orbit_directory_buffer_append_entry(
          &output,
          S_ISDIR(information.st_mode) ? 2 : 1,
          (const uint8_t *)name,
          name_length
        )) {
      orbit_directory_buffer_free(&output);
      orbit_directory_close_posix_stream(stream);
      *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
      return moonbit_make_bytes(0, 0);
    }
  }
  orbit_directory_close_posix_stream(stream);
  output.data[0] = (uint8_t)(output.count & 0xff);
  output.data[1] = (uint8_t)((output.count >> 8) & 0xff);
  output.data[2] = (uint8_t)((output.count >> 16) & 0xff);
  output.data[3] = (uint8_t)((output.count >> 24) & 0xff);
  moonbit_bytes_t bytes = orbit_directory_buffer_to_bytes(&output);
  orbit_directory_buffer_free(&output);
  return bytes;
}

#endif

MOONBIT_FFI_EXPORT orbit_directory_handle_t *orbit_file_directory_open(
  moonbit_bytes_t path,
  int32_t *status
) {
  *status = ORBIT_DIRECTORY_STATUS_OK;
  int32_t length = Moonbit_array_length(path);
#if defined(_WIN32)
  return orbit_directory_open_windows_path(path, length, status);
#else
  return orbit_directory_open_posix_path(path, length, status);
#endif
}

MOONBIT_FFI_EXPORT void orbit_file_directory_close(orbit_directory_handle_t *directory) {
  if (directory != NULL) {
    orbit_directory_finalize(directory);
  }
}

MOONBIT_FFI_EXPORT orbit_directory_handle_t *orbit_file_directory_open_child(
  orbit_directory_handle_t *directory,
  moonbit_bytes_t name,
  int32_t *status
) {
  *status = ORBIT_DIRECTORY_STATUS_OK;
  if (directory == NULL) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  int32_t length = Moonbit_array_length(name);
#if defined(_WIN32)
  if (directory->handle == NULL) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  return orbit_directory_open_windows_child(directory, name, length, status);
#else
  if (directory->fd < 0) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  return orbit_directory_open_posix_child(directory, name, length, status);
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t orbit_file_directory_entries(
  orbit_directory_handle_t *directory,
  int32_t max_entries,
  int32_t *status
) {
  *status = ORBIT_DIRECTORY_STATUS_OK;
  if (directory == NULL || max_entries < 1 || max_entries > ORBIT_DIRECTORY_MAX_ENTRIES) {
    *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
    return moonbit_make_bytes(0, 0);
  }
#if defined(_WIN32)
  return orbit_directory_entries_windows(directory, max_entries, status);
#else
  return orbit_directory_entries_posix(directory, max_entries, status);
#endif
}

MOONBIT_FFI_EXPORT orbit_read_file_handle_t *orbit_file_directory_open_read_file(
  orbit_directory_handle_t *directory,
  moonbit_bytes_t name,
  int32_t *status
) {
  *status = ORBIT_DIRECTORY_STATUS_OK;
  if (directory == NULL) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  int32_t length = Moonbit_array_length(name);
#if defined(_WIN32)
  if (directory->handle == NULL) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  return orbit_directory_open_windows_read_file(directory, name, length, status);
#else
  if (directory->fd < 0) {
    *status = ORBIT_DIRECTORY_STATUS_OPEN_FAILED;
    return NULL;
  }
  return orbit_directory_open_posix_read_file(directory, name, length, status);
#endif
}

MOONBIT_FFI_EXPORT void orbit_file_read_file_close(orbit_read_file_handle_t *file) {
  if (file != NULL) {
    orbit_read_file_finalize(file);
  }
}

MOONBIT_FFI_EXPORT moonbit_bytes_t orbit_file_read_file_bytes(
  orbit_read_file_handle_t *file,
  int32_t max_bytes,
  int32_t *status
) {
  *status = ORBIT_DIRECTORY_STATUS_OK;
  if (file == NULL || max_bytes < 0) {
    *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
    return moonbit_make_bytes(0, 0);
  }
#if defined(_WIN32)
  if (file->handle == NULL) {
    *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
    return moonbit_make_bytes(0, 0);
  }
  return orbit_read_file_bytes_windows(file, max_bytes, status);
#else
  if (file->fd < 0) {
    *status = ORBIT_DIRECTORY_STATUS_READ_FAILED;
    return moonbit_make_bytes(0, 0);
  }
  return orbit_read_file_bytes_posix(file, max_bytes, status);
#endif
}
