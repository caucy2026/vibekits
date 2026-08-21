import { readFile } from 'node:fs/promises';
import { homedir, platform, tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';

const argumentValue = (name) => {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
};

const defaultConnectionFile = () => {
  if (platform() === 'win32') {
    return join(process.env.LOCALAPPDATA || tmpdir(), 'Vibekits', 'Mcp', 'tool-bridge.json');
  }
  if (platform() === 'darwin') {
    return join(homedir(), 'Library', 'Application Support', 'Vibekits', 'Mcp', 'tool-bridge.json');
  }
  return join(process.env.XDG_RUNTIME_DIR || join(homedir(), '.local', 'share'), 'Vibekits', 'Mcp', 'tool-bridge.json');
};

const connectionFile = argumentValue('--connection-file')
  || process.env.VIBEKITS_TOOL_BRIDGE_FILE
  || defaultConnectionFile();

const connection = JSON.parse(await readFile(connectionFile, 'utf8'));
const endpoint = new URL(connection.endpoint);
const token = connection.token;
if (endpoint.protocol !== 'http:' || endpoint.hostname !== '127.0.0.1') {
  throw new Error('Vibekits tool bridge must use loopback HTTP');
}
if (typeof token !== 'string' || token.length < 32) {
  throw new Error('Vibekits tool bridge token is invalid');
}

const bridgeRequest = async (path, init = {}) => {
  const response = await fetch(new URL(path, endpoint), {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
  if (!response.ok) throw new Error(`Vibekits bridge HTTP ${response.status}`);
  return response.json();
};

let idByName = new Map();

const result = (id, value) => ({ jsonrpc: '2.0', id, result: value });
const failure = (id, error) => ({
  jsonrpc: '2.0',
  id,
  error: { code: -32603, message: error instanceof Error ? error.message : String(error) },
});

const handle = async (message) => {
  if (message.method === 'initialize') {
    return result(message.id, {
      protocolVersion: message.params?.protocolVersion || '2025-06-18',
      capabilities: { tools: {} },
      serverInfo: { name: 'vibekits-tools', version: '1.1.0' },
      instructions: 'Prefer registered VibeKits tools over shell substitutes. For Windows node work call windows_node__helper_status first, then inspect and plan. Never bypass unavailable identity, signed-helper, approval, or audit gates with raw SSH or shell commands.',
    });
  }
  if (message.method === 'ping') return result(message.id, {});
  if (message.method === 'tools/list') {
    const catalog = await bridgeRequest('/catalog');
    idByName = new Map();
    const tools = catalog.tools.map((tool) => {
      const name = tool.id.replace(/^vibekits\./, '').replaceAll('.', '__');
      idByName.set(name, tool.id);
      return {
        name,
        description: tool.description,
        inputSchema: tool.inputSchema,
        annotations: {
          readOnlyHint: tool.risk === 'readOnly',
          destructiveHint: tool.risk === 'destructive',
          idempotentHint: tool.risk === 'readOnly',
          openWorldHint: false,
        },
      };
    });
    return result(message.id, { tools });
  }
  if (message.method === 'tools/call') {
    const toolId = idByName.get(message.params?.name);
    if (!toolId) throw new Error(`Unknown Vibekits tool: ${message.params?.name}`);
    const value = await bridgeRequest('/invoke', {
      method: 'POST',
      body: JSON.stringify({
        toolId,
        arguments: message.params?.arguments || {},
      }),
    });
    return result(message.id, {
      isError: value.ok !== true,
      content: [{ type: 'text', text: JSON.stringify(value, null, 2) }],
      structuredContent: value,
    });
  }
  if (message.id === undefined) return undefined;
  return {
    jsonrpc: '2.0',
    id: message.id,
    error: { code: -32601, message: `Method not found: ${message.method}` },
  };
};

const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of lines) {
  if (!line.trim()) continue;
  let message;
  try {
    message = JSON.parse(line);
    const response = await handle(message);
    if (response !== undefined) process.stdout.write(`${JSON.stringify(response)}\n`);
  } catch (error) {
    if (message?.id !== undefined) {
      process.stdout.write(`${JSON.stringify(failure(message.id, error))}\n`);
    }
  }
}
