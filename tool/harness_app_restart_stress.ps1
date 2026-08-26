param(
  [ValidateRange(1, 1000)]
  [int]$Count = 100,
  [int]$WindowTimeoutSeconds = 15,
  [int]$ReadyTimeoutSeconds = 90,
  [int]$CloseTimeoutSeconds = 15,
  [string]$Executable = '',
  [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Executable) {
  $Executable = Join-Path $projectRoot 'build\windows\x64\runner\Release\vibekits.exe'
}
if (-not (Test-Path -LiteralPath $Executable)) {
  throw "VibeKits executable was not found: $Executable"
}

$logDirectory = Join-Path (Split-Path -Parent $Executable) 'tmp\logs'
if (-not $OutputPath) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $OutputPath = Join-Path $projectRoot ".tmp\harness-app-restart-$stamp.csv"
}
$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class VibeKitsRestartStressNative {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, UIntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern void keybd_event(byte virtualKey, byte scan, uint flags, UIntPtr extraInfo);
  public const uint WM_COMMAND = 0x0111;
  public const uint TRAY_EXIT_COMMAND = 41002;
  public const byte VK_CONTROL = 0x11;
  public const byte VK_1 = 0x31;
  public const uint KEYUP = 0x0002;
  public static void OpenHarness(IntPtr window) {
    SetForegroundWindow(window);
    keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
    keybd_event(VK_1, 0, 0, UIntPtr.Zero);
    keybd_event(VK_1, 0, KEYUP, UIntPtr.Zero);
    keybd_event(VK_CONTROL, 0, KEYUP, UIntPtr.Zero);
  }
  public static void ExitApp(IntPtr window) {
    PostMessage(window, WM_COMMAND, new UIntPtr(TRAY_EXIT_COMMAND), IntPtr.Zero);
  }
}
'@

function Wait-MainWindow([System.Diagnostics.Process]$Process, [int]$TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if ($Process.HasExited) { return [IntPtr]::Zero }
    $Process.Refresh()
    if ($Process.MainWindowHandle -ne [IntPtr]::Zero) { return $Process.MainWindowHandle }
    Start-Sleep -Milliseconds 100
  }
  return [IntPtr]::Zero
}

function Get-HarnessLog([datetime]$StartedAt, [string[]]$ExistingPaths) {
  if (-not (Test-Path -LiteralPath $logDirectory)) { return $null }
  return Get-ChildItem -LiteralPath $logDirectory -Filter 'harness-web-*.log' -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.LastWriteTime -ge $StartedAt.AddSeconds(-2) -and
      $ExistingPaths -notcontains $_.FullName
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Wait-HarnessReady(
  [datetime]$StartedAt,
  [string[]]$ExistingPaths,
  [System.Diagnostics.Process]$AppProcess,
  [int]$TimeoutSeconds
) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $log = $null
  $url = ''
  $harnessPid = 0
  $statusCode = 0
  $client = [System.Net.Http.HttpClient]::new()
  $client.Timeout = [TimeSpan]::FromMilliseconds(1200)
  try {
    while ((Get-Date) -lt $deadline) {
      if ($AppProcess.HasExited) { throw 'APP exited before Harness became ready' }
      if (-not $log) { $log = Get-HarnessLog $StartedAt $ExistingPaths }
      if ($log -and -not $url) {
        $firstLine = Get-Content -LiteralPath $log.FullName -TotalCount 1 -ErrorAction SilentlyContinue
        if ($firstLine -match 'pid=(\d+)\s+url=(http://127\.0\.0\.1:\d+)') {
          $harnessPid = [int]$Matches[1]
          $url = $Matches[2]
        }
      }
      if ($url) {
        try {
          $response = $client.GetAsync($url).GetAwaiter().GetResult()
          $statusCode = [int]$response.StatusCode
          $response.Dispose()
          if ($statusCode -ge 200 -and $statusCode -lt 500) {
            return [pscustomobject]@{
              Log = $log.FullName
              Url = $url
              HarnessPid = $harnessPid
              StatusCode = $statusCode
            }
          }
        } catch {
          # DSH is still composing its Web profile.
        }
      }
      Start-Sleep -Milliseconds 250
    }
    throw "Harness did not return HTTP within $TimeoutSeconds seconds"
  } finally {
    $client.Dispose()
  }
}

# Begin from a clean APP instance. This setup close is not counted as a cycle.
Get-Process vibekits -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.MainWindowHandle -ne [IntPtr]::Zero) {
    [VibeKitsRestartStressNative]::ExitApp($_.MainWindowHandle)
  }
  if (-not $_.WaitForExit(5000)) { $_.Kill($true) }
}

$results = [System.Collections.Generic.List[object]]::new()
for ($cycle = 1; $cycle -le $Count; $cycle++) {
  $cycleWatch = [System.Diagnostics.Stopwatch]::StartNew()
  $existingLogs = if (Test-Path -LiteralPath $logDirectory) {
    @(Get-ChildItem -LiteralPath $logDirectory -Filter 'harness-web-*.log' -File -ErrorAction SilentlyContinue |
      ForEach-Object FullName)
  } else { @() }
  $startedAt = Get-Date
  $app = $null
  $windowReady = $false
  $harnessReady = $false
  $closeOk = $false
  $harnessExited = $false
  $readyMilliseconds = 0
  $closeMilliseconds = 0
  $harnessPid = 0
  $httpStatus = 0
  $harnessLog = ''
  $errorText = ''
  try {
    $app = Start-Process -FilePath $Executable -PassThru
    $window = Wait-MainWindow $app $WindowTimeoutSeconds
    if ($window -eq [IntPtr]::Zero) { throw 'Main window did not appear' }
    $windowReady = $true
    [VibeKitsRestartStressNative]::OpenHarness($window)
    $ready = Wait-HarnessReady $startedAt $existingLogs $app $ReadyTimeoutSeconds
    $harnessReady = $true
    $readyMilliseconds = $cycleWatch.ElapsedMilliseconds
    $harnessPid = $ready.HarnessPid
    $httpStatus = $ready.StatusCode
    $harnessLog = $ready.Log

    $closeWatch = [System.Diagnostics.Stopwatch]::StartNew()
    [VibeKitsRestartStressNative]::ExitApp($window)
    $closeOk = $app.WaitForExit($CloseTimeoutSeconds * 1000)
    $closeMilliseconds = $closeWatch.ElapsedMilliseconds
    if (-not $closeOk) {
      $app.Kill($true)
      $app.WaitForExit(5000) | Out-Null
      $errorText = 'APP required forced termination'
    }
    if ($harnessPid -gt 0) {
      $harnessDeadline = (Get-Date).AddSeconds(5)
      do {
        $harnessProcess = Get-Process -Id $harnessPid -ErrorAction SilentlyContinue
        if (-not $harnessProcess) { break }
        Start-Sleep -Milliseconds 100
      } while ((Get-Date) -lt $harnessDeadline)
      $harnessExited = -not [bool](Get-Process -Id $harnessPid -ErrorAction SilentlyContinue)
    }
    if (-not $harnessExited) {
      $errorText = (($errorText + '; Harness PID remained after APP exit').Trim('; '))
    }
  } catch {
    $errorText = $_.Exception.Message
    if ($app -and -not $app.HasExited) {
      try { $app.Kill($true); $app.WaitForExit(5000) | Out-Null } catch {}
    }
    if ($harnessPid -gt 0) {
      $harnessExited = -not [bool](Get-Process -Id $harnessPid -ErrorAction SilentlyContinue)
    }
  } finally {
    $cycleWatch.Stop()
  }
  $passed = $windowReady -and $harnessReady -and $closeOk -and $harnessExited
  $result = [pscustomobject]@{
    Cycle = $cycle
    Passed = $passed
    AppPid = if ($app) { $app.Id } else { 0 }
    HarnessPid = $harnessPid
    ReadyMs = $readyMilliseconds
    CloseMs = $closeMilliseconds
    HttpStatus = $httpStatus
    WindowReady = $windowReady
    HarnessReady = $harnessReady
    GracefulClose = $closeOk
    HarnessExited = $harnessExited
    HarnessLog = $harnessLog
    Error = $errorText
  }
  $results.Add($result)
  $state = if ($passed) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0:D3}/{1:D3}] {2} ready={3}ms close={4}ms http={5} app={6} harness={7} {8}" -f `
    $cycle, $Count, $state, $readyMilliseconds, $closeMilliseconds, $httpStatus,
    $result.AppPid, $harnessPid, $errorText)
  $results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding utf8
}

$passedCount = @($results | Where-Object Passed).Count
$failedCount = $Count - $passedCount
$averageReady = [math]::Round((($results | Where-Object Passed | Measure-Object ReadyMs -Average).Average), 1)
$maxReady = ($results | Measure-Object ReadyMs -Maximum).Maximum
$averageClose = [math]::Round((($results | Where-Object GracefulClose | Measure-Object CloseMs -Average).Average), 1)
Write-Host "RESULT passed=$passedCount failed=$failedCount avgReadyMs=$averageReady maxReadyMs=$maxReady avgCloseMs=$averageClose"
Write-Host "REPORT $OutputPath"
if ($failedCount -gt 0) { exit 1 }
