import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { zstdCompress, zstdDecompress } from 'node:zlib';
import { promisify } from 'node:util';

const compress = promisify(zstdCompress);
const decompress = promisify(zstdDecompress);

const root = await mkdtemp(join(tmpdir(), 'vibekits-rebind-'));
const sessionId = 'session-11111111-1111-4111-8111-111111111111';
const sourceId = '22222222-2222-4222-8222-222222222222';
const targetId = '33333333-3333-4333-8333-333333333333';
const sourcePath = '/tmp/vibekits-source';
const targetPath = '/tmp/vibekits-target';
const sourceKey = '--tmp-vibekits-source--';
const targetKey = '--tmp-vibekits-target--';
const sourceSession = join(root, 'sessions', sourceKey, sessionId);
await mkdir(sourceSession, { recursive: true });
await mkdir(join(root, 'storages'), { recursive: true });
const header = {
  type: 'session', version: 1, id: sessionId, createdAt: 1,
  cwd: sourcePath, delegationDepth: 0,
};
await writeFile(
  join(sourceSession, 'session.jsonl.zstd'),
  await compress(Buffer.from(`${JSON.stringify(header)}\n{\"type\":\"event\"}\n`)),
);
await writeFile(join(root, 'storages', 'workspace.json'), JSON.stringify({
  tables: { workspaces: {
    [sourceId]: { path: sourcePath, title: 'source', sessionIds: [sessionId] },
    [targetId]: { path: targetPath, title: 'target', sessionIds: [] },
  } },
}));
await writeFile(join(root, 'storages', 'session_projcache.json'), JSON.stringify({
  tables: { sessions: { [sessionId]: { identity: { cwd: sourcePath }, rows: {} } } },
}));

try {
  const child = spawn(process.execPath, [
    fileURLToPath(new URL('../native/harness/vibekits-session-rebind.mjs', import.meta.url)),
    root, sessionId, sourceId, targetId,
  ], { stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  const exitCode = await new Promise((resolve) => child.on('close', resolve));
  assert.equal(exitCode, 0, stderr);
  assert.equal(JSON.parse(stdout).ok, true);

  const workspaces = JSON.parse(await readFile(join(root, 'storages', 'workspace.json'))).tables.workspaces;
  assert.deepEqual(workspaces[sourceId].sessionIds, []);
  assert.deepEqual(workspaces[targetId].sessionIds, [sessionId]);
  const projection = JSON.parse(
    await readFile(join(root, 'storages', 'session_projcache.json')),
  );
  assert.equal(projection.tables.sessions[sessionId].identity.cwd, targetPath);
  const moved = await decompress(
    await readFile(join(root, 'sessions', targetKey, sessionId, 'session.jsonl.zstd')),
  );
  assert.equal(JSON.parse(moved.subarray(0, moved.indexOf(10))).cwd, targetPath);
  await assert.rejects(readFile(join(sourceSession, 'session.jsonl.zstd')));
  console.log('Harness cross-project session rebind: PASS');
} finally {
  await rm(root, { recursive: true, force: true });
}
