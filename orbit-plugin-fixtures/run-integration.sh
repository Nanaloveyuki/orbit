#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$root/orbit-plugin-fixtures/orbit-plugin-fixture-v2.so"
header="$root/.mooncakes/Nanaloveyuki/orbit-plugin-abi/include"

cc -shared -fPIC -I "$header" \
  -o "$fixture" "$root/orbit-plugin-fixtures/fixture_v2.c"
moon -C "$root" run --target native orbit-plugin-fixtures "$fixture" v2

printf '%s\n' "ABI v2 plugin fixture integration passed"
