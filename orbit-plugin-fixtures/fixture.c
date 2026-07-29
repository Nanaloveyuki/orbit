#define _CRT_SECURE_NO_WARNINGS

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <windows.h>

#include "orbit_plugin_abi.h"

typedef struct FixtureInstance {
  const OrbitHostV1 *host;
} FixtureInstance;

static int destroyed = 0;
static int created = 0;

static void append_order(const char *entry) {
  FILE *file = fopen("orbit-plugin-fixture-order.log", "ab");
  if (file != NULL) {
    fputs(entry, file);
    fputc('\n', file);
    fclose(file);
  }
}

BOOL WINAPI DllMain(void *module, unsigned long reason, void *reserved) {
  (void)module;
  (void)reserved;
  if (reason == 0 && created) {
    append_order(destroyed ? "unload-after-destroy" : "unload-before-destroy");
  }
  return 1;
}

__declspec(dllexport) uint32_t orbit_plugin_abi_version(void) {
  return ORBIT_PLUGIN_ABI_VERSION_V1;
}

__declspec(dllexport) const char *orbit_plugin_manifest_json(void) {
  return "{\"id\":\"fixture.echo\",\"name\":\"Orbit fixture\",\"version\":\"1\",\"commands\":[\"echo\",\"fail\"],\"permissions\":[\"test.invoke\"]}";
}

__declspec(dllexport) int32_t orbit_plugin_create(
    const OrbitHostV1 *host,
    void **out_instance) {
  if (host == NULL || out_instance == NULL) return -1;
  FixtureInstance *instance = host->alloc(sizeof(FixtureInstance));
  if (instance == NULL) return -2;
  instance->host = host;
  created = 1;
  *out_instance = instance;
  return 0;
}

__declspec(dllexport) int32_t orbit_plugin_invoke(
    void *raw_instance,
    const char *command,
    const uint8_t *request,
    uint32_t request_len,
    OrbitBuffer *out_response) {
  FixtureInstance *instance = raw_instance;
  if (instance == NULL || command == NULL || out_response == NULL) return -3;
  if (strcmp(command, "fail") == 0) return -42;
  if (strcmp(command, "echo") != 0) return -4;
  uint8_t *response = instance->host->alloc(request_len);
  if (response == NULL && request_len != 0) return -5;
  if (request_len != 0) memcpy(response, request, request_len);
  out_response->data = response;
  out_response->len = request_len;
  return 0;
}

__declspec(dllexport) void orbit_plugin_destroy(void *raw_instance) {
  FixtureInstance *instance = raw_instance;
  if (instance != NULL) {
    destroyed = 1;
    append_order("destroy");
    instance->host->free(instance);
  }
}
