param(
  [string]$OutputDirectory = 'native\github_cli\windows\runtime'
)

$ErrorActionPreference = 'Stop'
$version = '2.100.0'
$archiveName = "gh_${version}_windows_amd64.zip"
$sha256 = '227e35230b25db3fa1b997bab7cf4d67df0470a3b75b99e4ee66bce1a7cd4e72'
$url = "https://github.com/cli/cli/releases/download/v$version/$archiveName"
$projectRoot = Split-Path -Parent $PSScriptRoot
$temporaryRoot = Join-Path $projectRoot '.tmp\github-cli-windows'
$archive = Join-Path $temporaryRoot $archiveName
$staging = Join-Path $temporaryRoot 'extract'
$target = Join-Path $projectRoot $OutputDirectory

if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
New-Item -ItemType Directory -Path $staging -Force | Out-Null
try {
  Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
  $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $sha256) { throw "GitHub CLI SHA-256 mismatch. Expected $sha256, got $actual" }
  Expand-Archive -LiteralPath $archive -DestinationPath $staging -Force
  $ghItem = Get-ChildItem -LiteralPath $staging -Filter 'gh.exe' -File -Recurse |
    Where-Object { $_.Directory.Name -eq 'bin' } | Select-Object -First 1
  if ($null -eq $ghItem) { throw 'Archive does not contain bin\gh.exe' }
  $source = Split-Path -Parent $ghItem.Directory.FullName
  $gh = $ghItem.FullName
  $versionOutput = @(& $gh --version)
  $versionExitCode = $LASTEXITCODE
  $reported = ($versionOutput | Select-Object -First 1).Trim()
  if ($versionExitCode -ne 0 -or $reported -notmatch '^gh version 2\.100\.0') { throw "Unexpected GitHub CLI version: $reported" }
  if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
  New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
  Move-Item -LiteralPath $source -Destination $target
  @{
    distribution = 'GitHub CLI'; version = $version; platform = 'windows'; architecture = 'amd64'
    sha256 = $sha256; source = $url; license = 'MIT'
  } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $target 'vibekits-github-cli-runtime.json') -Encoding utf8
  Write-Host "Prepared bundled GitHub CLI: $target ($reported)"
} finally {
  if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
}
