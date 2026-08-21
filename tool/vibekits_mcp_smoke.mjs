import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const toolDirectory = dirname(fileURLToPath(import.meta.url));
const launcher = join(toolDirectory, 'start_vibekits_mcp.ps1');
const child = spawn('powershell.exe', [
  '-NoLogo',
  '-NoProfile',
  '-NonInteractive',
  '-ExecutionPolicy',
  'Bypass',
  '-File',
  launcher,
], { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });

const pending = new Map();
const lines = createInterface({ input: child.stdout, crlfDelay: Infinity });
lines.on('line', (line) => {
  if (!line.trim()) return;
  const message = JSON.parse(line);
  pending.get(message.id)?.(message);
  pending.delete(message.id);
});

let requestId = 0;
const rpc = (method, params = {}, timeoutMs = 15_000) => new Promise((resolve, reject) => {
  const id = ++requestId;
  const timeout = setTimeout(() => {
    pending.delete(id);
    reject(new Error(`MCP timeout: ${method}`));
  }, timeoutMs);
  pending.set(id, (message) => {
    clearTimeout(timeout);
    if (message.error) reject(new Error(message.error.message));
    else resolve(message.result);
  });
  child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
});

try {
  await rpc('initialize', {
    protocolVersion: '2025-06-18',
    capabilities: {},
    clientInfo: { name: 'vibekits-codex-smoke', version: '1' },
  });
  child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' })}\n`);
  const listed = await rpc('tools/list');
  const names = listed.tools.map((tool) => tool.name);
  if (!names.includes('windows_node__helper_status')) {
    throw new Error('windows_node__helper_status is missing from tools/list');
  }
  if (!names.includes('windows_node__inspect')) {
    throw new Error('windows_node__inspect is missing from tools/list');
  }
  const called = await rpc('tools/call', {
    name: 'windows_node__helper_status',
    arguments: {},
  }, 30_000);
  if (called.isError || called.structuredContent?.ok !== true) {
    throw new Error(`helper_status failed: ${JSON.stringify(called)}`);
  }
  const inspected = await rpc('tools/call', {
    name: 'windows_node__inspect',
    arguments: { rootPath: 'D:\\KEMI-Test' },
  }, 60_000);
  if (inspected.isError || inspected.structuredContent?.ok !== true) {
    throw new Error(`inspect failed: ${JSON.stringify(inspected)}`);
  }
  process.stdout.write(JSON.stringify({
    ok: true,
    toolCount: names.length,
    helperAvailable: called.structuredContent.data?.available,
    protocolVersion: called.structuredContent.data?.protocolVersion,
    inspectionId: inspected.structuredContent.data?.inspectionId,
  }));
} finally {
  child.stdin.end();
  const exited = await Promise.race([
    new Promise((resolve) => child.once('exit', () => resolve(true))),
    new Promise((resolve) => setTimeout(() => resolve(false), 2_000)),
  ]);
  if (!exited) child.kill();
}
