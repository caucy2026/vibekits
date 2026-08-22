param(
  [string]$SourceExecutable = 'C:\Program Files\Clash Verge\verge-mihomo.exe',
  [string]$SourceDataDirectory = "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev",
  [string]$ExpectedVersion = '1.19.29',
  [string]$ExpectedSha256 = '98986B574E41F92B22ED65AA42A61AD8CADF886CC7B3F76B722CD73A3A52D878',
  [hashtable]$ExpectedGeoDataSha256 = @{
    'Country.mmdb' = '0EDF8A9651A7B21AF9234BB176DACB727FBD32149E19CC5A2A2163317A8F10FE'
    'geoip.dat' = 'AF332AB88EB4BB15E3CD10F03F5542E90655EE4BD5BF0E23949CFBD1E46BC20F'
    'geosite.dat' = '2C185FDFAC8F0AAC556CFCEEE6B66B9353779D3EF6DEFF3B4ACC0132D7515546'
  }
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
$geoData = [ordered]@{}
foreach ($name in @('Country.mmdb', 'geoip.dat', 'geosite.dat')) {
  $geoSource = (Resolve-Path -LiteralPath (Join-Path $SourceDataDirectory $name)).Path
  $geoHash = (Get-FileHash -LiteralPath $geoSource -Algorithm SHA256).Hash
  if ($geoHash -ne $ExpectedGeoDataSha256[$name]) {
    throw "$name SHA-256 mismatch: $geoHash"
  }
  Copy-Item -LiteralPath $geoSource -Destination (Join-Path $destination $name) -Force
  $geoData[$name] = [ordered]@{ sha256 = $geoHash; size = (Get-Item -LiteralPath $geoSource).Length }
}
$manifest = [ordered]@{
  product = 'Mihomo Meta'
  version = $ExpectedVersion
  source = 'https://github.com/MetaCubeX/mihomo'
  upstreamBundle = 'Clash Verge Rev'
  license = 'MIT'
  sha256 = $hash
  geoDataSource = 'https://github.com/MetaCubeX/meta-rules-dat'
  geoData = $geoData
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'vibekits-mihomo-runtime.json') -Encoding UTF8
Write-Host "Prepared Mihomo $ExpectedVersion ($hash)"
