param(
  [string]$SourceExecutable = 'C:\Program Files\Clash Verge\verge-mihomo.exe',
  [string]$ExpectedVersion = '1.19.29',
  [string]$ExpectedSha256 = '98986B574E41F92B22ED65AA42A61AD8CADF886CC7B3F76B722CD73A3A52D878'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $projectRoot 'native\mihomo\windows\runtime'
$source = (Resolve-Path -LiteralPath $SourceExecutable).Path
$hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
if ($hash -ne $ExpectedSha256) {
  throw "Mihomo SHA-256 mismatch: $hash"
}
$reported = (& $source -v | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $reported -notmatch "Mihomo Meta v$([regex]::Escape($ExpectedVersion))") {
  throw "Unexpected Mihomo version: $reported"
}
New-Item -ItemType Directory -Force -Path $destination | Out-Null
Copy-Item -LiteralPath $source -Destination (Join-Path $destination 'mihomo.exe') -Force
$manifest = [ordered]@{
  product = 'Mihomo Meta'
  version = $ExpectedVersion
  source = 'https://github.com/MetaCubeX/mihomo'
  upstreamBundle = 'Clash Verge Rev'
  license = 'MIT'
  sha256 = $hash
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'vibekits-mihomo-runtime.json') -Encoding UTF8
Write-Host "Prepared Mihomo $ExpectedVersion ($hash)"
