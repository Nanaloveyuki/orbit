$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $PSScriptRoot "orbit-plugin-fixture.dll"
$orderLog = Join-Path $root "orbit-plugin-fixture-order.log"
$header = Join-Path $root ".mooncakes\Nanaloveyuki\orbit-plugin-abi\include"

Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $orderLog -Force -ErrorAction SilentlyContinue
$compiler = Get-Command cl.exe -ErrorAction SilentlyContinue
if ($null -ne $compiler) {
  & $compiler.Source /nologo /LD /I $header /Fe:$fixture (Join-Path $PSScriptRoot "fixture.c") | Out-Host
} else {
  $compiler = Get-Command clang.exe -ErrorAction Stop
  & $compiler.Source -shared -I $header -o $fixture (Join-Path $PSScriptRoot "fixture.c") | Out-Host
}
if ($LASTEXITCODE -ne 0) {
  throw "failed to compile plugin fixture"
}
moon -C $root run --target native orbit-plugin-fixtures $fixture

$env:ORBIT_PLUGIN_FIXTURE_MODE = "create_fail"
moon -C $root run --target native orbit-plugin-fixtures $fixture create-failure
Remove-Item Env:ORBIT_PLUGIN_FIXTURE_MODE

$events = Get-Content -LiteralPath $orderLog
if (($events -join ",") -ne "destroy,unload-after-destroy") {
  throw "unexpected plugin teardown order: $($events -join ',')"
}

Write-Output "plugin fixture integration passed"
