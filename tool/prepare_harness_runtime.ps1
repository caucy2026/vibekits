param(
  [string]$NodeDirectory = "C:\Program Files\nodejs",
  [string]$OutputDirectory = "native\harness\windows\runtime",
  [string]$PackageVersion = "0.1.1-rc.2"
)

$ErrorActionPreference = 'Stop'
$packageVersion = $PackageVersion.Trim()
if ($packageVersion -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
  throw "Invalid Harness package version: $PackageVersion"
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$target = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
  $OutputDirectory
} else {
  Join-Path $projectRoot $OutputDirectory
}
$stagingRoot = Join-Path $projectRoot '.tmp\harness-runtime-staging'
$staging = Join-Path $stagingRoot "vibekits-harness-$packageVersion"
$npmCache = Join-Path $projectRoot '.tmp\npm-cache-harness'

if (-not (Test-Path -LiteralPath (Join-Path $NodeDirectory 'node.exe'))) {
  throw "Node.js 24 LTS not found at $NodeDirectory"
}

if (Test-Path -LiteralPath $staging) {
  Remove-Item -LiteralPath $staging -Recurse -Force
}
New-Item -ItemType Directory -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $npmCache | Out-Null

Push-Location $staging
try {
  & (Join-Path $NodeDirectory 'npm.cmd') init --yes | Out-Null
  # DSH is still a release candidate. Its published package family currently
  # contains peer metadata that makes npm's strict resolver spend minutes
  # backtracking. The runtime is pinned as one tested wave, so legacy peer
  # resolution is deterministic and avoids that startup-independent stall.
  & (Join-Path $NodeDirectory 'npm.cmd') install --omit=dev --ignore-scripts --legacy-peer-deps --no-audit --no-fund "@deepseek-ai/dsh@$packageVersion" --registry=https://registry.npmjs.org --cache=$npmCache --fetch-timeout=30000 --fetch-retries=1 --loglevel=warn
  if ($LASTEXITCODE -ne 0) { throw 'Harness npm install failed' }

  # npm's legacy resolver avoids pathological backtracking in the rc package
  # wave, but it intentionally omits required peers. Materialize those peers
  # explicitly and repeat because a newly installed peer can declare another
  # required peer of its own.
  $peerSpecs = @()
  for ($pass = 0; $pass -lt 6; $pass++) {
    $peerJson = & (Join-Path $NodeDirectory 'node.exe') (Join-Path $projectRoot 'tool\list_harness_required_peers.mjs') (Join-Path $staging 'node_modules')
    if ($LASTEXITCODE -ne 0) { throw 'Harness peer dependency scan failed' }
    $peerSpecs = @($peerJson | ConvertFrom-Json)
    if ($peerSpecs.Count -eq 0) { break }
    & (Join-Path $NodeDirectory 'npm.cmd') install --omit=dev --ignore-scripts --legacy-peer-deps --no-audit --no-fund @peerSpecs --registry=https://registry.npmjs.org --cache=$npmCache --fetch-timeout=30000 --fetch-retries=1 --loglevel=warn
    if ($LASTEXITCODE -ne 0) { throw 'Harness required peer install failed' }
  }
  if ($peerSpecs.Count -ne 0) {
    throw 'Harness required peer installation did not converge'
  }
} finally {
  Pop-Location
}

$packageJsonPath = Join-Path $staging 'node_modules\@deepseek-ai\dsh\package.json'
$packageJson = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
$binValue = if ($packageJson.bin -is [string]) { $packageJson.bin } else { $packageJson.bin.dsh }
if (-not $binValue) { throw 'Official dsh package does not expose a dsh CLI entry' }
$cliRelative = "node_modules/@deepseek-ai/dsh/$($binValue -replace '\\','/')"

if (Test-Path -LiteralPath $target) {
  Remove-Item -LiteralPath $target -Recurse -Force
}
New-Item -ItemType Directory -Path $target | Out-Null
New-Item -ItemType Directory -Path (Join-Path $target 'profile') | Out-Null
Copy-Item -LiteralPath (Join-Path $NodeDirectory 'node.exe') -Destination $target
Copy-Item -LiteralPath (Join-Path $staging 'node_modules') -Destination $target -Recurse
Copy-Item -LiteralPath (Join-Path $projectRoot 'native\harness\vibekits-mcp-server.mjs') -Destination $target
Copy-Item -LiteralPath (Join-Path $projectRoot 'native\harness\vibekits-codex-mcp.mjs') -Destination $target
Copy-Item -LiteralPath (Join-Path $projectRoot 'native\harness\vibekits-approval.mjs') -Destination $target
Copy-Item -LiteralPath (Join-Path $projectRoot 'native\harness\vibekits-android-stress-mcp.mjs') -Destination $target

& (Join-Path $target 'node.exe') (Join-Path $projectRoot 'tool\patch_harness_runtime.mjs') $target
if ($LASTEXITCODE -ne 0) { throw 'Harness Web compatibility patch failed' }

# Prime Node's portable compile cache at build time. New installations can
# seed this small cache before their first DSH launch instead of compiling the
# complete official plugin graph while the user watches a 20-50 second loader.
$profile = Join-Path $target 'profile'
$compileCache = Join-Path $profile 'node-compile-cache'
New-Item -ItemType Directory -Force -Path $compileCache | Out-Null
@'
- id: llm-pi-ai
  disabled: true
- id: session-telemetry-otel
  disabled: true
- id: client-hmr
  disabled: true
'@ | Set-Content -LiteralPath (Join-Path $profile 'cordis.patch.yml') -Encoding utf8
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$prewarmPort = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()
$prewarm = [System.Diagnostics.ProcessStartInfo]::new()
$prewarm.FileName = Join-Path $target 'node.exe'
$prewarm.Arguments = '"' + (Join-Path $target ($cliRelative -replace '/', '\')) + '" web --port ' + $prewarmPort + ' --no-open'
$prewarm.WorkingDirectory = $projectRoot
$prewarm.UseShellExecute = $false
$prewarm.CreateNoWindow = $true
$prewarm.RedirectStandardOutput = $true
$prewarm.RedirectStandardError = $true
$prewarm.EnvironmentVariables['DSH_HOME'] = $profile
$prewarm.EnvironmentVariables['NODE_COMPILE_CACHE'] = $compileCache
$prewarm.EnvironmentVariables['NODE_COMPILE_CACHE_PORTABLE'] = '1'
$prewarm.EnvironmentVariables['DSH_TELEMETRY_MODE'] = 'DISABLED'
$prewarm.EnvironmentVariables['DSH_TELEMETRY_DISABLED'] = '1'
$prewarmProcess = [System.Diagnostics.Process]::Start($prewarm)
$prewarmReady = $false
try {
  $prewarmDeadline = [DateTime]::UtcNow.AddSeconds(90)
  while ([DateTime]::UtcNow -lt $prewarmDeadline -and -not $prewarmProcess.HasExited) {
    try {
      $client = [System.Net.Sockets.TcpClient]::new()
      $connect = $client.ConnectAsync('127.0.0.1', $prewarmPort)
      if ($connect.Wait(300) -and $client.Connected) {
        $prewarmReady = $true
        $client.Dispose()
        break
      }
      $client.Dispose()
    } catch {}
    Start-Sleep -Milliseconds 200
  }
} finally {
  if (-not $prewarmProcess.HasExited) {
    & taskkill.exe /PID $prewarmProcess.Id /T /F 2>$null | Out-Null
    $prewarmProcess.WaitForExit(5000) | Out-Null
  }
}
if (-not $prewarmReady) {
  $prewarmError = $prewarmProcess.StandardError.ReadToEnd()
  throw "Harness build-time prewarm failed: $prewarmError"
}
Get-ChildItem -LiteralPath $profile -Force | Where-Object {
  $_.Name -ne 'node-compile-cache'
} | Remove-Item -Recurse -Force

@{
  version = "@deepseek-ai/dsh@$packageVersion"
  cli = $cliRelative
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $target 'harness-runtime.json') -Encoding utf8

Write-Host "Prepared Harness runtime: $target"
