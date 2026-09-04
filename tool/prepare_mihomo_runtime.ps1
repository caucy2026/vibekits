param(
  [string]$SourceExecutable = '',
  [string]$SourceDataDirectory = '',
  [string]$ExpectedVersion = '1.19.29',
  [string]$ExpectedArchiveSha256 = '1A8520CFE425441EBA3EBA8623B27B985020031243FE1ECAA1AF2B92358A03F9',
  [hashtable]$ExpectedGeoDataSha256 = @{
    'Country.mmdb' = 'D432DC277AE18CD5CF0D2BEE7711E715A6819D1C8B9284108192C73762827BC3'
    'geoip.dat' = '2C2272AEDFF90DC25353E4D35DF3D4A96C8AD77A65090E0433758EBD148382DD'
    'geosite.dat' = '35339FB9EADABE881ADCA2A74320E24FF2473FE86D2CF3DEDF68935994FC61ED'
  }
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$cache = Join-Path $projectRoot '.runtime-cache\mihomo'
$destination = Join-Path $projectRoot 'native\mihomo\windows\runtime'
$archive = Join-Path $cache "mihomo-windows-amd64-v$ExpectedVersion.zip"
$staging = Join-Path $cache 'staging'
New-Item -ItemType Directory -Force -Path $cache | Out-Null

if ($SourceExecutable) {
  $source = (Resolve-Path -LiteralPath $SourceExecutable).Path
} else {
  $url = "https://github.com/MetaCubeX/mihomo/releases/download/v$ExpectedVersion/mihomo-windows-amd64-v$ExpectedVersion.zip"
  if (-not (Test-Path -LiteralPath $archive) -or
      (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $ExpectedArchiveSha256) {
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
  }
  $archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
  if ($archiveHash -ne $ExpectedArchiveSha256) {
    throw "Mihomo archive SHA-256 mismatch: $archiveHash"
  }
  if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
  Expand-Archive -LiteralPath $archive -DestinationPath $staging -Force
  $source = (Get-ChildItem -LiteralPath $staging -Filter '*.exe' -File | Select-Object -First 1).FullName
  if (-not $source) { throw 'Official Mihomo archive contains no executable' }
}
$reported = (& $source -v | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $reported -notmatch "Mihomo Meta v$([regex]::Escape($ExpectedVersion))") {
  throw "Unexpected Mihomo version: $reported"
}
New-Item -ItemType Directory -Force -Path $destination | Out-Null
Copy-Item -LiteralPath $source -Destination (Join-Path $destination 'mihomo.exe') -Force
$geoData = [ordered]@{}
foreach ($name in @('Country.mmdb', 'geoip.dat', 'geosite.dat')) {
  if ($SourceDataDirectory) {
    $geoSource = (Resolve-Path -LiteralPath (Join-Path $SourceDataDirectory $name)).Path
  } else {
    $geoSource = Join-Path $cache $name
    if (-not (Test-Path -LiteralPath $geoSource) -or
        (Get-FileHash -LiteralPath $geoSource -Algorithm SHA256).Hash -ne $ExpectedGeoDataSha256[$name]) {
      Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/$name" -OutFile $geoSource
    }
  }
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
  distribution = 'Official Windows amd64 release archive'
  license = 'MIT'
  archiveSha256 = $ExpectedArchiveSha256
  geoDataSource = 'https://github.com/MetaCubeX/meta-rules-dat'
  geoData = $geoData
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'vibekits-mihomo-runtime.json') -Encoding UTF8
Write-Host "Prepared Mihomo $ExpectedVersion ($ExpectedArchiveSha256)"
