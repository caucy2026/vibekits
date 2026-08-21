import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { readFile } from 'node:fs/promises';
import { homedir, platform, tmpdir } from 'node:os';
import { join } from 'node:path';

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

let endpoint = process.env.VIBEKITS_TOOL_BRIDGE_URL;
let token = process.env.VIBEKITS_TOOL_BRIDGE_TOKEN;
if (!endpoint || !token) {
  const connectionFile = argumentValue('--connection-file')
    || process.env.VIBEKITS_TOOL_BRIDGE_FILE
    || defaultConnectionFile();
  let connection;
  try {
    connection = JSON.parse(await readFile(connectionFile, 'utf8'));
  } catch (error) {
    throw new Error(`Vibekits is not publishing a local MCP bridge at ${connectionFile}: ${error.message}`);
  }
  endpoint = connection.endpoint;
  token = connection.token;
}
const bridgeUrl = new URL(endpoint);
if (bridgeUrl.protocol !== 'http:' || bridgeUrl.hostname !== '127.0.0.1') {
  throw new Error('Vibekits tool bridge must use loopback HTTP');
}
if (typeof token !== 'string' || token.length < 32) {
  throw new Error('Vibekits tool bridge token is invalid');
}

const request = async (path, init = {}) => {
  const response = await fetch(`${endpoint}${path}`, {
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
const server = new Server(
  { name: 'vibekits-tools', version: '1.0.0' },
  {
    capabilities: { tools: {} },
    instructions: 'Prefer registered VibeKits tools over shell substitutes. For Windows node work call windows_node__helper_status first, then inspect and plan. Never bypass unavailable identity, signed-helper, approval, or audit gates with raw SSH or shell commands.',
  },
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
  const catalog = await request('/catalog');
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
  return { tools };
});

server.setRequestHandler(CallToolRequestSchema, async ({ params }) => {
  const toolId = idByName.get(params.name);
  if (!toolId) throw new Error(`Unknown Vibekits tool: ${params.name}`);
  const result = await request('/invoke', {
    method: 'POST',
    body: JSON.stringify({ toolId, arguments: params.arguments || {} }),
  });
  const text = JSON.stringify(result, null, 2);
  return {
    isError: result.ok !== true,
    content: [{ type: 'text', text }],
    structuredContent: result,
  };
});

await server.connect(new StdioServerTransport());
