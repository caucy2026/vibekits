import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { appendFile, mkdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const endpoint = process.env.VIBEKITS_TOOL_BRIDGE_URL;
const token = process.env.VIBEKITS_TOOL_BRIDGE_TOKEN;
if (!endpoint || !token) throw new Error('VibeKits bridge is not configured');
const bridgeUrl = new URL(endpoint);
if (bridgeUrl.protocol !== 'http:' || bridgeUrl.hostname !== '127.0.0.1') {
  throw new Error('VibeKits bridge must use loopback HTTP');
}

const invoke = async (toolId, args) => {
  const response = await fetch(`${endpoint}/invoke`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ toolId, arguments: args }),
  });
  if (!response.ok) throw new Error(`VibeKits bridge HTTP ${response.status}`);
  const result = await response.json();
  if (result.ok !== true) {
    throw new Error(`${toolId}: ${result.error || 'tool failed'}`);
  }
  return result.data || {};
};

const textOf = (value) => `${value || ''}`.trim();
const bootIdFrom = (result) => textOf(result.stdout).split(/\r?\n/)[0] || '';
const rebootPattern = /Booting Linux|Linux version|Restarting system|sys\.powerctl|coldboot|watchdog.*reboot/i;
const defaultPackageName = 'com.vibekits.vibekits';
const tasks = new Map();

const sleep = (milliseconds) => new Promise((resolveWait) => setTimeout(resolveWait, milliseconds));
const publicTask = (task) => ({
  taskId: task.taskId,
  phase: task.phase,
  createdAt: task.createdAt,
  startedAt: task.startedAt || null,
  completedAt: task.completedAt || null,
  progress: task.progress,
  result: task.result || null,
  error: task.error || null,
});
const mcpResult = (value) => ({
  content: [{ type: 'text', text: JSON.stringify(value, null, 2) }],
  structuredContent: value,
});

const normalizeAdbSerial = (value) => {
  const raw = textOf(value);
  if (/^\d{1,3}$/.test(raw)) return `192.168.3.${raw}:5555`;
  if (/^\d+\.\d+\.\d+\.\d+$/.test(raw)) return `${raw}:5555`;
  return raw;
};
const requireSafeArtifactDirectory = (value, label) => {
  const directory = resolve(value);
  if (process.platform === 'win32' && !/^D:\\/i.test(directory)) {
    throw new Error(`${label} must be on D: on this Windows workstation`);
  }
  return directory;
};
const normalizeSerialPortName = (value) => {
  const port = textOf(value);
  return process.platform === 'win32' ? port.toUpperCase() : port;
};

const server = new Server(
  { name: 'vibekits-android-install-stress', version: '1.0.0' },
  {
    capabilities: { tools: {} },
    instructions:
      'Run the complete Android APK install stress test locally. Raw serial and logcat data stay in the local report and are never returned to the model.',
  },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'android__apk_install_stress_start',
      description:
        '启动可恢复的Android APK压力长任务并立即返回taskId。任务由VibeKits在本地完成APK下载校验、ADB连接、串口监控、逐轮卸载/安装/启动和异常证据采集。',
      inputSchema: {
        type: 'object',
        properties: {
          serial: { type: 'string', description: 'ADB序列号、IP，或局域网设备尾号（例如53）' },
          apkPath: { type: 'string', description: 'D盘本地APK绝对路径；与apkUrl二选一' },
          apkUrl: { type: 'string', description: 'HTTP/HTTPS APK地址；与apkPath二选一' },
          downloadDirectory: { type: 'string', description: 'APK下载目录；当前Windows工作站必须在D盘，macOS使用绝对工作区目录' },
          serialPort: { type: 'string', description: '可选串口（如COM33或/dev/cu.usbserial-*）；省略时自动发现' },
          rounds: { type: 'integer', minimum: 1, maximum: 100, default: 100 },
          sourceRoot: { type: 'string', description: '可选D盘Git源码根目录，用于异常时记录Git状态' },
          packageName: { type: 'string', description: '待卸载和验证的Android应用包名' },
          mainActivity: { type: 'string', description: '可选完整组件；省略时安装后由Package Manager解析' },
        },
        required: ['serial', 'packageName'],
        additionalProperties: false,
      },
      annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true },
    },
    {
      name: 'android__apk_install_stress_status',
      description: '查询压力长任务；waitSeconds可长轮询，返回有界进度、结果路径和异常摘要。',
      inputSchema: {
        type: 'object',
        properties: {
          taskId: { type: 'string' },
          waitSeconds: { type: 'integer', minimum: 0, maximum: 45, default: 20 },
        },
        required: ['taskId'],
        additionalProperties: false,
      },
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    {
      name: 'android__apk_install_stress_cancel',
      description: '请求在当前原子步骤结束后安全取消压力长任务，并保留已完成轮次和本地证据。',
      inputSchema: {
        type: 'object',
        properties: { taskId: { type: 'string' } },
        required: ['taskId'],
        additionalProperties: false,
      },
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    },
    {
      name: 'android__apk_install_stress_100',
      description:
        '在 VibeKits 本地后台逐轮卸载、全新安装并启动 APK 100 次，同时用独立串口线程监听系统状态并检查 boot_id；发现重启立即保存末尾线程和日志后停止。',
      inputSchema: {
        type: 'object',
        properties: {
          serial: { type: 'string' },
          apkPath: { type: 'string' },
          serialPort: { type: 'string' },
          rounds: { type: 'integer', minimum: 1, maximum: 100 },
        },
        required: ['serial', 'apkPath', 'serialPort'],
        additionalProperties: false,
      },
      annotations: {
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false,
      },
    },
  ],
}));

const executeStress = async (argumentsValue, task = null) => {
  const serial = normalizeAdbSerial(argumentsValue?.serial);
  const packageName = textOf(argumentsValue?.packageName || defaultPackageName);
  let mainActivity = textOf(argumentsValue?.mainActivity);
  let apkPath = textOf(argumentsValue?.apkPath);
  const apkUrl = textOf(argumentsValue?.apkUrl);
  let downloadEvidence = null;
  let serialPort = normalizeSerialPortName(argumentsValue?.serialPort);
  if (!apkPath && apkUrl) {
    const downloadDirectory = requireSafeArtifactDirectory(
      textOf(argumentsValue?.downloadDirectory || join(process.cwd(), 'tmp', 'downloads')),
      'downloadDirectory',
    );
    const downloaded = await invoke('vibekits.network.download', {
      url: apkUrl,
      outputDirectory: downloadDirectory,
      overwrite: true,
      timeoutSeconds: 1800,
    });
    apkPath = textOf(downloaded.outputPath);
    if (textOf(downloaded.artifactType).toLowerCase() !== 'android-apk') {
      throw new Error(`Downloaded artifact type is ${textOf(downloaded.artifactType) || 'unknown'}, expected android-apk`);
    }
    downloadEvidence = {
      outputPath: apkPath,
      bytes: Number(downloaded.bytes || 0),
      sha256: textOf(downloaded.sha256),
      statusCode: Number(downloaded.statusCode || 0),
      finalUrl: textOf(downloaded.finalUrl),
      artifactType: textOf(downloaded.artifactType),
    };
  }
  apkPath = resolve(apkPath);
  const rounds = Math.min(100, Math.max(1, Number(argumentsValue?.rounds || 100)));
  if (!serial || !/^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$/.test(packageName) || !apkPath.toLowerCase().endsWith('.apk')) {
    throw new Error('Invalid stress-test target, APK, or serial port');
  }

  const reportRoot = requireSafeArtifactDirectory(
    process.env.VIBEKITS_STRESS_REPORT_DIR || join(process.cwd(), 'tmp', 'stress'),
    'Stress report directory',
  );
  await mkdir(reportRoot, { recursive: true });
  const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
  const detailPath = join(reportRoot, `android-install-stress-${stamp}.jsonl`);
  const summaryPath = join(reportRoot, `android-install-stress-${stamp}.summary.json`);
  const startedAt = new Date();
  let adbSessionId = '';
  let serialSessionId = '';
  let initialBootId = '';
  let completed = 0;
  let installsPassed = 0;
  let installsFailed = 0;
  let uninstallsPassed = 0;
  let uninstallsFailed = 0;
  let launchesPassed = 0;
  let launchesFailed = 0;
  let processChecksPassed = 0;
  let rebootDetected = false;
  let rebootReason = '';
  let serialBytesReceived = 0;
  let serialReadFailures = 0;
  let logcatSamples = 0;
  let logcatBytes = 0;
  const anomalyCounts = { crash: 0, anr: 0, watchdog: 0, reboot: 0, decoder: 0, wifiHal: 0, selinux: 0 };
  let gitEvidence = null;

  const classify = (data) => {
    const value = `${data || ''}`;
    const patterns = {
      crash: /FATAL EXCEPTION|Fatal signal/gi,
      anr: /ANR in |am_anr/gi,
      watchdog: /WATCHDOG KILLING SYSTEM PROCESS/gi,
      reboot: /Booting Linux|Restarting system|sys\.powerctl/gi,
      decoder: /OMXVDEC|decoder error|fill_buffer_done_set_speed/gi,
      wifiHal: /WifiVendorHal.*ERROR_UNKNOWN/gi,
      selinux: /avc:\s+denied/gi,
    };
    for (const [kind, pattern] of Object.entries(patterns)) {
      anomalyCounts[kind] += value.match(pattern)?.length || 0;
    }
  };

  const save = async (entry) => {
    await appendFile(detailPath, `${JSON.stringify(entry)}\n`, 'utf8');
  };

  const shell = (shellArguments) => invoke('vibekits.adb.shell', {
    serial,
    arguments: shellArguments,
  });

  const drainSerial = async (round, stage) => {
    try {
      const read = await invoke('vibekits.serial.session_read', {
        sessionId: serialSessionId,
        mode: 'text',
        clear: true,
      });
      const data = textOf(read.data);
      const bytes = Buffer.byteLength(data);
      serialBytesReceived += bytes;
      if (bytes > 0) {
        classify(data);
        await save({ type: 'serial-stage', round, stage, at: new Date().toISOString(), bytes, data });
      }
      return data;
    } catch (error) {
      serialReadFailures += 1;
      await save({ type: 'serial-stage-error', round, stage, at: new Date().toISOString(), error: `${error}` });
      return '';
    }
  };

  const readBootId = async () => bootIdFrom(
    await shell(['cat', '/proc/sys/kernel/random/boot_id']),
  );

  const captureFailureContext = async (round, reason) => {
    await save({ type: 'failure-context-start', round, reason, at: new Date().toISOString() });
    await drainSerial(round, 'failure-tail');
    const diagnostics = [
      ['threads', ['ps', '-A', '-T']],
      ['activity-processes', ['dumpsys', 'activity', 'processes']],
      ['activity-exit-info', ['dumpsys', 'activity', 'exit-info', packageName]],
      ['window-state', ['dumpsys', 'window', 'windows']],
      ['package-state', ['dumpsys', 'package', packageName]],
      ['pstore-list', ['ls', '-l', '/sys/fs/pstore']],
      ['kernel-tail', ['dmesg', '-T']],
    ];
    for (const [name, shellArguments] of diagnostics) {
      try {
        const result = await shell(shellArguments);
        await save({ type: 'failure-diagnostic', round, name, at: new Date().toISOString(), result });
      } catch (error) {
        await save({ type: 'failure-diagnostic-error', round, name, at: new Date().toISOString(), error: `${error}` });
      }
    }
    try {
      const logcat = await invoke('vibekits.adb.logcat', { serial, lines: 2000 });
      await save({ type: 'failure-logcat', round, at: new Date().toISOString(), logcat });
    } catch (error) {
      await save({ type: 'failure-logcat-error', round, at: new Date().toISOString(), error: `${error}` });
    }
  };

  try {
    await invoke('vibekits.adb.connect', { address: serial });
    const ports = await invoke('vibekits.serial.list_ports', {});
    let serialSettings = { baudRate: 115200, dataBits: 8, stopBits: 1, parity: 'none', flowControl: 'none' };
    if (!serialPort) {
      const detected = await invoke('vibekits.serial.auto_detect', { listenMs: 3000 });
      serialPort = normalizeSerialPortName(detected.port || detected.selected?.portName);
      serialSettings = { ...serialSettings, ...(detected.selected || {}) };
    }
    const descriptor = (ports.ports || []).find(
      (port) => normalizeSerialPortName(port.name) === serialPort,
    );
    if (!descriptor) throw new Error(`${serialPort} is not enumerated`);
    await save({ type: 'serial-port', descriptor });

    const serialSession = await invoke('vibekits.serial.session_open', {
      port: serialPort,
      baudRate: Number(serialSettings.baudRate || 115200),
      dataBits: Number(serialSettings.dataBits || 8),
      stopBits: Number(serialSettings.stopBits || 1),
      parity: textOf(serialSettings.parity || 'none'),
      // Match the verified SecureCRT profile used by the attached COM33
      // console: 115200/8N1 with DTR/DSR, RTS/CTS and XON/XOFF all disabled.
      flowControl: textOf(serialSettings.flowControl || 'none'),
    });
    serialSessionId = textOf(serialSession.sessionId);
    const adbSession = await invoke('vibekits.adb.session_open', {
      serial,
      heartbeatSeconds: 3,
    });
    adbSessionId = textOf(adbSession.sessionId);
    await invoke('vibekits.serial.session_read', {
      sessionId: serialSessionId,
      mode: 'text',
      clear: true,
    });
    // The connected Android console can be quiet while the system is healthy.
    // Send one harmless echo before the stress loop to prove that this is the
    // active RX/TX console, then keep the remainder of the test read-only.
    await invoke('vibekits.serial.session_write', {
      sessionId: serialSessionId,
      data: 'echo VIBEKITS_SERIAL_MONITOR_READY',
      mode: 'text',
      lineEnding: 'cr',
    });
    await new Promise((resolveWait) => setTimeout(resolveWait, 600));
    const serialProbe = await invoke('vibekits.serial.session_read', {
      sessionId: serialSessionId,
      mode: 'text',
      clear: true,
    });
    const serialProbeData = textOf(serialProbe.data);
    const serialProbeBytes = Buffer.byteLength(serialProbeData);
    serialBytesReceived += serialProbeBytes;
    await save({
      type: 'serial-probe',
      at: new Date().toISOString(),
      bytes: serialProbeBytes,
      data: serialProbeData,
      roundTripConfirmed: serialProbeData.includes('VIBEKITS_SERIAL_MONITOR_READY'),
    });
    initialBootId = await readBootId();
    if (!initialBootId) throw new Error('Initial Android boot_id is empty');
    await save({ type: 'baseline', at: new Date().toISOString(), initialBootId });

    for (let round = 1; round <= rounds; round += 1) {
      if (task?.cancelRequested) {
        rebootReason = 'cancelled by request';
        break;
      }
      if (task) task.progress = { completedRounds: completed, requestedRounds: rounds, currentRound: round };
      const roundStarted = Date.now();
      let installOk = false;
      let installError = '';
      let uninstallOk = false;
      let uninstallError = '';
      let launchOk = false;
      let launchError = '';
      let processId = '';
      let currentBootId = '';
      let serialData = '';
      try {
        const uninstall = await shell(['pm', 'uninstall', packageName]);
        uninstallOk = textOf(uninstall.stdout).includes('Success');
        if (!uninstallOk) throw new Error(textOf(uninstall.stdout) || 'pm uninstall did not return Success');
        uninstallsPassed += 1;
      } catch (error) {
        uninstallsFailed += 1;
        uninstallError = `${error}`;
      }
      serialData += await drainSerial(round, 'after-uninstall');
      try {
        await invoke('vibekits.adb.install_apk', {
          serial,
          apkPath,
          replace: false,
        });
        installOk = true;
        installsPassed += 1;
      } catch (error) {
        installsFailed += 1;
        installError = `${error}`;
        try {
          await invoke('vibekits.adb.connect', { address: serial });
        } catch (_) {
          // The failed reconnect is captured by the APP tool activity log.
        }
      }
      serialData += await drainSerial(round, 'after-install');
      if (installOk) {
        try {
          if (!mainActivity) {
            const resolvedActivity = await shell(['cmd', 'package', 'resolve-activity', '--brief', packageName]);
            mainActivity = textOf(resolvedActivity.stdout).split(/\r?\n/).find((line) => line.includes('/')) || '';
            if (!mainActivity) throw new Error(`No launchable activity resolved for ${packageName}`);
          }
          const launch = await shell(['am', 'start', '-W', '-n', mainActivity]);
          const launchText = `${launch.stdout || ''}\n${launch.stderr || ''}`;
          launchOk = /Status:\s*ok/i.test(launchText) || /Activity:/i.test(launchText);
          if (!launchOk) throw new Error(launchText.trim() || 'am start returned no success marker');
          await new Promise((resolveWait) => setTimeout(resolveWait, 1200));
          processId = textOf((await shell(['pidof', packageName])).stdout);
          if (!processId) throw new Error('APP process was not alive after launch');
          launchesPassed += 1;
          processChecksPassed += 1;
        } catch (error) {
          launchesFailed += 1;
          launchError = `${error}`;
        }
      }
      serialData += await drainSerial(round, 'after-launch');
      try {
        currentBootId = await readBootId();
      } catch (_) {
        // A wireless ADB connection can briefly disappear while the device is
        // rebooting. Reconnect once and compare the persistent boot_id.
        try {
          await new Promise((resolveWait) => setTimeout(resolveWait, 1500));
          await invoke('vibekits.adb.connect', { address: serial });
          currentBootId = await readBootId();
        } catch (_) {
          currentBootId = '';
        }
      }
      if (round === 1 || round % 10 === 0) {
        try {
          const logcat = await invoke('vibekits.adb.logcat', {
            serial,
            lines: 200,
          });
          const logcatText = `${logcat.stdout || ''}${logcat.stderr || ''}`;
          logcatSamples += 1;
          logcatBytes += Buffer.byteLength(logcatText);
          classify(logcatText);
          await save({
            type: 'system-logcat',
            round,
            at: new Date().toISOString(),
            bytes: Buffer.byteLength(logcatText),
            data: logcatText,
          });
        } catch (error) {
          await save({
            type: 'system-logcat-error',
            round,
            at: new Date().toISOString(),
            error: `${error}`,
          });
        }
      }
      completed = round;
      const bootChanged = Boolean(currentBootId && currentBootId !== initialBootId);
      const marker = serialData.match(rebootPattern)?.[0] || '';
      await save({
        type: 'round',
        round,
        at: new Date().toISOString(),
        elapsedMs: Date.now() - roundStarted,
        uninstallOk,
        uninstallError,
        installOk,
        installError,
        launchOk,
        launchError,
        processId,
        bootId: currentBootId,
        bootChanged,
        serialBytes: Buffer.byteLength(serialData),
        serialData,
        rebootMarker: marker,
      });
      if (bootChanged || marker) {
        rebootDetected = true;
        rebootReason = bootChanged ? 'boot_id changed' : `serial marker: ${marker}`;
        await captureFailureContext(round, rebootReason);
        break;
      }
    }
  } catch (error) {
    await save({ type: 'fatal', at: new Date().toISOString(), error: `${error}` });
    rebootReason = `fatal: ${error}`;
  } finally {
    if (adbSessionId) {
      try {
        await invoke('vibekits.adb.session_close', { sessionId: adbSessionId });
      } catch (_) {}
    }
    if (serialSessionId) {
      try {
        const tail = await invoke('vibekits.serial.session_read', {
          sessionId: serialSessionId,
          mode: 'text',
          clear: true,
        });
        const tailData = `${tail.data || ''}`;
        serialBytesReceived += Buffer.byteLength(tailData);
        await save({ type: 'serial-tail', at: new Date().toISOString(), data: tailData });
      } catch (_) {}
      try {
        await invoke('vibekits.serial.session_close', { sessionId: serialSessionId });
      } catch (_) {}
    }
  }

  const sourceRoot = textOf(argumentsValue?.sourceRoot);
  const anomalyTotal = Object.values(anomalyCounts).reduce((sum, value) => sum + value, 0);
  if (sourceRoot && (rebootDetected || anomalyTotal > 0 || completed !== rounds)) {
    try {
      gitEvidence = await invoke('vibekits.git.inspect', { path: sourceRoot });
      await save({ type: 'git-evidence', at: new Date().toISOString(), sourceRoot, result: gitEvidence });
    } catch (error) {
      gitEvidence = { error: `${error}` };
      await save({ type: 'git-evidence-error', at: new Date().toISOString(), sourceRoot, error: `${error}` });
    }
  }

  const summary = {
    startedAt: startedAt.toISOString(),
    completedAt: new Date().toISOString(),
    serial,
    apkPath,
    downloadEvidence,
    serialPort,
    packageName,
    mainActivity,
    requestedRounds: rounds,
    completed,
    installsPassed,
    installsFailed,
    uninstallsPassed,
    uninstallsFailed,
    launchesPassed,
    launchesFailed,
    processChecksPassed,
    rebootDetected,
    serialBytesReceived,
    serialReadFailures,
    logcatSamples,
    logcatBytes,
    anomalyCounts,
    gitEvidenceCaptured: gitEvidence !== null,
    gitSourceRoot: sourceRoot || null,
    recommendations: [
      ...(anomalyCounts.decoder > 0 ? ['检查设备硬件视频解码缓冲区长度校验、空帧处理和解码器重建时序'] : []),
      ...(anomalyCounts.wifiHal > 0 ? ['检查Wi-Fi Vendor HAL返回值处理及ADB断线后的退避重连'] : []),
      ...(anomalyCounts.selinux > 0 ? ['为/proc性能采样补充最小SELinux策略，或在拒绝时降级为公开系统指标'] : []),
      ...(anomalyCounts.crash > 0 || anomalyCounts.anr > 0 ? ['使用本地failure-logcat和activity-exit-info定位首个应用崩溃或ANR调用栈'] : []),
      ...(rebootDetected ? ['结合boot_id、pstore、dmesg和串口尾部定位内核重启原因'] : []),
    ],
    conclusion: rebootDetected
      ? `Stopped at round ${completed}: ${rebootReason}; serial, Logcat and final thread state saved locally`
      : completed === rounds
        ? `Completed ${rounds} fresh uninstall/install/launch rounds without a detected reboot`
        : `Stopped early: ${rebootReason || 'unknown failure'}`,
    detailPath,
  };
  await writeFile(summaryPath, JSON.stringify(summary, null, 2), 'utf8');
  return {
    isError: completed !== rounds || uninstallsFailed > 0 || installsFailed > 0 || launchesFailed > 0 || rebootDetected,
    content: [{ type: 'text', text: JSON.stringify({ ...summary, summaryPath }, null, 2) }],
    structuredContent: { ...summary, summaryPath },
  };
};

server.setRequestHandler(CallToolRequestSchema, async ({ params }) => {
  if (params.name === 'android__apk_install_stress_100') return executeStress(params.arguments);
  if (params.name === 'android__apk_install_stress_start') {
    const normalizedSerial = normalizeAdbSerial(params.arguments?.serial);
    const existing = [...tasks.values()].find(
      (candidate) => candidate.serial === normalizedSerial
        && (candidate.phase === 'queued' || candidate.phase === 'running'),
    );
    if (existing) return mcpResult({ ...publicTask(existing), reused: true });
    const taskId = `android-stress-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
    const task = {
      taskId,
      serial: normalizedSerial,
      phase: 'queued',
      createdAt: new Date().toISOString(),
      progress: { completedRounds: 0, requestedRounds: Number(params.arguments?.rounds || 100), currentRound: 0 },
      cancelRequested: false,
    };
    tasks.set(taskId, task);
    void (async () => {
      task.phase = 'running';
      task.startedAt = new Date().toISOString();
      try {
        task.result = await executeStress(params.arguments, task);
        const summary = task.result?.structuredContent || {};
        task.progress = {
          completedRounds: Number(summary.completed || task.progress.completedRounds || 0),
          requestedRounds: Number(summary.requestedRounds || task.progress.requestedRounds || 0),
          currentRound: Number(summary.completed || task.progress.currentRound || 0),
        };
        task.phase = task.cancelRequested ? 'cancelled' : (task.result?.isError ? 'failed' : 'completed');
      } catch (error) {
        task.error = `${error}`;
        task.phase = task.cancelRequested ? 'cancelled' : 'failed';
      } finally {
        task.completedAt = new Date().toISOString();
      }
    })();
    return mcpResult(publicTask(task));
  }
  if (params.name === 'android__apk_install_stress_status') {
    const task = tasks.get(textOf(params.arguments?.taskId));
    if (!task) throw new Error('Unknown stress taskId');
    const waitSeconds = Math.min(45, Math.max(0, Number(params.arguments?.waitSeconds || 20)));
    const deadline = Date.now() + waitSeconds * 1000;
    while (task.phase === 'queued' || task.phase === 'running') {
      if (Date.now() >= deadline) break;
      await sleep(250);
    }
    return mcpResult(publicTask(task));
  }
  if (params.name === 'android__apk_install_stress_cancel') {
    const task = tasks.get(textOf(params.arguments?.taskId));
    if (!task) throw new Error('Unknown stress taskId');
    task.cancelRequested = true;
    return mcpResult(publicTask(task));
  }
  throw new Error(`Unknown tool: ${params.name}`);
});

await server.connect(new StdioServerTransport());
