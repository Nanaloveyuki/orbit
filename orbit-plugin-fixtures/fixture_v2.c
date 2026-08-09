#define _CRT_SECURE_NO_WARNINGS

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "orbit_plugin_abi.h"

#ifdef _WIN32
#define ORBIT_FIXTURE_EXPORT __declspec(dllexport)
#else
#define ORBIT_FIXTURE_EXPORT __attribute__((visibility("default")))
#endif

typedef struct FixtureV2Instance {
  const OrbitHostV2 *host;
} FixtureV2Instance;

ORBIT_FIXTURE_EXPORT uint32_t orbit_plugin_abi_version(void) {
  return ORBIT_PLUGIN_ABI_VERSION_V2;
}

ORBIT_FIXTURE_EXPORT const char *orbit_plugin_manifest_json(void) {
  return "{\"id\":\"fixture.v2\",\"name\":\"Orbit v2 fixture\",\"version\":\"1\",\"commands\":[\"host_success\",\"host_denied\",\"host_cancel\",\"host_reentrant\"],\"permissions\":[\"test.invoke\"]}";
}

ORBIT_FIXTURE_EXPORT int32_t orbit_plugin_create(
    const OrbitHostV2 *host,
    void **out_instance) {
  FixtureV2Instance *instance;
  if (host == NULL || out_instance == NULL ||
      host->abi_version != ORBIT_PLUGIN_ABI_VERSION_V2 ||
      host->struct_size < sizeof(OrbitHostV2) ||
      (host->flags & ORBIT_HOST_V2_FLAG_REQUEST) == 0 ||
      host->request == NULL) {
    return -1;
  }
  instance = host->alloc(sizeof(FixtureV2Instance));
  if (instance == NULL) return -2;
  instance->host = host;
  *out_instance = instance;
  return 0;
}

ORBIT_FIXTURE_EXPORT int32_t orbit_plugin_invoke(
    void *raw_instance,
    const char *command,
    const uint8_t *request,
    uint32_t request_len,
    OrbitBuffer *out_response) {
  FixtureV2Instance *instance = raw_instance;
  const char *host_command;
  if (instance == NULL || command == NULL || out_response == NULL) return -3;
  if (strcmp(command, "host_success") == 0) {
    host_command = "app:echo";
  } else if (strcmp(command, "host_denied") == 0) {
    host_command = "app:denied";
  } else if (strcmp(command, "host_cancel") == 0) {
    host_command = "app:wait";
  } else if (strcmp(command, "host_reentrant") == 0) {
    host_command = "app:alias";
  } else {
    return -4;
  }
  return instance->host->request(
      instance->host->host_context,
      (const uint8_t *)host_command,
      (uint32_t)strlen(host_command),
      request,
      request_len,
      strcmp(command, "host_cancel") == 0 ? 0 : 5000,
      out_response);
}

ORBIT_FIXTURE_EXPORT void orbit_plugin_destroy(void *raw_instance) {
  FixtureV2Instance *instance = raw_instance;
  if (instance != NULL) instance->host->free(instance);
}
