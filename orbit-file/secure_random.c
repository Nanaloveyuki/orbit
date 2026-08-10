#include <moonbit.h>

#include <stdint.h>

#if defined(_WIN32)
#include <windows.h>
#include <bcrypt.h>

#pragma comment(lib, "bcrypt.lib")
#elif defined(__linux__)
#include <errno.h>
#include <sys/random.h>
#elif defined(__APPLE__)
#include <stdlib.h>
#endif

MOONBIT_FFI_EXPORT int32_t orbit_file_secure_random_fill(void *buffer) {
  const int32_t size = 16;
#if defined(_WIN32)
  return BCryptGenRandom(NULL, (PUCHAR)buffer, (ULONG)size,
                         BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0;
#elif defined(__linux__)
  uint8_t *cursor = (uint8_t *)buffer;
  int32_t remaining = size;
  while (remaining > 0) {
    const ssize_t received = getrandom(cursor, (size_t)remaining, 0);
    if (received < 0) {
      if (errno == EINTR) continue;
      return 0;
    }
    if (received == 0) return 0;
    cursor += received;
    remaining -= (int32_t)received;
  }
  return 1;
#elif defined(__APPLE__)
  arc4random_buf(buffer, (size_t)size);
  return 1;
#else
  (void)buffer;
  return 0;
#endif
}
