param(
  [string]$InstallerUrl = 'https://qemu.weilnetz.de/w64/qemu-w64-setup-20260811.exe',
  [string]$Sha512Url = 'https://qemu.weilnetz.de/w64/qemu-w64-setup-20260811.sha512'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$cache = Join-Path $projectRoot '.runtime-cache\qemu'
$staging = Join-Path $cache 'staging'
$installer = Join-Path $cache 'qemu-w64-setup.exe'
$destination = Join-Path $projectRoot 'native\qemu\windows\runtime'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$checksumResponse = Invoke-WebRequest -UseBasicParsing -Uri $Sha512Url
$checksumText = if ($checksumResponse.Content -is [byte[]]) {
  [Text.Encoding]::ASCII.GetString($checksumResponse.Content)
} else {
  [string]$checksumResponse.Content
}
$expected = (($checksumText.Trim()) -split '\s+')[0].ToUpperInvariant()
$existingMatches = (Test-Path -LiteralPath $installer) -and
  ((Get-FileHash -LiteralPath $installer -Algorithm SHA512).Hash -eq $expected)
if (-not $existingMatches) {
  Invoke-WebRequest -UseBasicParsing -Uri $InstallerUrl -OutFile $installer
}
$actual = (Get-FileHash -LiteralPath $installer -Algorithm SHA512).Hash
if ($actual -ne $expected) { throw "QEMU installer SHA-512 mismatch: $actual" }
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
$process = Start-Process -FilePath $installer -ArgumentList @('/S', "/D=$staging") -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "QEMU silent installer failed: $($process.ExitCode)" }
if (-not (Test-Path -LiteralPath (Join-Path $staging 'qemu-system-x86_64.exe'))) {
  throw 'QEMU x86_64 executable missing after extraction'
}
if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
New-Item -ItemType Directory -Force -Path $destination | Out-Null
Copy-Item -LiteralPath (Join-Path $staging 'qemu-system-x86_64.exe') -Destination $destination
Copy-Item -LiteralPath (Join-Path $staging 'qemu-img.exe') -Destination $destination
Get-ChildItem -LiteralPath $staging -Filter '*.dll' -File | Copy-Item -Destination $destination
$shareSource = Join-Path $staging 'share'
$shareDestination = Join-Path $destination 'share'
New-Item -ItemType Directory -Force -Path $shareDestination | Out-Null
foreach ($pattern in @(
  'bios*.bin', 'vgabios*.bin', 'kvmvapic.bin', 'linuxboot*.bin',
  'multiboot.bin', 'efi-*.rom', 'pxe-*.rom', '*.aml',
  'edk2-i386-*.fd', 'edk2-x86_64-*.fd'
)) {
  Get-ChildItem -LiteralPath $shareSource -Filter $pattern -File |
    Copy-Item -Destination $shareDestination
}
$keymaps = Join-Path $shareSource 'keymaps'
if (Test-Path -LiteralPath $keymaps) {
  Copy-Item -LiteralPath $keymaps -Destination $shareDestination -Recurse
}
foreach ($notice in @('COPYING', 'COPYING.LIB', 'README')) {
  $source = Join-Path $staging $notice
  if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $destination }
}
$version = (& (Join-Path $destination 'qemu-system-x86_64.exe') --version | Select-Object -First 1).Trim()
$manifest = [ordered]@{
  product = 'QEMU x86_64 compact runtime'
  version = $version
  source = 'https://www.qemu.org/'
  windowsBuild = $InstallerUrl
  license = 'GPL-2.0 and component licenses; see COPYING files'
  installerSha512 = $actual
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'vibekits-qemu-runtime.json') -Encoding UTF8
Write-Host "Prepared $version"
