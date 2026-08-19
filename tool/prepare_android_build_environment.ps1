param(
  [string]$AndroidSdkRoot = 'D:\work\allwin',
  [string]$JavaHome = 'D:\work\ai_code\tools\jdk-17\jdk-17.0.14+7'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$cache = Join-Path $projectRoot '.runtime-cache\android'
$archive = Join-Path $cache 'commandlinetools-win.zip'
$extract = Join-Path $cache 'commandlinetools'
$url = 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip'
$expectedSha256 = '90AE805D20434428BFFCB699C290860F19BB5F66A67E6B330067E3DE801FB04A'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
if (-not (Test-Path -LiteralPath $archive) -or
    (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedSha256) {
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
}
$actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
if ($actual -ne $expectedSha256) { throw "Command line tools SHA-256 mismatch: $actual" }
if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force
$latest = Join-Path $AndroidSdkRoot 'cmdline-tools\latest'
if (Test-Path -LiteralPath $latest) { Remove-Item -LiteralPath $latest -Recurse -Force }
New-Item -ItemType Directory -Force -Path $latest | Out-Null
Copy-Item -Path (Join-Path $extract 'cmdline-tools\*') -Destination $latest -Recurse
$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdkRoot
$env:ANDROID_SDK_ROOT = $AndroidSdkRoot
$android = Join-Path $latest 'bin\android.exe'
& $android --no-metrics sdk install platform-tools platforms/android-36 build-tools/36.0.0 ndk/28.2.13676358
if ($LASTEXITCODE -ne 0) { throw 'Android SDK component installation failed' }
Write-Host 'Android build environment is ready.'
