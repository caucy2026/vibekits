$ErrorActionPreference = 'Stop'

$credential = Join-Path $env:LOCALAPPDATA 'Vibekits\Harness\.credentials.yaml'
if (-not (Test-Path -LiteralPath $credential)) { throw 'HARNESS_NO_CREDENTIAL_FILE' }
$line = Get-Content -LiteralPath $credential | Where-Object { $_ -match '^\s*DEEPSEEK_API_KEY\s*:' } | Select-Object -First 1
if (-not $line) { throw 'HARNESS_NO_SAVED_KEY' }
$key = ($line -replace '^\s*DEEPSEEK_API_KEY\s*:\s*', '').Trim().Trim('"').Trim("'")
if ([string]::IsNullOrWhiteSpace($key)) { throw 'HARNESS_NO_SAVED_KEY' }
$env:DEEPSEEK_API_KEY = $key
try {
  & "$PSScriptRoot\..\native\harness\windows\runtime\node.exe" "$PSScriptRoot\harness_network_vm_web_smoke.mjs"
  if ($LASTEXITCODE -ne 0) { throw "HARNESS_NETWORK_VM_WEB_EXIT_$LASTEXITCODE" }
} finally {
  Remove-Item Env:DEEPSEEK_API_KEY -ErrorAction SilentlyContinue
  $key = $null
  $line = $null
}
