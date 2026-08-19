param(
  [ValidateSet('fast', 'release')]
  [string]$Tier = 'fast',
  [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = Join-Path $projectRoot 'build\acceptance'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$manifestPath = Join-Path $PSScriptRoot 'release_acceptance_manifest.json'
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath |
  ConvertFrom-Json
$flutter = 'D:\tools\flutter\bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) {
  $flutter = (Get-Command flutter -ErrorAction Stop).Source
}

$commands = [System.Collections.Generic.List[object]]::new()
$commands.Add([pscustomobject]@{
  name = 'acceptance manifest'
  executable = $flutter
  arguments = @('test', 'test\feature_acceptance_manifest_test.dart')
})
$commands.Add([pscustomobject]@{
  name = 'system drive insights'
  executable = $flutter
  arguments = @('test', 'test\system_drive_analyzer_test.dart')
})
$commands.Add([pscustomobject]@{
  name = 'cleaner workflow'
  executable = $flutter
  arguments = @('test', 'test\cleanup_scanner_test.dart', 'test\cleanup_deleter_report_test.dart', 'test\cleaner_widget_test.dart')
})
$commands.Add([pscustomobject]@{
  name = 'Harness workflow bridge'
  executable = $flutter
  arguments = @('test', 'test\harness_tool_bridge_test.dart', 'test\remote_workspace_widget_test.dart')
})
$commands.Add([pscustomobject]@{
  name = 'file Diff and module audit'
  executable = $flutter
  arguments = @('test', 'test\file_diff_service_test.dart', 'test\file_diff_widget_test.dart', 'test\harness_tool_activity_store_test.dart')
})
if ($Tier -eq 'release') {
  $commands.Add([pscustomobject]@{
    name = 'Flutter analyze'
    executable = $flutter
    arguments = @('analyze')
  })
  $commands.Add([pscustomobject]@{
    name = 'Windows Release build'
    executable = $flutter
    arguments = @('build', 'windows', '--release')
  })
  $commands.Add([pscustomobject]@{
    name = 'Windows bundle verification'
    executable = 'powershell'
    arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'verify_windows_bundle.ps1'))
  })
}

$results = [System.Collections.Generic.List[object]]::new()
$failed = $false
Push-Location $projectRoot
try {
  foreach ($command in $commands) {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $safeName = ($command.name -replace '[^A-Za-z0-9_-]', '_')
    $logPath = Join-Path $OutputDirectory "${timestamp}_${safeName}.log"
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $output = & $command.executable @($command.arguments) 2>&1
      $exitCode = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $previousErrorAction
    }
    $watch.Stop()
    $output | Set-Content -LiteralPath $logPath -Encoding UTF8
    if ($exitCode -ne 0) { $failed = $true }
    $results.Add([pscustomobject]@{
      name = $command.name
      exitCode = $exitCode
      durationMs = $watch.ElapsedMilliseconds
      log = $logPath
    })
  }
} finally {
  Pop-Location
}

$releaseExe = Join-Path $projectRoot 'build\windows\x64\runner\Release\vibekits.exe'
$artifact = $null
if (Test-Path -LiteralPath $releaseExe) {
  $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($releaseExe)
  $artifact = [pscustomobject]@{
    path = $releaseExe
    fileVersion = $version.FileVersion
    productVersion = $version.ProductVersion
    sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $releaseExe).Hash
  }
}
$report = [pscustomobject]@{
  schemaVersion = 1
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  tier = $Tier
  passed = -not $failed
  manifestVersion = $manifest.version
  workflowCount = @($manifest.workflows).Count
  commands = $results
  artifact = $artifact
}
$jsonPath = Join-Path $OutputDirectory "${timestamp}_${Tier}_acceptance.json"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$markdownPath = Join-Path $OutputDirectory "${timestamp}_${Tier}_acceptance.md"
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# Vibekits $Tier acceptance")
$lines.Add('')
$lines.Add("- Generated: $($report.generatedAt)")
$lines.Add("- Result: $(if ($report.passed) { 'PASS' } else { 'FAIL' })")
$lines.Add("- Workflows in manifest: $($report.workflowCount)")
if ($artifact) {
  $lines.Add("- Artifact: $($artifact.productVersion)")
  $lines.Add("- SHA-256: $($artifact.sha256)")
}
$lines.Add('')
$lines.Add('| Check | Exit | Duration ms | Log |')
$lines.Add('|---|---:|---:|---|')
foreach ($result in $results) {
  $lines.Add("| $($result.name) | $($result.exitCode) | $($result.durationMs) | $($result.log) |")
}
$lines | Set-Content -LiteralPath $markdownPath -Encoding UTF8
Write-Output "Acceptance report: $markdownPath"
if ($failed) { exit 1 }
