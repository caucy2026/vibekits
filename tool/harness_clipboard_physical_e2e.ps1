param(
  [Parameter(Mandatory = $true)]
  [int]$AppProcessId,
  [int]$DebugPort = 9333
)

$ErrorActionPreference = 'Stop'
$nativeSource = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class HarnessClipboardNative {
  public delegate bool EnumProc(IntPtr handle, IntPtr state);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr state);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr handle, StringBuilder value, int size);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr handle, out Rect value);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr handle, ref Point value);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
}
'@
Add-Type -TypeDefinition $nativeSource -ErrorAction SilentlyContinue
[void][HarnessClipboardNative]::SetProcessDpiAwarenessContext([IntPtr](-4))

$app = Get-Process -Id $AppProcessId
$webviewWindows = [Collections.Generic.List[object]]::new()
$enumCallback = [HarnessClipboardNative+EnumProc]{
  param($handle, $state)
  $className = New-Object Text.StringBuilder 256
  [void][HarnessClipboardNative]::GetClassName($handle, $className, 256)
  if ($className.ToString() -ne 'Chrome_WidgetWin_0') { return $true }
  [uint32]$ownerProcessId = 0
  [void][HarnessClipboardNative]::GetWindowThreadProcessId($handle, [ref]$ownerProcessId)
  $owner = Get-Process -Id $ownerProcessId -ErrorAction SilentlyContinue
  if ($null -eq $owner -or $owner.ProcessName -ne 'msedgewebview2') { return $true }
  if ($owner.StartTime -lt $app.StartTime.AddSeconds(-5)) { return $true }
  $rect = New-Object HarnessClipboardNative+Rect
  [void][HarnessClipboardNative]::GetClientRect($handle, [ref]$rect)
  $area = ($rect.Right - $rect.Left) * ($rect.Bottom - $rect.Top)
  if ($area -gt 0) {
    $webviewWindows.Add([pscustomobject]@{ Handle = $handle; Area = $area })
  }
  return $true
}
[void][HarnessClipboardNative]::EnumWindows($enumCallback, [IntPtr]::Zero)
$webview = $webviewWindows | Sort-Object Area -Descending | Select-Object -First 1
if ($null -eq $webview) { throw 'VibeKits WebView2 window not found' }

$probePath = Join-Path $PSScriptRoot 'harness_dom_probe.mjs'
$probe = (& 'C:\Program Files\nodejs\node.exe' $probePath "--port=$DebugPort") | ConvertFrom-Json
if ($null -eq $probe) { throw 'Harness message editor not found' }

$client = New-Object HarnessClipboardNative+Rect
$origin = New-Object HarnessClipboardNative+Point
[void][HarnessClipboardNative]::GetClientRect($webview.Handle, [ref]$client)
[void][HarnessClipboardNative]::ClientToScreen($webview.Handle, [ref]$origin)
$clientWidth = $client.Right - $client.Left
$clientHeight = $client.Bottom - $client.Top
$clickX = [int]($origin.X + (($probe.x + ($probe.width / 2)) * $clientWidth / $probe.innerWidth))
$clickY = [int]($origin.Y + (($probe.y + ($probe.height / 2)) * $clientHeight / $probe.innerHeight))

function Send-Shortcut([byte]$key) {
  [HarnessClipboardNative]::keybd_event(0x11, 0, 0, [UIntPtr]::Zero)
  [HarnessClipboardNative]::keybd_event($key, 0, 0, [UIntPtr]::Zero)
  [HarnessClipboardNative]::keybd_event($key, 0, 2, [UIntPtr]::Zero)
  [HarnessClipboardNative]::keybd_event(0x11, 0, 2, [UIntPtr]::Zero)
}

$marker = "VIBEKITS_PHYSICAL_CLIPBOARD_$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
Set-Clipboard -Value $marker
[void][HarnessClipboardNative]::SetForegroundWindow($app.MainWindowHandle)
Start-Sleep -Milliseconds 400
[void][HarnessClipboardNative]::SetCursorPos($clickX, $clickY)
[HarnessClipboardNative]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
[HarnessClipboardNative]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 250
Send-Shortcut 0x41
Send-Shortcut 0x56
Start-Sleep -Milliseconds 800
$pasted = ((& 'C:\Program Files\nodejs\node.exe' $probePath "--port=$DebugPort") | ConvertFrom-Json).value

Set-Clipboard -Value 'VIBEKITS_COPY_SENTINEL'
Send-Shortcut 0x41
Send-Shortcut 0x43
Start-Sleep -Milliseconds 500
$copied = (Get-Clipboard -Raw).Trim()
$result = [pscustomobject]@{
  ok = ($pasted -eq $marker -and $copied -eq $marker)
  paste = [pscustomobject]@{ passed = ($pasted -eq $marker); expected = $marker; actual = $pasted }
  copy = [pscustomobject]@{ passed = ($copied -eq $marker); expected = $marker; actual = $copied }
  input = [pscustomobject]@{ x = $clickX; y = $clickY; webviewHandle = $webview.Handle.ToInt64() }
}
$result | ConvertTo-Json -Depth 4
if (-not $result.ok) { exit 1 }
