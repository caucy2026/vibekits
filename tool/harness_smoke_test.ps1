param(
  [string]$RuntimeDirectory = 'build\windows\x64\runner\Debug\tools\harness',
  [string]$Workspace = '.'
)

$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VibekitsCredentialReader {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  private struct CREDENTIAL {
    public UInt32 Flags; public UInt32 Type; public IntPtr TargetName;
    public IntPtr Comment; public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public UInt32 CredentialBlobSize; public IntPtr CredentialBlob;
    public UInt32 Persist; public UInt32 AttributeCount; public IntPtr Attributes;
    public IntPtr TargetAlias; public IntPtr UserName;
  }
  [DllImport("Advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
  private static extern bool CredRead(string target, UInt32 type, UInt32 flags, out IntPtr credential);
  [DllImport("Advapi32.dll", SetLastError=false)]
  private static extern void CredFree(IntPtr buffer);
  public static string Read(string target) {
    IntPtr pointer;
    if (!CredRead(target, 1, 0, out pointer)) return null;
    try {
      CREDENTIAL value = Marshal.PtrToStructure<CREDENTIAL>(pointer);
      if (value.CredentialBlobSize == 0) return "";
      return Marshal.PtrToStringUni(value.CredentialBlob, (int)value.CredentialBlobSize / 2);
    } finally { CredFree(pointer); }
  }
}
'@

$key = [VibekitsCredentialReader]::Read('Vibekits/Database/deepseek-api-key')
if ([string]::IsNullOrWhiteSpace($key)) { throw 'HARNESS_SMOKE_NO_SAVED_KEY' }
$runtime = (Resolve-Path -LiteralPath $RuntimeDirectory).Path
$node = Join-Path $runtime 'node.exe'
$cli = Join-Path $runtime 'node_modules\@deepseek-ai\dsh\lib\bin.js'
$profile = Join-Path $runtime 'profile'
$work = (Resolve-Path -LiteralPath $Workspace).Path

$start = [System.Diagnostics.ProcessStartInfo]::new()
$start.FileName = $node
$start.WorkingDirectory = $work
$start.UseShellExecute = $false
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.CreateNoWindow = $true
$start.Arguments = '"' + $cli + '" --profile headless "Reply with VIBEKITS_HARNESS_OK only. Do not call tools."'
$start.Environment['DEEPSEEK_API_KEY'] = $key
$start.Environment['DEEPSEEK_BASE_URL'] = 'https://api.deepseek.com'
$start.Environment['DSH_HOME'] = $profile
$start.Environment['DSH_TELEMETRY_MODE'] = 'DISABLED'
$start.Environment['DSH_PERMISSION_MODE'] = 'workspace-write'

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $start
if (-not $process.Start()) { throw 'HARNESS_SMOKE_START_FAILED' }
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
if (-not $process.WaitForExit(120000)) {
  $process.Kill($true)
  throw 'HARNESS_SMOKE_TIMEOUT'
}
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderrText = $stderrTask.GetAwaiter().GetResult()
Write-Host "HARNESS_EXIT=$($process.ExitCode)"
if ($stdout) { Write-Host $stdout.Trim() }
if ($stderrText) { Write-Host $stderrText.Trim() }
if ($process.ExitCode -ne 0 -or -not $stdout.Contains('VIBEKITS_HARNESS_OK')) {
  throw 'HARNESS_SMOKE_RESPONSE_INVALID'
}
Write-Host 'HARNESS_SMOKE_PASSED'
