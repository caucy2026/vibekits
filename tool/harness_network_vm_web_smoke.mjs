import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const release = join(root, 'build', 'windows', 'x64', 'runner', 'Release');
const runtime = join(root, 'native', 'harness', 'windows', 'runtime');
const node = join(runtime, 'node.exe');
const cli = join(runtime, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js');
const mcp = join(runtime, 'vibekits-mcp-server.mjs');
const mihomo = join(release, 'tools', 'mihomo', 'mihomo.exe');
const qemu = join(release, 'tools', 'qemu', 'qemu-system-x86_64.exe');
const acceptance = join(root, 'build', 'acceptance');
const config = join(acceptance, 'mihomo-direct-smoke.yaml');
const dataDirectory = join(acceptance, 'harness-mihomo-data');
const disk = join(acceptance, 'harness-vm-smoke.qcow2');
const evidenceFile = join(acceptance, 'harness-network-vm-tool-activity.json');
const harnessHome = join(process.env.LOCALAPPDATA, 'Vibekits', 'Harness');
const token = randomBytes(32).toString('base64url');
const webOnly = process.argv.includes('--web-only');
if (!process.env.DEEPSEEK_API_KEY) throw new Error('HARNESS_NO_SAVED_KEY');
await mkdir(acceptance, { recursive: true });
await mkdir(dataDirectory, { recursive: true });

let proxyProcess;
let vmProcess;
const activity = [];
const tools = [
  tool('vibekits.runtime.inspect', 'Inspect bundled Mihomo and QEMU versions.', {}),
  tool('vibekits.runtime.status', 'Read Mihomo/QEMU process status and PIDs.', {}),
  tool('vibekits.proxy.start', 'Start bundled Mihomo using an explicit YAML config.', {
    configPath: { type: 'string' }, dataDirectory: { type: 'string' },
  }, ['configPath', 'dataDirectory']),
  tool('vibekits.proxy.stop', 'Stop Mihomo started by Vibekits.', {}),
  tool('vibekits.vm.start', 'Start bundled QEMU with an explicit disk.', {
    diskPath: { type: 'string' }, memoryMiB: { type: 'integer' }, cpuCount: { type: 'integer' },
  }, ['diskPath']),
  tool('vibekits.vm.stop', 'Stop QEMU started by Vibekits.', {}),
];

function tool(id, description, properties, required = []) {
  return { id, description, inputSchema: {
    type: 'object', properties, ...(required.length ? { required } : {}), additionalProperties: false,
  }};
}

function run(executable, args) {
  const result = spawnSync(executable, args, { encoding: 'utf8', windowsHide: true, shell: false });
  if (result.status !== 0) throw new Error(`${executable} exited ${result.status}: ${result.stderr}`);
  return `${result.stdout}\n${result.stderr}`.trim();
}

function start(executable, args, cwd) {
  const child = spawn(executable, args, { cwd, windowsHide: true, shell: false, stdio: ['ignore', 'pipe', 'pipe'] });
  child.stdout.resume();
  child.stderr.resume();
  return child;
}

async function stop(child) {
  if (!child || child.exitCode !== null) return;
  child.kill();
  await Promise.race([
    new Promise((resolveExit) => child.once('exit', resolveExit)),
    new Promise((resolveTimeout) => setTimeout(resolveTimeout, 3000)),
  ]);
  if (child.exitCode === null) child.kill('SIGKILL');
}

async function invoke(toolId, args) {
  const startedAt = new Date();
  let data;
  if (toolId === 'vibekits.runtime.inspect') {
    data = {
      mihomo: run(mihomo, ['-v']).split(/\r?\n/)[0],
      qemu: run(qemu, ['--version']).split(/\r?\n/)[0],
    };
  } else if (toolId === 'vibekits.runtime.status') {
    data = {
      mihomoRunning: Boolean(proxyProcess && proxyProcess.exitCode === null),
      mihomoPid: proxyProcess?.pid ?? null,
      qemuRunning: Boolean(vmProcess && vmProcess.exitCode === null),
      qemuPid: vmProcess?.pid ?? null,
    };
  } else if (toolId === 'vibekits.proxy.start') {
    if (resolve(args.configPath) !== resolve(config) || resolve(args.dataDirectory) !== resolve(dataDirectory)) {
      throw new Error('proxy smoke allowlist rejected paths');
    }
    proxyProcess = start(mihomo, ['-d', dataDirectory, '-f', config], dirname(mihomo));
    await new Promise((resolveWait) => setTimeout(resolveWait, 800));
    if (proxyProcess.exitCode !== null) throw new Error(`Mihomo exited ${proxyProcess.exitCode}`);
    data = { started: true, pid: proxyProcess.pid };
  } else if (toolId === 'vibekits.proxy.stop') {
    await stop(proxyProcess); data = { stopped: true };
  } else if (toolId === 'vibekits.vm.start') {
    if (resolve(args.diskPath) !== resolve(disk)) throw new Error('VM smoke allowlist rejected disk');
    const memory = Math.max(256, Math.min(32768, Number(args.memoryMiB) || 256));
    const cpus = Math.max(1, Math.min(16, Number(args.cpuCount) || 1));
    vmProcess = start(qemu, [
      '-name', 'Vibekits-Harness-Smoke', '-m', `${memory}`, '-smp', `${cpus}`,
      '-boot', 'menu=on', '-nic', 'user,model=e1000', '-usb', '-device', 'usb-tablet',
      '-hda', disk, '-display', 'none',
    ], dirname(qemu));
    await new Promise((resolveWait) => setTimeout(resolveWait, 800));
    if (vmProcess.exitCode !== null) throw new Error(`QEMU exited ${vmProcess.exitCode}`);
    data = { started: true, pid: vmProcess.pid };
  } else if (toolId === 'vibekits.vm.stop') {
    await stop(vmProcess); data = { stopped: true };
  } else {
    throw new Error(`unknown tool ${toolId}`);
  }
  activity.push({ toolId, arguments: args, result: data, startedAt: startedAt.toISOString(), elapsedMs: Date.now() - startedAt.getTime() });
  await writeFile(evidenceFile, JSON.stringify({ version: 1, entries: activity }, null, 2), 'utf8');
  return data;
}

const server = createServer(async (request, response) => {
  response.setHeader('Content-Type', 'application/json');
  if (request.headers.authorization !== `Bearer ${token}`) {
    response.statusCode = 401; response.end(JSON.stringify({ error: 'unauthorized' })); return;
  }
  try {
    if (request.method === 'GET' && request.url === '/catalog') {
      response.end(JSON.stringify({ protocol: 'vibekits.tools.v1', tools })); return;
    }
    if (request.method !== 'POST' || request.url !== '/invoke') {
      response.statusCode = 404; response.end(JSON.stringify({ error: 'not_found' })); return;
    }
    let body = '';
    for await (const chunk of request) body += chunk;
    const payload = JSON.parse(body);
    const data = await invoke(payload.toolId, payload.arguments || {});
    response.end(JSON.stringify({ ok: true, data }));
  } catch (error) {
    response.end(JSON.stringify({ ok: false, error: `${error}` }));
  }
});

await new Promise((resolveListen) => server.listen(0, '127.0.0.1', resolveListen));
const endpoint = `http://127.0.0.1:${server.address().port}`;

async function runAgent(prompt, marker, timeoutMs = 240000) {
  const child = spawn(node, [cli, '--profile', 'headless', prompt], {
    cwd: root, windowsHide: true, shell: false,
    env: {
      ...process.env,
      DEEPSEEK_BASE_URL: 'https://api.deepseek.com',
      DEEPSEEK_MODEL: 'deepseek-v4-pro',
      DSH_HOME: harnessHome,
      DSH_TELEMETRY_MODE: 'DISABLED',
      DSH_PERMISSION_MODE: 'workspace-write',
      DSH_TELEMETRY_DISABLED: '1',
      VIBEKITS_NODE_EXECUTABLE: node,
      VIBEKITS_MCP_SERVER: mcp,
      VIBEKITS_TOOL_BRIDGE_URL: endpoint,
      VIBEKITS_TOOL_BRIDGE_TOKEN: token,
    },
  });
  let output = '';
  child.stdout.on('data', (value) => { output += value; process.stdout.write(value); });
  child.stderr.on('data', (value) => { output += value; process.stderr.write(value); });
  const timer = setTimeout(() => child.kill(), timeoutMs);
  const code = await new Promise((resolveExit, reject) => { child.on('error', reject); child.on('exit', resolveExit); });
  clearTimeout(timer);
  if (code !== 0 || !output.includes(marker)) throw new Error(`${marker}_FAILED exit=${code}`);
  return output;
}

try {
  if (!webOnly) {
    const toolPrompt = `Strict acceptance: use only Vibekits MCP tools, no shell. Call runtime.inspect. Then call proxy.start with configPath="${config}" and dataDirectory="${dataDirectory}". Call runtime.status and verify Mihomo has a PID. Call vm.start with diskPath="${disk}", memoryMiB=256, cpuCount=1. Call runtime.status and verify QEMU has a PID. Then call vm.stop and proxy.stop. After every call succeeds output exactly VIBEKITS_HARNESS_NETWORK_VM_OK.`;
    await runAgent(toolPrompt, 'VIBEKITS_HARNESS_NETWORK_VM_OK');
    const required = new Set(tools.map((item) => item.id));
    if (![...required].every((id) => activity.some((item) => item.toolId === id))) throw new Error('HARNESS_MISSING_TOOL_CALLS');
    console.log('HARNESS_NETWORK_VM_SMOKE_PASSED');
  }

  const webPrompt = 'You must use the built-in web search tool, not memory. Search the official QEMU website for the current stable release page. Include a qemu.org source URL, then output exactly VIBEKITS_HARNESS_WEB_SEARCH_OK.';
  const webOutput = await runAgent(webPrompt, 'VIBEKITS_HARNESS_WEB_SEARCH_OK');
  if (!webOutput.toLowerCase().includes('qemu.org')) throw new Error('HARNESS_WEB_SEARCH_NO_OFFICIAL_SOURCE');
  console.log('HARNESS_WEB_SEARCH_SMOKE_PASSED');
} finally {
  await stop(vmProcess);
  await stop(proxyProcess);
  await new Promise((resolveClose) => server.close(resolveClose));
}
