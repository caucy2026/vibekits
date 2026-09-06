param(
  [string]$SourceExecutable = '',
  [string]$SourceDataDirectory = '',
  [string]$ExpectedVersion = '1.19.29',
  [string]$ExpectedArchiveSha256 = '1A8520CFE425441EBA3EBA8623B27B985020031243FE1ECAA1AF2B92358A03F9',
  [hashtable]$ExpectedGeoDataSha256 = @{
    'Country.mmdb' = '031BD6E8DFD62D70B81D2D65CE54A92ED7F21F060ADD17C66E16A2A0E55D3A41'
    'geoip.dat' = '4149E607530F91DA697BAD4696F8C59F0A475AF38E69405E4124438C9886C721'
    'geosite.dat' = '54AF8C41407B9A56A59E65C03BCC27D812CB2620E18E62E4795E2972FFF5B539'
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
