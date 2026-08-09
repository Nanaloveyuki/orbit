$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $PSScriptRoot "orbit-plugin-fixture.dll"
$fixtureV2 = Join-Path $PSScriptRoot "orbit-plugin-fixture-v2.dll"
$orderLog = Join-Path $root "orbit-plugin-fixture-order.log"
$header = Join-Path $root ".mooncakes\Nanaloveyuki\orbit-plugin-abi\include"

Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $fixtureV2 -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $orderLog -Force -ErrorAction SilentlyContinue
$compiler = Get-Command cl.exe -ErrorAction SilentlyContinue
if ($null -ne $compiler) {
  & $compiler.Source /nologo /LD /I $header /Fe:$fixture (Join-Path $PSScriptRoot "fixture.c") | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "failed to compile ABI v1 plugin fixture"
  }
  & $compiler.Source /nologo /LD /I $header /Fe:$fixtureV2 (Join-Path $PSScriptRoot "fixture_v2.c") | Out-Host
} else {
  $compiler = Get-Command clang.exe -ErrorAction Stop
  & $compiler.Source -shared -I $header -o $fixture (Join-Path $PSScriptRoot "fixture.c") | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "failed to compile ABI v1 plugin fixture"
  }
  & $compiler.Source -shared -I $header -o $fixtureV2 (Join-Path $PSScriptRoot "fixture_v2.c") | Out-Host
}
if ($LASTEXITCODE -ne 0) {
  throw "failed to compile ABI v2 plugin fixture"
}
moon -C $root run --target native orbit-plugin-fixtures $fixture
if ($LASTEXITCODE -ne 0) {
  throw "ABI v1 plugin fixture failed"
}
moon -C $root run --target native orbit-plugin-fixtures $fixtureV2 v2
if ($LASTEXITCODE -ne 0) {
  throw "ABI v2 plugin fixture failed"
}
moon -C $root run --target native orbit-plugin-fixtures $fixtureV2 core-v2
if ($LASTEXITCODE -ne 0) {
  throw "ABI v2 orbit-core fixture failed"
}

$env:ORBIT_PLUGIN_FIXTURE_MODE = "create_fail"
moon -C $root run --target native orbit-plugin-fixtures $fixture create-failure
if ($LASTEXITCODE -ne 0) {
  throw "plugin create-failure fixture failed"
}
Remove-Item Env:ORBIT_PLUGIN_FIXTURE_MODE

$events = Get-Content -LiteralPath $orderLog
if (($events -join ",") -ne "destroy,unload-after-destroy") {
  throw "unexpected plugin teardown order: $($events -join ',')"
}

Write-Output "plugin fixture integration passed"
