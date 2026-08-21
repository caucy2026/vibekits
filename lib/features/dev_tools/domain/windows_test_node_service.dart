import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

enum WindowsNodeCheckStatus { pass, warning, blocked, unknown }

class WindowsNodeCheck {
  const WindowsNodeCheck({
    required this.id,
    required this.label,
    required this.status,
    required this.detail,
    this.requiresElevation = false,
  });

  final String id;
  final String label;
  final WindowsNodeCheckStatus status;
  final String detail;
  final bool requiresElevation;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'status': status.name,
    'detail': detail,
    'requiresElevation': requiresElevation,
  };
}

class WindowsNodeInspection {
  const WindowsNodeInspection({
    required this.id,
    required this.inspectedAt,
    required this.rootPath,
    required this.raw,
    required this.checks,
    required this.digest,
    required this.overallStatus,
    required this.requiresElevation,
  });

  final String id;
  final DateTime inspectedAt;
  final String rootPath;
  final Map<String, Object?> raw;
  final List<WindowsNodeCheck> checks;
  final String digest;
  final WindowsNodeCheckStatus overallStatus;
  final List<String> requiresElevation;

  Map<String, Object?> toJson() => <String, Object?>{
    'inspectionId': id,
    'inspectedAt': inspectedAt.toUtc().toIso8601String(),
    'rootPath': rootPath,
    'overallStatus': overallStatus.name,
    'digest': digest,
    'requiresElevation': requiresElevation,
    'checks': checks.map((WindowsNodeCheck item) => item.toJson()).toList(),
    'facts': raw,
  };
}

class WindowsNodePlanAction {
  const WindowsNodePlanAction({
    required this.id,
    required this.currentValue,
    required this.targetValue,
    required this.reason,
    required this.risk,
    required this.requiresElevation,
    required this.requiresNetwork,
    required this.requiresRestart,
    required this.estimatedSeconds,
    required this.cancelBehavior,
    required this.rollback,
    required this.dependencies,
    required this.failureBoundary,
  });

  final String id;
  final String currentValue;
  final String targetValue;
  final String reason;
  final String risk;
  final bool requiresElevation;
  final bool requiresNetwork;
  final bool requiresRestart;
  final int estimatedSeconds;
  final String cancelBehavior;
  final String rollback;
  final List<String> dependencies;
  final String failureBoundary;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'currentValue': currentValue,
    'targetValue': targetValue,
    'reason': reason,
    'risk': risk,
    'requiresElevation': requiresElevation,
    'requiresNetwork': requiresNetwork,
    'requiresRestart': requiresRestart,
    'estimatedSeconds': estimatedSeconds,
    'cancelBehavior': cancelBehavior,
    'rollback': rollback,
    'dependencies': dependencies,
    'failureBoundary': failureBoundary,
  };
}

class WindowsNodeChangePlan {
  const WindowsNodeChangePlan({
    required this.id,
    required this.inspectionId,
    required this.inspectionDigest,
    required this.createdAt,
    required this.expiresAt,
    required this.actions,
    required this.blockers,
    required this.digest,
    required this.rollbackId,
  });

  final String id;
  final String inspectionId;
  final String inspectionDigest;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<WindowsNodePlanAction> actions;
  final List<String> blockers;
  final String digest;
  final String rollbackId;

  bool get requiresElevation =>
      actions.any((WindowsNodePlanAction action) => action.requiresElevation);
  bool get requiresNetwork =>
      actions.any((WindowsNodePlanAction action) => action.requiresNetwork);

  Map<String, Object?> toJson() => <String, Object?>{
    'planId': id,
    'inspectionId': inspectionId,
    'inspectionDigest': inspectionDigest,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'actions': actions
        .map((WindowsNodePlanAction item) => item.toJson())
        .toList(),
    'blockers': blockers,
    'requiresElevation': requiresElevation,
    'requiresNetwork': requiresNetwork,
    'rollbackId': rollbackId,
    'digest': digest,
    'executable': blockers.isEmpty && actions.isNotEmpty,
  };
}

typedef WindowsNodeInspectionProbe = Future<Map<String, Object?>> Function();

class WindowsTestNodeService {
  WindowsTestNodeService({
    WindowsNodeInspectionProbe? probe,
    DateTime Function()? clock,
    Random? random,
  }) : _probe = probe ?? _probeWindows,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  static const String requiredRoot = r'D:\KEMI-Test';
  static const int minimumFreeBytes = 30 * 1024 * 1024 * 1024;
  static const Duration planLifetime = Duration(minutes: 10);

  final WindowsNodeInspectionProbe _probe;
  final DateTime Function() _clock;
  final Random _random;
  final Map<String, WindowsNodeInspection> _inspections =
      <String, WindowsNodeInspection>{};
  final Map<String, WindowsNodeChangePlan> _plans =
      <String, WindowsNodeChangePlan>{};

  Future<WindowsNodeInspection> inspect({
    String rootPath = requiredRoot,
  }) async {
    final String normalizedRoot = _validateRoot(rootPath);
    final DateTime inspectedAt = _clock();
    final Map<String, Object?> raw = await _probe();
    final List<WindowsNodeCheck> checks = _buildChecks(raw, normalizedRoot);
    final WindowsNodeCheckStatus overall =
        checks.any(
          (WindowsNodeCheck item) =>
              item.status == WindowsNodeCheckStatus.blocked,
        )
        ? WindowsNodeCheckStatus.blocked
        : checks.any(
            (WindowsNodeCheck item) =>
                item.status == WindowsNodeCheckStatus.warning ||
                item.status == WindowsNodeCheckStatus.unknown,
          )
        ? WindowsNodeCheckStatus.warning
        : WindowsNodeCheckStatus.pass;
    final String digest = sha256
        .convert(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'rootPath': normalizedRoot,
              'facts': raw,
              'checks': checks
                  .map((WindowsNodeCheck item) => item.toJson())
                  .toList(),
            }),
          ),
        )
        .toString();
    final String id = _randomId();
    final WindowsNodeInspection inspection = WindowsNodeInspection(
      id: id,
      inspectedAt: inspectedAt,
      rootPath: normalizedRoot,
      raw: Map<String, Object?>.unmodifiable(raw),
      checks: List<WindowsNodeCheck>.unmodifiable(checks),
      digest: digest,
      overallStatus: overall,
      requiresElevation: checks
          .where((WindowsNodeCheck item) => item.requiresElevation)
          .map((WindowsNodeCheck item) => item.id)
          .toList(growable: false),
    );
    _inspections[id] = inspection;
    return inspection;
  }

  WindowsNodeChangePlan plan(String inspectionId) {
    _prune();
    final WindowsNodeInspection? inspection = _inspections[inspectionId.trim()];
    if (inspection == null) {
      throw const FormatException('体检不存在或已失效，请重新执行只读体检');
    }
    final List<String> blockers = inspection.checks
        .where(
          (WindowsNodeCheck item) =>
              item.status == WindowsNodeCheckStatus.blocked,
        )
        .map((WindowsNodeCheck item) => '${item.label}：${item.detail}')
        .toList(growable: false);
    final List<WindowsNodePlanAction> actions = _actionsFor(inspection);
    final DateTime createdAt = _clock();
    final String id = _randomId();
    final String rollbackId = _randomId();
    final String digest = sha256
        .convert(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'id': id,
              'inspectionDigest': inspection.digest,
              'actions': actions
                  .map((WindowsNodePlanAction item) => item.toJson())
                  .toList(),
              'blockers': blockers,
            }),
          ),
        )
        .toString();
    final WindowsNodeChangePlan plan = WindowsNodeChangePlan(
      id: id,
      inspectionId: inspection.id,
      inspectionDigest: inspection.digest,
      createdAt: createdAt,
      expiresAt: createdAt.add(planLifetime),
      actions: List<WindowsNodePlanAction>.unmodifiable(actions),
      blockers: List<String>.unmodifiable(blockers),
      digest: digest,
      rollbackId: rollbackId,
    );
    _plans[id] = plan;
    return plan;
  }

  WindowsNodeChangePlan requireExecutablePlan({
    required String planId,
    required String digest,
  }) {
    _prune();
    final WindowsNodeChangePlan? plan = _plans[planId.trim()];
    if (plan == null) {
      throw const FormatException('计划不存在或已过期，请重新体检');
    }
    if (plan.digest != digest.trim()) {
      throw const FormatException('计划摘要不匹配，拒绝执行');
    }
    if (plan.blockers.isNotEmpty) throw const FormatException('计划存在阻断项，不能执行');
    if (plan.actions.isEmpty) throw const FormatException('节点已达到目标状态，无需重复变更');
    return plan;
  }

  List<WindowsNodePlanAction> _actionsFor(WindowsNodeInspection inspection) {
    bool passed(String id) => inspection.checks.any(
      (WindowsNodeCheck item) =>
          item.id == id && item.status == WindowsNodeCheckStatus.pass,
    );
    final List<WindowsNodePlanAction> actions = <WindowsNodePlanAction>[];
    void add({
      required String id,
      required String current,
      required String target,
      required String reason,
      required String rollback,
      bool network = false,
      List<String> dependencies = const <String>[],
      int seconds = 30,
    }) {
      actions.add(
        WindowsNodePlanAction(
          id: id,
          currentValue: current,
          targetValue: target,
          reason: reason,
          risk: 'systemChange',
          requiresElevation: true,
          requiresNetwork: network,
          requiresRestart: false,
          estimatedSeconds: seconds,
          cancelBehavior: network ? '取消安装并重新体检真实状态' : '完成当前原子动作后停止后续动作',
          rollback: rollback,
          dependencies: dependencies,
          failureBoundary: '失败后停止依赖该动作的后续步骤，保留已完成动作和回滚记录',
        ),
      );
    }

    if (!passed('openssh')) {
      add(
        id: 'windows.openssh.install_or_repair',
        current: 'OpenSSH 证据不完整',
        target: 'sshd 二进制、服务、配置和 host key 可用',
        reason: '测试节点需要受支持的加密管理通道',
        rollback: '不自动卸载系统组件；恢复本轮修改的配置备份',
        network: true,
        seconds: 300,
      );
    }
    if (!passed('sshd_config')) {
      add(
        id: 'windows.sshd.configure',
        current: '配置缺失或不合规',
        target: '受限账户、公钥和 D 盘入口配置',
        reason: '限制节点暴露面并保留认证切换门禁',
        rollback: '恢复 sshd_config 原文件备份',
        dependencies: <String>['windows.openssh.install_or_repair'],
      );
    }
    if (!passed('sshd_service')) {
      add(
        id: 'windows.sshd.start_and_enable',
        current: '服务未运行或未自启',
        target: 'Running / Automatic',
        reason: '节点重启后仍应可验证',
        rollback: '恢复原服务状态和启动类型',
        dependencies: <String>['windows.sshd.configure'],
      );
    }
    if (!passed('network_private')) {
      add(
        id: 'windows.network.mark_private',
        current: '活跃网络不是 Private',
        target: '用户确认的活跃网卡为 Private',
        reason: 'LAN 防火墙规则仅适用于 Private',
        rollback: '恢复原 NetworkCategory',
      );
    }
    if (!passed('firewall')) {
      add(
        id: 'windows.firewall.apply_lan_rule',
        current: '缺少受限 TCP 22 规则',
        target: 'Private + 用户确认私网 CIDR（IPv4 最宽 /24）',
        reason: '只允许局域网访问，不开放公网',
        rollback: '恢复/删除 VIBEKITS-TEST-NODE-SSH-LAN 规则',
        dependencies: <String>['windows.network.mark_private'],
      );
    }
    if (!passed('test_user')) {
      add(
        id: 'windows.local_user.create_standard',
        current: 'kemi-test 不存在或状态未知',
        target: '标准本地账户，不加入 Administrators',
        reason: '隔离测试权限',
        rollback: '仅禁用本轮创建账户；删除账户需另行审批',
      );
    }
    if (!passed('authorized_keys')) {
      add(
        id: 'windows.local_user.set_authorized_keys',
        current: '尚无已验证设备公钥',
        target: '原子写入独立设备公钥并校验 ACL',
        reason: '每设备独立身份，禁止共享私钥',
        rollback: '恢复 authorized_keys 备份',
        dependencies: <String>['windows.local_user.create_standard'],
      );
    }
    if (!passed('test_root')) {
      add(
        id: 'windows.acl.apply_test_root',
        current: '目录树或 ACL 不完整',
        target: requiredRoot,
        reason: '所有测试数据限制在 D 盘专用根目录',
        rollback: '恢复原 ACL；只删除本轮登记的空目录',
      );
    }
    if (!passed('powershell7')) {
      add(
        id: 'windows.runtime.install_powershell',
        current: '系统路径缺少 pwsh',
        target: 'pwsh -NoProfile 可调用',
        reason: '远端验收命令依赖系统 PowerShell 7',
        rollback: '不自动卸载系统组件',
        network: true,
        seconds: 180,
      );
    }
    if (!passed('ac_power')) {
      add(
        id: 'windows.power.disable_ac_sleep',
        current: '接通电源时可能自动睡眠/休眠',
        target: '接通电源时测试期间不自动睡眠',
        reason: '长测试和传输不能被系统睡眠中断',
        rollback: '恢复原 AC 电源设置',
      );
    }
    return actions;
  }

  static List<WindowsNodeCheck> _buildChecks(
    Map<String, Object?> raw,
    String rootPath,
  ) {
    final List<WindowsNodeCheck> checks = <WindowsNodeCheck>[];
    final int build = _integer(raw['osBuild']);
    final String edition = '${raw['osEdition'] ?? '未知'}';
    checks.add(
      WindowsNodeCheck(
        id: 'windows_support',
        label: 'Windows 版本支持',
        status: build >= 22000
            ? WindowsNodeCheckStatus.pass
            : build >= 19041
            ? WindowsNodeCheckStatus.warning
            : WindowsNodeCheckStatus.blocked,
        detail:
            '$edition · build $build${build < 22000 ? '；Windows 10 生命周期需人工确认' : ''}',
      ),
    );
    checks.add(
      WindowsNodeCheck(
        id: 'hardware',
        label: 'CPU / RAM / GPU / 显示',
        status: _integer(raw['ramBytes']) > 0
            ? WindowsNodeCheckStatus.pass
            : WindowsNodeCheckStatus.unknown,
        detail:
            '${raw['cpu'] ?? '未知 CPU'} · RAM ${_formatBytes(_integer(raw['ramBytes']))} · '
            '${raw['gpu'] ?? '未知 GPU'} · ${raw['display'] ?? '未知显示参数'}',
      ),
    );
    final bool dExists = raw['dExists'] == true;
    final int dFree = _integer(raw['dFreeBytes']);
    checks.add(
      WindowsNodeCheck(
        id: 'd_drive',
        label: 'D 盘门禁',
        status: !dExists || dFree < minimumFreeBytes
            ? WindowsNodeCheckStatus.blocked
            : WindowsNodeCheckStatus.pass,
        detail: dExists
            ? '总量 ${_formatBytes(_integer(raw['dTotalBytes']))} · 剩余 ${_formatBytes(dFree)}'
            : 'D 盘不存在',
      ),
    );
    final String category = '${raw['networkCategory'] ?? 'Unknown'}';
    final String cidr = '${raw['candidateCidr'] ?? ''}';
    checks.add(
      WindowsNodeCheck(
        id: 'network_private',
        label: '活跃网络类别',
        status: category.toLowerCase() == 'private'
            ? WindowsNodeCheckStatus.pass
            : WindowsNodeCheckStatus.warning,
        detail: '${raw['ipv4'] ?? '无 IPv4'} · $cidr · $category',
        requiresElevation: category.toLowerCase() != 'private',
      ),
    );
    final bool sshBinary = raw['sshdBinary'] == true;
    final bool sshService = raw['sshdServiceExists'] == true;
    final String capability = '${raw['opensshCapability'] ?? 'Unknown'}';
    checks.add(
      WindowsNodeCheck(
        id: 'openssh',
        label: 'OpenSSH 综合状态',
        status: sshBinary && sshService
            ? WindowsNodeCheckStatus.pass
            : WindowsNodeCheckStatus.warning,
        detail:
            'Capability $capability · binary $sshBinary · service $sshService · version ${raw['sshdVersion'] ?? '未知'}',
        requiresElevation: true,
      ),
    );
    checks.add(
      _booleanCheck(
        raw,
        'sshd_config',
        'sshd 配置与 host key',
        'sshdConfigValid',
        elevation: true,
      ),
    );
    checks.add(
      _booleanCheck(
        raw,
        'sshd_service',
        'sshd 服务与 TCP 22',
        'sshdRunningAndListening',
        elevation: true,
      ),
    );
    checks.add(
      _booleanCheck(
        raw,
        'firewall',
        'LAN 防火墙规则',
        'firewallValid',
        elevation: true,
      ),
    );
    checks.add(
      _booleanCheck(raw, 'powershell7', 'PowerShell 7', 'powershell7'),
    );
    checks.add(_booleanCheck(raw, 'webview2', 'WebView2', 'webview2'));
    checks.add(_booleanCheck(raw, 'vcredist', 'VC++ x64 Runtime', 'vcredist'));
    checks.add(
      _booleanCheck(
        raw,
        'ac_power',
        '接通电源睡眠策略',
        'acPowerSafe',
        elevation: true,
      ),
    );
    checks.add(
      _booleanCheck(
        raw,
        'test_root',
        rootPath,
        'testRootValid',
        elevation: true,
      ),
    );
    checks.add(
      _booleanCheck(
        raw,
        'test_user',
        'kemi-test 标准账户',
        'testUserValid',
        elevation: true,
      ),
    );
    checks.add(
      _booleanCheck(
        raw,
        'authorized_keys',
        '设备公钥与 ACL',
        'authorizedKeysValid',
        elevation: true,
      ),
    );
    return checks;
  }

  static WindowsNodeCheck _booleanCheck(
    Map<String, Object?> raw,
    String id,
    String label,
    String key, {
    bool elevation = false,
  }) {
    final Object? value = raw[key];
    return WindowsNodeCheck(
      id: id,
      label: label,
      status: value == true
          ? WindowsNodeCheckStatus.pass
          : value == false
          ? WindowsNodeCheckStatus.warning
          : WindowsNodeCheckStatus.unknown,
      detail:
          '${raw['${key}Detail'] ?? (value == true
                  ? '符合要求'
                  : value == false
                  ? '需要变更'
                  : '普通权限无法确认')}',
      requiresElevation: elevation && value != true,
    );
  }

  static String _validateRoot(String value) {
    final String path = value.trim().replaceAll('/', '\\');
    if (path.toLowerCase() != requiredRoot.toLowerCase()) {
      throw const FormatException(r'测试节点根目录只能是 D:\KEMI-Test');
    }
    return requiredRoot;
  }

  void _prune() {
    final DateTime now = _clock();
    _plans.removeWhere(
      (String _, WindowsNodeChangePlan plan) => !plan.expiresAt.isAfter(now),
    );
  }

  String _randomId() =>
      base64UrlEncode(List<int>.generate(24, (_) => _random.nextInt(256)))
          .replaceAll('=', '');

  static int _integer(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;
  static String _formatBytes(int bytes) => bytes <= 0
      ? '未知'
      : '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';

  static Future<Map<String, Object?>> _probeWindows() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows 测试节点仅支持 Windows');
    }
    const String script = r'''
$ErrorActionPreference='SilentlyContinue'
$os=Get-CimInstance Win32_OperatingSystem
$cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
$gpu=Get-CimInstance Win32_VideoController | Select-Object -First 1
$display=Get-CimInstance Win32_DesktopMonitor | Select-Object -First 1
$d=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='D:'"
$route=Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1
$ip=if($route){Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '169.254.*'} | Select-Object -First 1}
$profile=if($route){Get-NetConnectionProfile -InterfaceIndex $route.InterfaceIndex | Select-Object -First 1}
$cap=Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
$svc=Get-CimInstance Win32_Service -Filter "Name='sshd'"
$sshd="$env:WINDIR\System32\OpenSSH\sshd.exe"
$config="$env:ProgramData\ssh\sshd_config"
$hostKeys=@(Get-ChildItem "$env:ProgramData\ssh\ssh_host_*_key" -File)
$listen=@(Get-NetTCPConnection -State Listen -LocalPort 22)
$pwsh=Get-Command pwsh.exe
$wv=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F1E7E843-F6AD-4A62-9A44-4D9C2181E2E0}' -ErrorAction SilentlyContinue).'pv'
$vc=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue).Installed
$root='D:\KEMI-Test'
$user=Get-LocalUser -Name 'kemi-test' -ErrorAction SilentlyContinue
$auth='C:\Users\kemi-test\.ssh\authorized_keys'
$cidr=if($ip){$parts=$ip.IPAddress.Split('.'); "$($parts[0]).$($parts[1]).$($parts[2]).0/24"}else{''}
$cidrMask=if($ip){$parts=$ip.IPAddress.Split('.'); "$($parts[0]).$($parts[1]).$($parts[2]).0/255.255.255.0"}else{''}
$sshdConfigValid=$false
if((Test-Path $sshd) -and (Test-Path $config) -and $hostKeys.Count -gt 0){
  & $sshd -t -f $config 2>$null
  $sshdConfigValid=($LASTEXITCODE -eq 0)
}
$sshFirewallRows=@()
Get-NetFirewallPortFilter -Protocol TCP -LocalPort 22 | ForEach-Object {
  $rule=$_ | Get-NetFirewallRule
  if($rule.Direction -eq 'Inbound' -and $rule.Enabled -eq 'True' -and $rule.Action -eq 'Allow'){
    $remote=@(($rule | Get-NetFirewallAddressFilter).RemoteAddress)
    $sshFirewallRows += [pscustomobject]@{name=$rule.Name;profile=[string]$rule.Profile;remote=$remote;restricted=(([string]$rule.Profile -eq 'Private') -and ($remote -contains $cidr -or $remote -contains $cidrMask))}
  }
}
$firewallRestricted=@($sshFirewallRows | Where-Object {$_.restricted}).Count -gt 0
$firewallBroad=@($sshFirewallRows | Where-Object {!$_.restricted}).Count -gt 0
$firewallValid=$firewallRestricted -and !$firewallBroad
$sleep=(powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>$null | Out-String)
$hibernate=(powercfg /query SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE 2>$null | Out-String)
function Get-AcPowerIndex([string]$text){
  $line=($text -split "`r?`n" | Where-Object {$_ -match 'Current AC Power Setting Index|当前交流电源设置索引'} | Select-Object -First 1)
  if($line -match '0x([0-9a-fA-F]+)'){return [Convert]::ToInt64($Matches[1],16)}
  return $null
}
$sleepAc=Get-AcPowerIndex $sleep
$hibernateAc=Get-AcPowerIndex $hibernate
$adminGroup=Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue
$userIsAdmin=if($user -and $adminGroup){@((Get-LocalGroupMember -Group $adminGroup -ErrorAction SilentlyContinue) | Where-Object {$_.SID.Value -eq $user.SID.Value}).Count -gt 0}else{$false}
$authAclValid=$false
if($user -and (Test-Path $auth)){
  $allowedSids=@($user.SID.Value,'S-1-5-18','S-1-5-32-544')
  $writeMask=[int]([System.Security.AccessControl.FileSystemRights]::WriteData -bor [System.Security.AccessControl.FileSystemRights]::AppendData -bor [System.Security.AccessControl.FileSystemRights]::WriteAttributes -bor [System.Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor [System.Security.AccessControl.FileSystemRights]::Delete -bor [System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor [System.Security.AccessControl.FileSystemRights]::TakeOwnership)
  $badAce=$false
  foreach($ace in (Get-Acl $auth).Access){
    try{$sid=$ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value}catch{$badAce=$true;continue}
    if($ace.AccessControlType -eq 'Allow' -and (([int]$ace.FileSystemRights -band $writeMask) -ne 0) -and $sid -notin $allowedSids){$badAce=$true}
  }
  $authAclValid=!$badAce
}
[pscustomobject]@{
 osEdition=$os.Caption;osVersion=$os.Version;osBuild=[int]$os.BuildNumber;cpu=$cpu.Name;ramBytes=[int64]$os.TotalVisibleMemorySize*1024;gpu=$gpu.Name;display="$($display.ScreenWidth)x$($display.ScreenHeight)";
 dExists=($null -ne $d);dTotalBytes=if($d){[int64]$d.Size}else{0};dFreeBytes=if($d){[int64]$d.FreeSpace}else{0};
 ipv4=if($ip){$ip.IPAddress}else{''};prefix=if($ip){$ip.PrefixLength}else{0};gateway=if($route){$route.NextHop}else{''};candidateCidr=$cidr;networkCategory=if($profile){[string]$profile.NetworkCategory}else{'Unknown'};
 opensshCapability=if($cap){$cap.State}else{'Unknown'};sshdBinary=(Test-Path $sshd);sshdVersion=if(Test-Path $sshd){(Get-Item $sshd).VersionInfo.FileVersion}else{''};sshdServiceExists=($null -ne $svc);
 sshdConfigValid=$sshdConfigValid;sshdConfigValidDetail="config=$(Test-Path $config), hostKeys=$($hostKeys.Count), syntax=$sshdConfigValid";
 sshdRunningAndListening=(($svc.State -eq 'Running') -and $listen.Count -gt 0);sshdRunningAndListeningDetail="service=$($svc.State), listeners=$($listen.Count)";
 firewallValid=$firewallValid;firewallValidDetail="sshRules=$($sshFirewallRows.Count), restricted=$firewallRestricted, broad=$firewallBroad, candidate=$cidr";
 powershell7=($null -ne $pwsh);powershell7Detail=if($pwsh){& $pwsh.Source -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'}else{'系统 PATH 未找到 pwsh'};
 webview2=![string]::IsNullOrWhiteSpace($wv);webview2Detail=$wv;vcredist=($vc -eq 1);vcredistDetail="$vc";
 acPowerSafe=($sleepAc -eq 0 -and $hibernateAc -eq 0);acPowerSafeDetail="AC sleep=$sleepAc, hibernate=$hibernateAc";
 testRootValid=(Test-Path $root);testRootValidDetail=$root;testUserValid=($null -ne $user -and $user.Enabled -and !$userIsAdmin);testUserValidDetail=if($user){"enabled=$($user.Enabled), administrator=$userIsAdmin"}else{'账户不存在'};
 authorizedKeysValid=((Test-Path $auth) -and $authAclValid -and (Get-Content $auth -ErrorAction SilentlyContinue | Where-Object {$_ -match '^ssh-(ed25519|rsa) '}).Count -gt 0);authorizedKeysValidDetail="$auth, acl=$authAclValid"
} | ConvertTo-Json -Compress -Depth 5
''';
    final List<int> bytes = <int>[];
    for (final int unit in script.codeUnits) {
      bytes
        ..add(unit & 0xff)
        ..add((unit >> 8) & 0xff);
    }
    final ProcessResult result = await Process.run('powershell.exe', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      base64.encode(bytes),
    ], runInShell: false).timeout(const Duration(seconds: 40));
    if (result.exitCode != 0) {
      throw FormatException('Windows 节点体检失败：${result.stderr}');
    }
    final Object? decoded = jsonDecode('${result.stdout}'.trim());
    if (decoded is! Map) throw const FormatException('Windows 节点体检返回格式无效');
    return decoded.map<String, Object?>(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
  }
}
