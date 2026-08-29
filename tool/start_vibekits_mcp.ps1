param(
  [int]$BridgeWaitSeconds = 20
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeCandidates = @(
  $PSScriptRoot,
  (Join-Path $projectRoot 'build\windows\x64\runner\Release\tools\harness'),
  (Join-Path $projectRoot 'native\harness\windows\runtime')
)
$runtime = $runtimeCandidates | Where-Object {
  (Test-Path -LiteralPath (Join-Path $_ 'node.exe')) -and
  (Test-Path -LiteralPath (Join-Path $_ 'vibekits-mcp-server.mjs'))
} | Select-Object -First 1

if (-not $runtime) {
  [Console]::Error.WriteLine('VibeKits bundled MCP runtime is missing. Build or reinstall VibeKits first.')
  exit 2
}

$connectionFile = Join-Path $env:LOCALAPPDATA 'Vibekits\Mcp\tool-bridge.json'
function Test-VibekitsBridge {
  if (-not (Test-Path -LiteralPath $connectionFile)) { return $false }
  try {
    $connection = Get-Content -Raw -LiteralPath $connectionFile | ConvertFrom-Json
    $endpoint = [Uri]$connection.endpoint
    if ($endpoint.Scheme -ne 'http' -or $endpoint.Host -ne '127.0.0.1' -or
        [string]::IsNullOrWhiteSpace($connection.token)) {
      return $false
    }
    $headers = @{ Authorization = "Bearer $($connection.token)" }
    $null = Invoke-RestMethod -Uri "$($endpoint.AbsoluteUri.TrimEnd('/'))/catalog" -Headers $headers -TimeoutSec 2
    return $true
  } catch {
    return $false
  }
}

if (-not (Test-VibekitsBridge)) {
  if (Test-Path -LiteralPath $connectionFile) {
    Remove-Item -LiteralPath $connectionFile -Force
  }
  $appCandidates = @(
    (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'vibekits.exe'),
    (Join-Path $projectRoot 'build\windows\x64\runner\Release\vibekits.exe')
  )
  $app = $appCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not (Test-Path -LiteralPath $app)) {
    [Console]::Error.WriteLine('VibeKits is not running and the Release executable is missing.')
    exit 3
  }
  Start-Process -FilePath $app
  $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(1, $BridgeWaitSeconds))
  while (-not (Test-VibekitsBridge)) {
    if ([DateTime]::UtcNow -ge $deadline) {
      [Console]::Error.WriteLine('Timed out waiting for the VibeKits local MCP bridge.')
      exit 4
    }
    Start-Sleep -Milliseconds 100
  }
}

$node = Join-Path $runtime 'node.exe'
$server = Join-Path $runtime 'vibekits-mcp-server.mjs'
& $node $server --connection-file $connectionFile
exit $LASTEXITCODE
