param(
  [string]$OutputDirectory = "native\git\windows\runtime"
)

$ErrorActionPreference = 'Stop'
$version = '2.55.0.3'
$tag = 'v2.55.0.windows.3'
$sha256 = 'f48e2d2dc74a24454adc6d8fd0ac25bf9c2386f19cfb06202b9465aaad4f9f05'
$url = "https://github.com/git-for-windows/git/releases/download/$tag/MinGit-$version-64-bit.zip"
$projectRoot = Split-Path -Parent $PSScriptRoot
$target = Join-Path $projectRoot $OutputDirectory
$staging = Join-Path ([System.IO.Path]::GetTempPath()) "vibekits-mingit-$version"
$archive = Join-Path ([System.IO.Path]::GetTempPath()) "vibekits-mingit-$version.zip"

if (Test-Path -LiteralPath $staging) {
  Remove-Item -LiteralPath $staging -Recurse -Force
}
New-Item -ItemType Directory -Path $staging | Out-Null

try {
  Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
  $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualHash -ne $sha256) {
    throw "MinGit SHA-256 mismatch. Expected $sha256, got $actualHash"
  }
  Expand-Archive -LiteralPath $archive -DestinationPath $staging -Force
  $git = Join-Path $staging 'cmd\git.exe'
  if (-not (Test-Path -LiteralPath $git)) {
    throw 'MinGit archive does not contain cmd\git.exe'
  }
  $reportedVersion = (& $git --version).Trim()
  if ($LASTEXITCODE -ne 0 -or $reportedVersion -notmatch '^git version 2\.55\.0') {
    throw "Unexpected bundled Git version: $reportedVersion"
  }

  if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }
  New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
  Move-Item -LiteralPath $staging -Destination $target
  @{
    distribution = 'MinGit'
    version = $version
    tag = $tag
    sha256 = $sha256
    source = $url
    license = 'GPL-2.0-only and bundled component licenses'
  } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $target 'vibekits-git-runtime.json') -Encoding utf8
  Write-Host "Prepared bundled Git runtime: $target ($reportedVersion)"
} finally {
  if (Test-Path -LiteralPath $archive) {
    Remove-Item -LiteralPath $archive -Force
  }
  if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force
  }
}
