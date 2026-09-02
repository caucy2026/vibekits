import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const [connectionFile, expectedProcessId] = process.argv.slice(2);
if (!connectionFile || !/^\d+$/.test(expectedProcessId ?? '')) {
  throw new Error('usage: verify_harness_local_bridge.mjs <connection-file> <process-id>');
}

const connection = JSON.parse(await readFile(connectionFile, 'utf8'));
assert.equal(connection.version, 1);
assert.equal(connection.processId, Number(expectedProcessId));
assert.equal(typeof connection.token, 'string');
assert.ok(connection.token.length >= 32, 'bridge token is too short');
const endpoint = new URL(connection.endpoint);
assert.equal(endpoint.protocol, 'http:');
assert.equal(endpoint.hostname, '127.0.0.1');

async function request(path, init = {}) {
  const response = await fetch(new URL(path, endpoint), {
    ...init,
    headers: {
      Authorization: `Bearer ${connection.token}`,
      ...(init.headers ?? {}),
    },
    signal: AbortSignal.timeout(10_000),
  });
  assert.equal(response.status, 200, `${path} returned HTTP ${response.status}`);
  return response.json();
}

const catalog = await request('/catalog');
assert.equal(catalog.protocol, 'vibekits.tools.v1');
assert.ok(
  Array.isArray(catalog.tools) &&
    catalog.tools.some((tool) => tool.id === 'vibekits.system.capability_check'),
  'capability_check is missing from the local catalog',
);

const result = await request('/invoke', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    toolId: 'vibekits.system.capability_check',
    arguments: {},
  }),
});
assert.equal(result.ok, true, 'local capability_check did not succeed');
assert.notEqual(result.cancelled, true, 'local capability_check was cancelled');
console.log(`Verified local Harness tool bridge: App PID=${connection.processId}`);
