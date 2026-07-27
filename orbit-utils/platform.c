#include <moonbit.h>

#include <stdint.h>

MOONBIT_FFI_EXPORT int32_t orbit_current_platform(void) {
#if defined(_WIN32)
  return 1;
#elif defined(__ANDROID__)
  return 4;
#elif defined(__OHOS__)
  return 5;
#elif defined(__APPLE__)
  return 3;
#elif defined(__linux__)
  return 2;
#else
  return 0;
#endif
}
