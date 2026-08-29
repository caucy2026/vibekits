param(
  [string]$SourceRoot = '',
  [string]$GoExecutable = '',
  [string]$PythonExecutable = 'D:\Python312\python.exe'
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

if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot 'go.mod'))) {
  throw "Official larksuite/cli source is missing: $SourceRoot"
}
if (-not (Test-Path -LiteralPath $GoExecutable)) {
  throw "D-drive Go toolchain is missing: $GoExecutable"
}
if (-not (Test-Path -LiteralPath $PythonExecutable)) {
  throw "Python is missing: $PythonExecutable"
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
  & $GoExecutable build -trimpath -o $binary .
  if ($LASTEXITCODE -ne 0) { throw "lark-cli build failed: $LASTEXITCODE" }
} finally {
  Pop-Location
}

& $binary --version
if ($LASTEXITCODE -ne 0) { throw 'lark-cli version smoke test failed' }
Write-Host "Prepared official lark-cli runtime: $binary"
