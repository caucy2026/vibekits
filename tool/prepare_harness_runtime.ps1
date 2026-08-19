param(
  [string]$NodeDirectory = "C:\Program Files\nodejs",
  [string]$OutputDirectory = "native\harness\windows\runtime"
)

$ErrorActionPreference = 'Stop'
$packageVersion = '0.1.0-rc.7'
$projectRoot = Split-Path -Parent $PSScriptRoot
$target = Join-Path $projectRoot $OutputDirectory
$staging = Join-Path ([System.IO.Path]::GetTempPath()) "vibekits-harness-$packageVersion"

if (-not (Test-Path -LiteralPath (Join-Path $NodeDirectory 'node.exe'))) {
  throw "Node.js 24 LTS not found at $NodeDirectory"
}

if (Test-Path -LiteralPath $staging) {
  Remove-Item -LiteralPath $staging -Recurse -Force
}
New-Item -ItemType Directory -Path $staging | Out-Null

Push-Location $staging
try {
  & (Join-Path $NodeDirectory 'npm.cmd') init --yes | Out-Null
  & (Join-Path $NodeDirectory 'npm.cmd') install --omit=dev --ignore-scripts --no-audit --no-fund "@deepseek-ai/dsh@$packageVersion"
  if ($LASTEXITCODE -ne 0) { throw 'Harness npm install failed' }
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
Copy-Item -LiteralPath (Join-Path $projectRoot 'native\harness\vibekits-approval.mjs') -Destination $target

& (Join-Path $target 'node.exe') (Join-Path $projectRoot 'tool\patch_harness_runtime.mjs') $target
if ($LASTEXITCODE -ne 0) { throw 'Harness Web compatibility patch failed' }

@{
  version = "@deepseek-ai/dsh@$packageVersion"
  cli = $cliRelative
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $target 'harness-runtime.json') -Encoding utf8

Write-Host "Prepared Harness runtime: $target"
