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
const packageName = 'com.vibekits.vibekits';
const mainActivity = `${packageName}/.MainActivity`;

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

server.setRequestHandler(CallToolRequestSchema, async ({ params }) => {
  if (params.name !== 'android__apk_install_stress_100') {
    throw new Error(`Unknown tool: ${params.name}`);
  }
  const serial = textOf(params.arguments?.serial);
  const apkPath = resolve(textOf(params.arguments?.apkPath));
  const serialPort = textOf(params.arguments?.serialPort).toUpperCase();
  const rounds = Math.min(100, Math.max(1, Number(params.arguments?.rounds || 100)));
  if (!serial || !apkPath.toLowerCase().endsWith('.apk') || !/^COM\d+$/.test(serialPort)) {
    throw new Error('Invalid stress-test target, APK, or serial port');
  }

  const reportRoot = process.env.VIBEKITS_STRESS_REPORT_DIR
    || join(process.env.LOCALAPPDATA || process.cwd(), 'Vibekits', 'Harness', 'stress');
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
    const descriptor = (ports.ports || []).find(
      (port) => textOf(port.name).toUpperCase() === serialPort,
    );
    if (!descriptor) throw new Error(`${serialPort} is not enumerated`);
    await save({ type: 'serial-port', descriptor });

    const serialSession = await invoke('vibekits.serial.session_open', {
      port: serialPort,
      baudRate: 115200,
      dataBits: 8,
      stopBits: 1,
      parity: 'none',
      // Match the verified SecureCRT profile used by the attached COM33
      // console: 115200/8N1 with DTR/DSR, RTS/CTS and XON/XOFF all disabled.
      flowControl: 'none',
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

  const summary = {
    startedAt: startedAt.toISOString(),
    completedAt: new Date().toISOString(),
    serial,
    apkPath,
    serialPort,
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
});

await server.connect(new StdioServerTransport());
