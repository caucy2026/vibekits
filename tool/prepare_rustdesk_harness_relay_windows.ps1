param(
  [string]$RustDeskSource = $env:VIBEKITS_RUSTDESK_SOURCE,
  [string]$ToolsRoot = 'D:\KEMI-Test\tools',
  [string]$VisualStudioRoot = 'D:\VSBuildTools',
  [string]$LlvmRoot = '',
  [string]$OutputFile = '',
  [string]$CargoTargetDirectory = 'D:\KEMI-Test\build\rustdesk-harness-relay'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
  $OutputFile = Join-Path $projectRoot 'native\rustdesk\windows\runtime\vibekits-harness-relay.exe'
}
if ([string]::IsNullOrWhiteSpace($RustDeskSource)) {
  $RustDeskSource = 'D:\KEMI-Test\work\RustDesk\client'
}

function Assert-DDrivePath([string]$Name, [string]$Path) {
  if (-not [System.IO.Path]::IsPathFullyQualified($Path)) {
    throw "$Name must be an absolute path: $Path"
  }
  if (-not $Path.StartsWith('D:\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Name must stay on the Windows lab D drive: $Path"
  }
}

Assert-DDrivePath 'RustDeskSource' $RustDeskSource
Assert-DDrivePath 'ToolsRoot' $ToolsRoot
Assert-DDrivePath 'VisualStudioRoot' $VisualStudioRoot
Assert-DDrivePath 'OutputFile' $OutputFile
Assert-DDrivePath 'CargoTargetDirectory' $CargoTargetDirectory

if ([string]::IsNullOrWhiteSpace($LlvmRoot)) {
  $LlvmRoot = Get-ChildItem -LiteralPath $ToolsRoot -Directory |
    Where-Object { $_.Name -like 'llvm*' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\libclang.dll')) } |
    Sort-Object Name -Descending |
    Select-Object -First 1 -ExpandProperty FullName
}
if ([string]::IsNullOrWhiteSpace($LlvmRoot)) {
  throw "No pinned LLVM directory containing bin\libclang.dll was found under $ToolsRoot"
}
Assert-DDrivePath 'LlvmRoot' $LlvmRoot
$libclangPath = Join-Path $LlvmRoot 'bin'

$cargoHome = Join-Path $ToolsRoot 'cargo-home-rustdesk'
$rustupHome = Join-Path $ToolsRoot 'rustup-home-rustdesk'
$cargo = Join-Path $cargoHome 'bin\cargo.exe'
$vswhere = Join-Path $ToolsRoot 'vswhere.exe'
$vcpkgRoot = Get-ChildItem -LiteralPath $ToolsRoot -Directory |
  Where-Object { $_.Name -like 'vcpkg-*' } |
  Sort-Object Name -Descending |
  Select-Object -First 1 -ExpandProperty FullName

foreach ($required in @(
  (Join-Path $RustDeskSource 'Cargo.toml'),
  (Join-Path $RustDeskSource 'Cargo.lock'),
  (Join-Path $RustDeskSource 'src\vibekits_harness_cli.rs'),
  (Join-Path $RustDeskSource 'src\vibekits_harness_relay.rs'),
  $cargo,
  (Join-Path $libclangPath 'libclang.dll'),
  (Join-Path $projectRoot 'third_party\rustdesk-transport\LICENCE')
)) {
  if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
    throw "Required relay build input is missing: $required"
  }
}
if ([string]::IsNullOrWhiteSpace($vcpkgRoot)) {
  throw "No pinned vcpkg directory was found under $ToolsRoot"
}

function Invoke-CapturedProcess(
  [string]$FilePath,
  [string[]]$ArgumentList
) {
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $FilePath
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  foreach ($argument in $ArgumentList) {
    $startInfo.ArgumentList.Add($argument)
  }
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  if (-not $process.Start()) {
    throw "Unable to start native process: $FilePath"
  }
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) {
    throw "Native process failed ($($process.ExitCode)): $FilePath`n$stderr"
  }
  return $stdout
}

$vsDevCmd = Join-Path $VisualStudioRoot 'Common7\Tools\VsDevCmd.bat'
if (-not (Test-Path -LiteralPath $vsDevCmd -PathType Leaf)) {
  if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw "Visual Studio C++ Build Tools and vswhere are missing: $VisualStudioRoot"
  }
  $visualStudio = (Invoke-CapturedProcess $vswhere @(
    '-latest',
    '-products', '*',
    '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
    '-property', 'installationPath'
  )).Trim()
  if ([string]::IsNullOrWhiteSpace($visualStudio)) {
    throw 'Visual Studio C++ Build Tools were not found'
  }
  $vsDevCmd = Join-Path $visualStudio 'Common7\Tools\VsDevCmd.bat'
}
if (-not (Test-Path -LiteralPath $vsDevCmd -PathType Leaf)) {
  throw "VsDevCmd.bat is missing: $vsDevCmd"
}
$commandProcessor = Join-Path $env:SystemRoot 'System32\cmd.exe'
& $commandProcessor /d /s /c "`"$vsDevCmd`" -no_logo -arch=x64 -host_arch=x64 >nul && set" |
  ForEach-Object {
    $separator = $_.IndexOf('=')
    if ($separator -gt 0) {
      [Environment]::SetEnvironmentVariable(
        $_.Substring(0, $separator),
        $_.Substring($separator + 1),
        'Process'
      )
    }
  }

$env:CARGO_HOME = $cargoHome
$env:RUSTUP_HOME = $rustupHome
$env:CARGO_TARGET_DIR = $CargoTargetDirectory
$env:VCPKG_ROOT = $vcpkgRoot
$env:VCPKG_INSTALLED_ROOT = Join-Path $vcpkgRoot 'installed'
$env:VCPKG_DEFAULT_TRIPLET = 'x64-windows-static'
$env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
$env:LIBCLANG_PATH = $libclangPath
$env:PATH = "$(Join-Path $cargoHome 'bin');$env:PATH"

Push-Location $RustDeskSource
try {
  & $cargo test --locked --target x86_64-pc-windows-msvc --features flutter --lib 'vibekits_harness_relay::tests'
  if ($LASTEXITCODE -ne 0) { throw 'Harness relay Rust tests failed' }
  & $cargo build --locked --release --target x86_64-pc-windows-msvc --features flutter --bin vibekits-harness-relay
  if ($LASTEXITCODE -ne 0) { throw 'Harness relay Release build failed' }
  $sourceCommit = (& git rev-parse HEAD).Trim()
} finally {
  Pop-Location
}

$builtRelay = Join-Path $CargoTargetDirectory 'x86_64-pc-windows-msvc\release\vibekits-harness-relay.exe'
if (-not (Test-Path -LiteralPath $builtRelay -PathType Leaf)) {
  throw "Cargo did not produce the expected relay: $builtRelay"
}
$binaryText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($builtRelay))
foreach ($marker in @(
  'transport_connected',
  'transport_connect_timeout',
  'stdin_eof_v1',
  'vibekits-harness-remote-assistance-access'
)) {
  if (-not $binaryText.Contains($marker)) {
    throw "Harness relay is stale; missing marker: $marker"
  }
}

$statusText = (& $builtRelay --vibekits-harness-status 2>$null | Out-String).Trim()
try {
  $status = $statusText | ConvertFrom-Json
} catch {
  throw "Harness relay status did not return JSON: $statusText"
}
if ($null -eq $status) { throw 'Harness relay status was empty' }

$outputDirectory = Split-Path -Parent $OutputFile
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$temporary = "$OutputFile.new"
Copy-Item -LiteralPath $builtRelay -Destination $temporary -Force
Move-Item -LiteralPath $temporary -Destination $OutputFile -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'third_party\rustdesk-transport\LICENCE') `
  -Destination (Join-Path $outputDirectory 'RUSTDESK-AGPL-3.0.txt') -Force

$hash = (Get-FileHash -LiteralPath $OutputFile -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = [ordered]@{
  schemaVersion = 1
  component = 'vibekits-harness-relay'
  sourceRepository = 'https://github.com/caucy2026/rust-desk.git'
  sourceCommit = $sourceCommit
  target = 'x86_64-pc-windows-msvc'
  features = @('flutter')
  sha256 = $hash
}
$manifestPath = Join-Path $outputDirectory 'vibekits-harness-relay.json'
$manifestJson = $manifest | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText(
  $manifestPath,
  $manifestJson,
  [Text.UTF8Encoding]::new($false)
)

Write-Host "Prepared $OutputFile"
Write-Host "sourceCommit=$sourceCommit"
Write-Host "sha256=$hash"
