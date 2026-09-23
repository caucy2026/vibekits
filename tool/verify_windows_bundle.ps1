param(
  [ValidateSet('Debug', 'Release')]
  [string]$Configuration = 'Release',
  [string]$ExpectedVersion = '',
  [string]$BundlePath = '',
  [switch]$IncludeOptionalRuntimes,
  [switch]$SkipLiveRelayProbe
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) {
  $manifest = Join-Path $projectRoot 'pubspec.yaml'
  $versionMatch = Select-String -LiteralPath $manifest -Pattern '^version:\s*(\S+)\s*$' | Select-Object -First 1
  if ($null -eq $versionMatch) {
    throw "Unable to read the application version from $manifest"
  }
  $ExpectedVersion = $versionMatch.Matches[0].Groups[1].Value
}
$appVersionSource = Get-Content -LiteralPath (Join-Path $projectRoot 'lib\app\app_version.dart') -Raw
$semanticMatch = [regex]::Match($appVersionSource, "static const String semantic = '([^']+)';")
$buildMatch = [regex]::Match($appVersionSource, 'static const int build = (\d+);')
if (-not $semanticMatch.Success -or -not $buildMatch.Success) {
  throw 'Unable to read AppVersion semantic/build constants'
}
$sourceVersion = "$($semanticMatch.Groups[1].Value)+$($buildMatch.Groups[1].Value)"
if ($sourceVersion -ne $ExpectedVersion) {
  throw "Source version mismatch: pubspec/expected=$ExpectedVersion, AppVersion=$sourceVersion"
}
$bundle = if ([string]::IsNullOrWhiteSpace($BundlePath)) {
  Join-Path $projectRoot "build\windows\x64\runner\$Configuration"
} else {
  (Resolve-Path -LiteralPath $BundlePath).Path
}
$app = Join-Path $bundle 'vibekits.exe'
$required = @(
  'flutter_windows.dll',
  'data\app.so',
  'vibekits-harness-relay.exe',
  'vibekits-harness-relay.json',
  'RUSTDESK-AGPL-3.0.txt',
  'tools\git\cmd\git.exe',
  'tools\git\mingw64\bin\git-remote-http.exe',
  'tools\git\mingw64\bin\git-remote-https.exe',
  'tools\git\vibekits-git-runtime.json',
  'tools\github-cli\bin\gh.exe',
  'tools\github-cli\vibekits-github-cli-runtime.json',
  'tools\adb\adb.exe',
  'tools\adb\AdbWinApi.dll',
  'tools\adb\AdbWinUsbApi.dll',
  'tools\7zip\7z.exe',
  'tools\7zip\7z.dll',
  'tools\harness\node.exe',
  'tools\harness\harness-runtime.json',
  'tools\harness\vibekits-mcp-server.mjs',
  'tools\harness\vibekits-codex-mcp.mjs',
  'tools\harness\vibekits-approval.mjs',
  'tools\harness\vibekits-parent-watchdog.mjs',
  'tools\harness\vibekits-android-stress-mcp.mjs',
  'tools\harness\vibekits-session-rebind.mjs',
  'tools\harness\builtin-skills\kemi-s1-hardware-debug\SKILL.md',
  'tools\harness\builtin-skills\kemi-s1-hardware-debug\agents\openai.yaml',
  'tools\harness\builtin-skills\kemi-s1-hardware-debug\references\s1-profile.md',
  'tools\harness\builtin-skills\kemi-s1-hardware-debug\references\hiv730-project-routing.md',
  'tools\harness\builtin-skills\vibekits-remote-simulator\SKILL.md',
  'tools\harness\builtin-skills\vibekits-remote-simulator\agents\openai.yaml',
  'tools\harness\builtin-skills\vibekits-remote-simulator\references\tool-contract.md',
  'tools\harness\builtin-skills\vibekits-remote-simulator\scripts\invoke.rb',
  'tools\lark-cli\lark-cli.exe',
  'libserialport_plus.dll',
  'onnxruntime.dll',
  'vibekits_onnx.dll',
  'data\flutter_assets\test_data\models\ppocrv6_tiny\det.onnx',
  'data\flutter_assets\test_data\models\ppocrv6_tiny\rec.onnx',
  'data\flutter_assets\test_data\models\ppocrv6_tiny\rec.yml'
)

if ($IncludeOptionalRuntimes) {
  $required += @(
  'tools\mihomo\mihomo.exe',
  'tools\mihomo\vibekits-mihomo-runtime.json',
  'tools\mihomo\Country.mmdb',
  'tools\mihomo\geoip.dat',
  'tools\mihomo\geosite.dat',
  'tools\qemu\qemu-system-x86_64.exe',
  'tools\qemu\qemu-img.exe',
  'tools\qemu\vibekits-qemu-runtime.json'
  )
}

if (-not (Test-Path -LiteralPath $app)) {
  throw "Windows bundle is missing: $app"
}
foreach ($relative in $required) {
  $path = Join-Path $bundle $relative
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Required bundled runtime is missing: $relative"
  }
}

$relay = Join-Path $bundle 'vibekits-harness-relay.exe'
$relayManifestPath = Join-Path $bundle 'vibekits-harness-relay.json'
$relayManifest = Get-Content -LiteralPath $relayManifestPath -Raw | ConvertFrom-Json
$relayHash = (Get-FileHash -LiteralPath $relay -Algorithm SHA256).Hash.ToLowerInvariant()
if ($relayManifest.component -ne 'vibekits-harness-relay' -or
    $relayManifest.target -ne 'x86_64-pc-windows-msvc' -or
    $relayManifest.sha256 -ne $relayHash) {
  throw 'Bundled Harness relay provenance or SHA256 is invalid'
}
# Structural checks can run while another installed VibeKits owns the relay.
# Release acceptance must also run the default live probe with THIS bundle active.
if (-not $SkipLiveRelayProbe) {
$relayStatusText = (& $relay --vibekits-harness-status 2>$null | Out-String).Trim()
try {
  $relayStatus = $relayStatusText | ConvertFrom-Json
} catch {
  throw "Bundled Harness relay status did not return JSON: $relayStatusText"
}
if ($null -eq $relayStatus) { throw 'Bundled Harness relay status was empty' }
$relayProtocolText = (& $relay --vibekits-harness-protocol 2>$null | Out-String).Trim()
try {
  $relayProtocol = $relayProtocolText | ConvertFrom-Json
} catch {
  throw "Bundled Harness relay protocol probe did not return JSON: $relayProtocolText"
}
if ($LASTEXITCODE -ne 0 -or
    $relayProtocol.code -notin @('protocol_v2', 'service_unavailable')) {
  throw "Bundled Harness relay does not implement protocol_v2: $relayProtocolText"
}

}

$version = (Get-Item -LiteralPath $app).VersionInfo
if ($version.FileVersion -ne $ExpectedVersion -or $version.ProductVersion -ne $ExpectedVersion) {
  throw "Version mismatch: File=$($version.FileVersion), Product=$($version.ProductVersion)"
}
# The EXE resource and installer can report the new version while Flutter's
# actual AOT payload is left over from an older build. Check the version shown
# by the running app in app.so before accepting the staged directory.
$expectedSemanticVersion = ($ExpectedVersion -split '\+')[0]
$appSo = Join-Path $bundle 'data\app.so'
$appSoText = [Text.Encoding]::GetEncoding(28591).GetString(
  [IO.File]::ReadAllBytes($appSo)
)
if (-not $appSoText.Contains($expectedSemanticVersion)) {
  throw "Flutter AOT version mismatch: data\app.so does not contain $expectedSemanticVersion"
}
$git = Join-Path $bundle 'tools\git\cmd\git.exe'
$gitVersion = (& $git --version).Trim()
if ($LASTEXITCODE -ne 0 -or $gitVersion -notmatch '^git version 2\.55\.0\.windows\.3$') {
  throw "Bundled Git failed: $gitVersion"
}
foreach ($helperName in @('git-remote-http.exe', 'git-remote-https.exe')) {
  $helper = Join-Path $bundle "tools\git\mingw64\bin\$helperName"
  if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) {
    throw "Bundled Git is missing HTTPS helper: $helperName"
  }
}
$gh = Join-Path $bundle 'tools\github-cli\bin\gh.exe'
$ghVersion = (& $gh --version | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or $ghVersion -notmatch '^gh version 2\.100\.0') {
  throw "Bundled GitHub CLI failed: $ghVersion"
}
$node = Join-Path $bundle 'tools\harness\node.exe'
& $node --check (Join-Path $bundle 'tools\harness\vibekits-approval.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Harness approval plugin syntax check failed' }
& $node --check (Join-Path $bundle 'tools\harness\vibekits-session-rebind.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Harness session rebind helper syntax check failed' }

$larkCli = Join-Path $bundle 'tools\lark-cli\lark-cli.exe'
$larkVersion = (& $larkCli --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $larkVersion -notmatch '1\.0\.92') {
  throw "Bundled Lark CLI failed version smoke test: $larkVersion"
}
$larkSchema = (& $larkCli schema calendar.events.get 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or
    $larkSchema -notmatch 'calendar_id' -or
    $larkSchema -notmatch 'calendar:calendar:readonly') {
  throw 'Bundled Lark CLI failed calendar schema smoke test'
}

Write-Host "Verified bundle $bundle; version $ExpectedVersion; $gitVersion; $ghVersion; Lark CLI $larkVersion; required runtimes: $($required.Count)"
