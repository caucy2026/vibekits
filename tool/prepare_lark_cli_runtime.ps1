param(
  [string]$SourceRoot = '',
  [string]$GoExecutable = '',
  [string]$PythonExecutable = 'D:\Python312\python.exe',
  [string]$ExpectedVersion = '1.0.92'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$workspaceParent = Split-Path -Parent $projectRoot
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
  $SourceRoot = Join-Path $workspaceParent 'upstream\larksuite-cli'
}
if ([string]::IsNullOrWhiteSpace($GoExecutable)) {
  $GoExecutable = Join-Path $projectRoot '.cache\go-sdk\go\bin\go.exe'
}
$target = Join-Path $projectRoot 'native\lark_cli\windows\runtime'
$binary = Join-Path $target 'lark-cli.exe'
$cacheRoot = Join-Path $projectRoot '.cache'
$packageManifest = Join-Path $SourceRoot 'package.json'

if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot 'go.mod'))) {
  throw "Official larksuite/cli source is missing: $SourceRoot"
}
if (-not (Test-Path -LiteralPath $GoExecutable)) {
  throw "D-drive Go toolchain is missing: $GoExecutable"
}
if (-not (Test-Path -LiteralPath $PythonExecutable)) {
  throw "Python is missing: $PythonExecutable"
}
$packageVersion = (Get-Content -LiteralPath $packageManifest -Raw | ConvertFrom-Json).version
if ($packageVersion -ne $ExpectedVersion) {
  throw "Lark CLI source version mismatch: expected $ExpectedVersion, found $packageVersion"
}

New-Item -ItemType Directory -Force -Path $target | Out-Null
$env:GOCACHE = Join-Path $cacheRoot 'go-build'
$env:GOMODCACHE = Join-Path $cacheRoot 'go-mod'
$env:GOPATH = Join-Path $cacheRoot 'go-path'
$env:GOPROXY = 'https://goproxy.cn,direct'
$env:GOSUMDB = 'sum.golang.org'

Push-Location $SourceRoot
try {
  & $PythonExecutable scripts\fetch_meta.py --force
  if ($LASTEXITCODE -ne 0) { throw "lark-cli metadata fetch failed: $LASTEXITCODE" }
  $buildDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  $ldflags = "-s -w -X github.com/larksuite/cli/internal/build.Version=$packageVersion -X github.com/larksuite/cli/internal/build.Date=$buildDate"
  & $GoExecutable build -buildvcs=false -trimpath -ldflags $ldflags -o $binary .
  if ($LASTEXITCODE -ne 0) { throw "lark-cli build failed: $LASTEXITCODE" }
} finally {
  Pop-Location
}

$versionOutput = (& $binary --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch [regex]::Escape($ExpectedVersion)) {
  throw "lark-cli version smoke test failed: $versionOutput"
}
Write-Host "Prepared official lark-cli runtime: $binary"
