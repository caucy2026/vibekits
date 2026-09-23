#ifndef ComponentId
  #error ComponentId is required
#endif
#ifndef VersionCode
  #error VersionCode is required
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
[Setup]
AppId=com.caucy.vibekits.component.{#ComponentId}
AppName=VibeKits 功能组件 {#ComponentId}
AppVersion={#VersionCode}
AppPublisher=Newlink
DefaultDirName={localappdata}\Vibekits\components\{#ComponentId}\{#VersionCode}
DisableDirPage=yes
DisableProgramGroupPage=yes
CreateAppDir=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Uninstallable=no
OutputDir={#OutputDir}
OutputBaseFilename=Vibekits-{#ComponentId}-windows-x64-{#VersionCode}-setup
Compression=lzma2/fast
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Code]
const HostKey = 'Software\KEMI\AppMarket\com.caucy.vibekits';
function InitializeSetup(): Boolean;
var HostExe: String; HostVersion: Cardinal;
begin
  Result := RegQueryStringValue(HKCU, HostKey, 'Executable', HostExe);
  if not Result then Result := RegQueryStringValue(HKLM64, HostKey, 'Executable', HostExe);
  Result := Result and FileExists(HostExe);
  if Result then begin
    Result := RegQueryDWordValue(HKCU, HostKey, 'VersionCode', HostVersion);
    if not Result then Result := RegQueryDWordValue(HKLM64, HostKey, 'VersionCode', HostVersion);
    Result := Result and (HostVersion >= 2226);
  end;
  if not Result then
    SuppressibleMsgBox('这是 VibeKits 功能组件，不能单独使用。请先从 KEMI 商城安装或更新 VibeKits 主程序至 2226 或更高版本。', mbError, MB_OK, IDOK);
end;
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  WizardForm.DirEdit.Text := ExpandConstant('{localappdata}\Vibekits\components\{#ComponentId}\{#VersionCode}');
  if FileExists(ExpandConstant('{app}\component-manifest.json')) then
    Result := '此版本组件目录已存在，请在主程序中检查组件状态。';
end;
function ProbeRuntime(Name, Args: String): Boolean;
var Code: Integer;
begin
  Result := Exec(ExpandConstant('{app}\') + Name, Args, ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Code);
  if Result then Result := Code = 0;
end;
procedure CurStepChanged(CurStep: TSetupStep);
var Root, Active, Backup, Pending: String;
begin
  if CurStep = ssPostInstall then begin
    #if ComponentId == "virtual_machine"
    if not ProbeRuntime('qemu\qemu-system-x86_64.exe', '--version') or
       not ProbeRuntime('qemu\qemu-img.exe', '--version') then
      RaiseException('虚拟机组件无法运行，原激活版本保持不变。');
#else
    if not ProbeRuntime('mihomo\mihomo.exe', '-v') then
      RaiseException('网络代理组件无法运行，原激活版本保持不变。');
#endif
    Root := ExpandConstant('{localappdata}\Vibekits\components\{#ComponentId}');
    Active := Root + '\active.json';
    Backup := Root + '\active.previous.json';
    Pending := Root + '\active.pending.json';
    if not SaveStringToFile(Pending, '{"version_code":{#VersionCode}}', False) then
      RaiseException('无法写入组件激活记录，原版本保持不变。');
    if FileExists(Backup) then DeleteFile(Backup);
    if FileExists(Active) and not RenameFile(Active, Backup) then
      RaiseException('组件正在更新，请稍后重试。');
    if not RenameFile(Pending, Active) then begin
      if FileExists(Backup) then RenameFile(Backup, Active);
      RaiseException('组件激活失败，已恢复原版本。');
    end;
  end;
end;
