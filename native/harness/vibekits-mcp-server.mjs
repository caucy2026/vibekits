import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';

const endpoint = process.env.VIBEKITS_TOOL_BRIDGE_URL;
const token = process.env.VIBEKITS_TOOL_BRIDGE_TOKEN;
if (!endpoint || !token) throw new Error('Vibekits tool bridge is not configured');

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
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => {
  const catalog = await request('/catalog');
  idByName = new Map();
  const tools = catalog.tools.map((tool) => {
    const name = tool.id.replace(/^vibekits\./, '').replaceAll('.', '__');
    idByName.set(name, tool.id);
    return { name, description: tool.description, inputSchema: tool.inputSchema };
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
