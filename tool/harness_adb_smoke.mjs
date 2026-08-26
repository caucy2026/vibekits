import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const runtime = join(root, 'native', 'harness', 'windows', 'runtime');
const adb = join(root, 'build', 'windows', 'x64', 'runner', 'Release', 'tools', 'adb', 'adb.exe');
const node = join(runtime, 'node.exe');
const cli = join(runtime, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js');
const mcp = join(runtime, 'vibekits-mcp-server.mjs');
const harnessHome = join(process.env.LOCALAPPDATA, 'Vibekits', 'Harness');
const target = '192.168.3.63:5555';
const token = randomBytes(32).toString('base64url');
const activityFile = join(harnessHome, 'tool_activity.json');

if (!process.env.DEEPSEEK_API_KEY) throw new Error('HARNESS_ADB_NO_SAVED_KEY');
await mkdir(harnessHome, { recursive: true });

const run = (executable, args, timeoutMs = 15_000) => new Promise((resolveRun, reject) => {
  const child = spawn(executable, args, { windowsHide: true, shell: false });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (value) => { stdout += value; });
  child.stderr.on('data', (value) => { stderr += value; });
  const timer = setTimeout(() => {
    child.kill();
    reject(new Error(`command timeout: ${args.join(' ')}`));
  }, timeoutMs);
  child.on('error', reject);
  child.on('exit', (code) => {
    clearTimeout(timer);
    resolveRun({ code, stdout: stdout.trim(), stderr: stderr.trim() });
  });
});

const tools = [
  {
    id: 'vibekits.adb.list_devices',
    description: 'List Android devices using Vibekits bundled ADB.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
  },
  {
    id: 'vibekits.adb.command',
    description: 'Run an approved read-only getprop command on one Android device.',
    inputSchema: {
      type: 'object',
      properties: {
        serial: { type: 'string' },
        arguments: { type: 'array', items: { type: 'string' }, minItems: 3, maxItems: 3 },
      },
      required: ['serial', 'arguments'],
      additionalProperties: false,
    },
  },
];

const allowedProperties = new Set([
  'ro.product.model',
  'ro.build.version.release',
  'ro.product.manufacturer',
]);

const record = async ({ toolId, toolName, target: activityTarget, args, result, status, startedAt }) => {
  let entries = [];
  try {
    const current = JSON.parse(await readFile(activityFile, 'utf8'));
    if (Array.isArray(current.entries)) entries = current.entries;
  } catch (_) {}
  entries.unshift({
    id: `${startedAt.getTime() * 1000}-${randomBytes(4).readUInt32LE()}`,
    toolId,
    toolName,
    target: activityTarget,
    argumentsSummary: JSON.stringify(args),
    resultSummary: JSON.stringify({ ...result, evidenceSource: 'adb-process' }).slice(0, 4096),
    status,
    startedAt: startedAt.toISOString(),
    elapsedMs: Date.now() - startedAt.getTime(),
  });
  const temporary = `${activityFile}.tmp`;
  await writeFile(temporary, JSON.stringify({ version: 1, entries: entries.slice(0, 500) }), 'utf8');
  await rename(temporary, activityFile);
};

const server = createServer(async (request, response) => {
  response.setHeader('Content-Type', 'application/json');
  if (request.headers.authorization !== `Bearer ${token}`) {
    response.statusCode = 401;
    response.end(JSON.stringify({ error: 'unauthorized' }));
    return;
  }
  try {
    if (request.method === 'GET' && request.url === '/catalog') {
      response.end(JSON.stringify({ protocol: 'vibekits.tools.v1', tools }));
      return;
    }
    if (request.method !== 'POST' || request.url !== '/invoke') {
      response.statusCode = 404;
      response.end(JSON.stringify({ error: 'not_found' }));
      return;
    }
    let body = '';
    for await (const chunk of request) {
      body += chunk;
      if (body.length > 1024 * 1024) throw new Error('request too large');
    }
    const payload = JSON.parse(body);
    const startedAt = new Date();
    if (payload.toolId === 'vibekits.adb.list_devices') {
      const result = await run(adb, ['devices', '-l']);
      await record({
        toolId: payload.toolId,
        toolName: '列出 ADB 设备',
        target: '',
        args: payload.arguments || {},
        result,
        status: result.code === 0 ? 'succeeded' : 'failed',
        startedAt,
      });
      response.end(JSON.stringify({ ok: result.code === 0, data: result }));
      return;
    }
    const args = payload.arguments?.arguments;
    if (payload.toolId !== 'vibekits.adb.command' ||
        payload.arguments?.serial !== target ||
        !Array.isArray(args) || args.length !== 3 ||
        args[0] !== 'shell' || args[1] !== 'getprop' ||
        !allowedProperties.has(args[2])) {
      response.end(JSON.stringify({ ok: false, cancelled: true, error: 'smoke allowlist rejected request' }));
      return;
    }
    const result = await run(adb, ['-s', target, ...args]);
    await record({
      toolId: payload.toolId,
      toolName: '执行 ADB 命令',
      target,
      args: payload.arguments,
      result,
      status: result.code === 0 ? 'succeeded' : 'failed',
      startedAt,
    });
    response.end(JSON.stringify({ ok: result.code === 0, data: result }));
  } catch (error) {
    response.statusCode = 400;
    response.end(JSON.stringify({ error: `${error}` }));
  }
});

await new Promise((resolveListen) => server.listen(0, '127.0.0.1', resolveListen));
const endpoint = `http://127.0.0.1:${server.address().port}`;
const prompt = `You must use Vibekits ADB tools, never guess. List devices, then query ${target} for ro.product.model, ro.build.version.release, and ro.product.manufacturer. Finally output exactly one line: VIBEKITS_HARNESS_ADB_OK model=<value> android=<value> manufacturer=<value>`;
const child = spawn(node, [cli, '--profile', 'headless', prompt], {
  cwd: root,
  windowsHide: true,
  shell: false,
  env: {
    ...process.env,
    DEEPSEEK_BASE_URL: 'https://api.deepseek.com',
    DEEPSEEK_MODEL: 'deepseek-v4-flash',
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
const timeout = setTimeout(() => child.kill(), 120_000);
const code = await new Promise((resolveExit, reject) => {
  child.on('error', reject);
  child.on('exit', resolveExit);
});
clearTimeout(timeout);
await new Promise((resolveClose) => server.close(resolveClose));
if (code !== 0 ||
    !output.includes('VIBEKITS_HARNESS_ADB_OK') ||
    !output.toLowerCase().includes('huanglong') ||
    !output.includes('HL2.0')) {
  throw new Error(`HARNESS_ADB_SMOKE_FAILED exit=${code}`);
}
console.log('HARNESS_ADB_SMOKE_PASSED');
