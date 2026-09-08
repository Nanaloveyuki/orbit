#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <moonbit.h>

_Noreturn void moonbit_panic(void) { abort(); }

static int live_buffers;
static int read_fault;
static moonbit_bytes_t tracked_bytes(int32_t size, int value) {
  live_buffers++;
  return moonbit_make_bytes(size, value);
}
static void tracked_drop(void *bytes) {
  live_buffers--;
  moonbit_decref(bytes);
}
static ssize_t test_pread(int fd, void *data, size_t length, off_t offset) {
  int fault = read_fault;
  read_fault = 0;
  if (fault == 1) return 0;
  if (fault == 2 || fault == 3) {
    errno = fault == 2 ? EIO : EINTR;
    return -1;
  }
  return pread(fd, data, length, offset);
}

/* Exercise production code with deterministic read faults and allocation counts. */
#define moonbit_make_bytes tracked_bytes
#define moonbit_decref tracked_drop
#define pread test_pread
#include "../secure_directory.c"
#undef moonbit_make_bytes
#undef moonbit_decref
#undef pread

int main(void) {
  alarm(10);
  char root[] = "/tmp/orbit-directory-test-XXXXXX";
  assert(mkdtemp(root) != NULL);
  orbit_directory_handle_t directory = { .fd = open(root, O_RDONLY | O_DIRECTORY) };
  assert(directory.fd >= 0);
  assert(mkfifoat(directory.fd, "pipe", 0600) == 0);
  int32_t status = 0;
  assert(orbit_directory_open_posix_read_file(&directory, (const uint8_t *)"pipe", 4, &status) == NULL);
  assert(status == ORBIT_DIRECTORY_STATUS_OPEN_FAILED);
  status = 0;
  moonbit_bytes_t entries = orbit_directory_entries_posix(&directory, 128, &status);
  assert(status == 0 && Moonbit_array_length(entries) == 4 && entries[0] == 0);
  tracked_drop(entries);

  int fd = openat(directory.fd, "regular", O_RDWR | O_CREAT | O_EXCL, 0600);
  assert(fd >= 0 && write(fd, "data", 4) == 4);
  orbit_read_file_handle_t file = { .fd = fd };
  for (int fault = 0; fault <= 3; fault++) {
    status = 0;
    read_fault = fault;
    moonbit_bytes_t bytes = orbit_read_file_bytes_posix(&file, 64, &status);
    if (fault == 1 || fault == 2) {
      assert(status == ORBIT_DIRECTORY_STATUS_READ_FAILED);
      assert(Moonbit_array_length(bytes) == 0);
    } else {
      assert(status == 0 && Moonbit_array_length(bytes) == 4);
      assert(memcmp(bytes, "data", 4) == 0);
    }
    tracked_drop(bytes);
    assert(live_buffers == 0);
  }
  close(fd);
  assert(unlinkat(directory.fd, "pipe", 0) == 0);
  assert(unlinkat(directory.fd, "regular", 0) == 0);
  close(directory.fd);
  assert(rmdir(root) == 0);
  puts("secure directory: FIFO, listing, EOF, EIO, EINTR, and allocation balance passed");
  return 0;
}
