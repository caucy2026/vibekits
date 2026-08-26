$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$credential = Join-Path $env:LOCALAPPDATA 'Vibekits\Harness\.credentials.yaml'
$line = Get-Content -LiteralPath $credential | Where-Object { $_ -match '^\s*DEEPSEEK_API_KEY\s*:' } | Select-Object -First 1
if (-not $line) { throw 'HARNESS_NO_SAVED_KEY' }
$key = ($line -replace '^\s*DEEPSEEK_API_KEY\s*:\s*', '').Trim().Trim('"').Trim("'")
if ([string]::IsNullOrWhiteSpace($key)) { throw 'HARNESS_NO_SAVED_KEY' }
$workspace = Join-Path $root 'build\acceptance\harness-web-search-workspace'
New-Item -ItemType Directory -Force -Path $workspace | Out-Null
$env:DEEPSEEK_API_KEY = $key
try {
  Push-Location $workspace
  $ErrorActionPreference = 'Continue'
  $output = & (Join-Path $root 'native\harness\windows\runtime\node.exe') (Join-Path $PSScriptRoot 'harness_network_vm_web_smoke.mjs') --web-only 2>&1
  $ErrorActionPreference = 'Stop'
  $text = $output -join "`n"
  $text
  if ($LASTEXITCODE -ne 0 -or $text -notmatch 'VIBEKITS_HARNESS_WEB_SEARCH_OK' -or $text -notmatch 'qemu\.org') {
    throw "HARNESS_WEB_SEARCH_FAILED_$LASTEXITCODE"
  }
  'HARNESS_WEB_SEARCH_SMOKE_PASSED'
} finally {
  Pop-Location -ErrorAction SilentlyContinue
  Remove-Item Env:DEEPSEEK_API_KEY -ErrorAction SilentlyContinue
  $key = $null
  $line = $null
}
