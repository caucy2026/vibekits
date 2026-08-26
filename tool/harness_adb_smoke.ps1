$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VibekitsHarnessKeyReader {
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
  [DllImport("Advapi32.dll")] private static extern void CredFree(IntPtr buffer);
  public static string Read(string target) {
    IntPtr pointer;
    if (!CredRead(target, 1, 0, out pointer)) return null;
    try {
      CREDENTIAL value = Marshal.PtrToStructure<CREDENTIAL>(pointer);
      return value.CredentialBlobSize == 0 ? "" :
        Marshal.PtrToStringUni(value.CredentialBlob, (int)value.CredentialBlobSize / 2);
    } finally { CredFree(pointer); }
  }
}
'@

$key = [VibekitsHarnessKeyReader]::Read('Vibekits/Database/deepseek-api-key')
if ([string]::IsNullOrWhiteSpace($key)) { throw 'HARNESS_ADB_NO_SAVED_KEY' }
$env:DEEPSEEK_API_KEY = $key
try {
  & "$PSScriptRoot\..\native\harness\windows\runtime\node.exe" "$PSScriptRoot\harness_adb_smoke.mjs"
  if ($LASTEXITCODE -ne 0) { throw "HARNESS_ADB_SMOKE_EXIT_$LASTEXITCODE" }
} finally {
  Remove-Item Env:DEEPSEEK_API_KEY -ErrorAction SilentlyContinue
  $key = $null
}
