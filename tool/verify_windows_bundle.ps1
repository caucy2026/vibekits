param(
  [ValidateSet('Debug', 'Release')]
  [string]$Configuration = 'Release',
  [string]$ExpectedVersion = '1.9.0-dev.56+66',
  [string]$BundlePath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$bundle = if ([string]::IsNullOrWhiteSpace($BundlePath)) {
  Join-Path $projectRoot "build\windows\x64\runner\$Configuration"
} else {
  (Resolve-Path -LiteralPath $BundlePath).Path
}
$app = Join-Path $bundle 'vibekits.exe'
$required = @(
  'tools\git\cmd\git.exe',
  'tools\git\vibekits-git-runtime.json',
  'tools\adb\adb.exe',
  'tools\adb\AdbWinApi.dll',
  'tools\adb\AdbWinUsbApi.dll',
  'tools\7zip\7z.exe',
  'tools\7zip\7z.dll',
  'tools\harness\node.exe',
  'tools\harness\harness-runtime.json',
  'tools\harness\vibekits-mcp-server.mjs',
  'tools\harness\vibekits-approval.mjs',
  'tools\mihomo\mihomo.exe',
  'tools\mihomo\vibekits-mihomo-runtime.json',
  'tools\qemu\qemu-system-x86_64.exe',
  'tools\qemu\qemu-img.exe',
  'tools\qemu\vibekits-qemu-runtime.json',
  'libserialport_plus.dll',
  'onnxruntime.dll',
  'vibekits_onnx.dll',
  'data\flutter_assets\test_data\models\ppocrv6_tiny\det.onnx',
  'data\flutter_assets\test_data\models\ppocrv6_tiny\rec.onnx',
  'data\flutter_assets\test_data\models\ppocrv6_tiny\rec.yml'
)

if (-not (Test-Path -LiteralPath $app)) {
  throw "Windows bundle is missing: $app"
}
foreach ($relative in $required) {
  $path = Join-Path $bundle $relative
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Required bundled runtime is missing: $relative"
  }
}

$version = (Get-Item -LiteralPath $app).VersionInfo
if ($version.FileVersion -ne $ExpectedVersion -or $version.ProductVersion -ne $ExpectedVersion) {
  throw "Version mismatch: File=$($version.FileVersion), Product=$($version.ProductVersion)"
}
$git = Join-Path $bundle 'tools\git\cmd\git.exe'
$gitVersion = (& $git --version).Trim()
if ($LASTEXITCODE -ne 0 -or $gitVersion -notmatch '^git version 2\.55\.0\.windows\.3$') {
  throw "Bundled Git failed: $gitVersion"
}
$node = Join-Path $bundle 'tools\harness\node.exe'
& $node --check (Join-Path $bundle 'tools\harness\vibekits-approval.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Harness approval plugin syntax check failed' }

Write-Host "Verified bundle $bundle; version $ExpectedVersion; $gitVersion; required runtimes: $($required.Count)"
