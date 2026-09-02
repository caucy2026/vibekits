import { cp, mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { zstdCompress, zstdDecompress } from 'node:zlib';
import { promisify } from 'node:util';

const compress = promisify(zstdCompress);
const decompress = promisify(zstdDecompress);

const [home, sessionId, sourceWorkspaceId, targetWorkspaceId] = process.argv.slice(2);
if (!home || !/^session-[0-9a-f-]{36}$/.test(sessionId ?? '') ||
    !/^[0-9a-f-]{36}$/.test(sourceWorkspaceId ?? '') ||
    !/^[0-9a-f-]{36}$/.test(targetWorkspaceId ?? '')) {
  throw new Error('invalid session rebind arguments');
}

const storageDir = join(home, 'storages');
const workspaceFile = join(storageDir, 'workspace.json');
const projectionFile = join(storageDir, 'session_projcache.json');
const workspaceRoot = JSON.parse(await readFile(workspaceFile, 'utf8'));
const projectionRoot = JSON.parse(await readFile(projectionFile, 'utf8'));
const workspaces = workspaceRoot?.tables?.workspaces;
const projections = projectionRoot?.tables?.sessions;
const source = workspaces?.[sourceWorkspaceId];
const target = workspaces?.[targetWorkspaceId];
const projection = projections?.[sessionId];
if (!source || !target || !projection) throw new Error('session or workspace not found');
if (!Array.isArray(source.sessionIds) || !source.sessionIds.includes(sessionId)) {
  throw new Error('source workspace does not own session');
}
if (!Array.isArray(target.sessionIds)) target.sessionIds = [];
if (target.sessionIds.includes(sessionId)) throw new Error('target workspace already owns session');
if (projection.identity?.cwd !== source.path) throw new Error('session cwd does not match source workspace');

function projectKey(cwd) {
  let readable = '';
  let separatorRun = false;
  for (let i = 0; i < cwd.length; i++) {
    const code = cwd.charCodeAt(i);
    const ch = String.fromCharCode(code);
    if (ch === '/' || ch === '\\' || ch === ':') {
      if (!separatorRun) readable += '-';
      separatorRun = true;
    } else if (ch !== '~' && /^[A-Za-z0-9._-]$/.test(ch)) {
      readable += ch;
      separatorRun = false;
    } else {
      readable += `~${code.toString(16).toUpperCase().padStart(4, '0')}`;
      separatorRun = false;
    }
  }
  return `--${(readable.replace(/^-+/, '') || 'root').slice(0, 251)}--`;
}

const sessionsRoot = join(home, 'sessions');
const sourceDir = join(sessionsRoot, projectKey(source.path), sessionId);
const targetParent = join(sessionsRoot, projectKey(target.path));
const targetDir = join(targetParent, sessionId);
const token = `${process.pid}-${Date.now()}`;
const stagingDir = `${targetDir}.vibekits-${token}.tmp`;
const backupDir = `${sourceDir}.vibekits-${token}.bak`;
const workspaceNext = `${workspaceFile}.vibekits-${token}.tmp`;
const workspaceBackup = `${workspaceFile}.vibekits-${token}.bak`;
const projectionNext = `${projectionFile}.vibekits-${token}.tmp`;
const projectionBackup = `${projectionFile}.vibekits-${token}.bak`;

let sourceBackedUp = false;
let targetInstalled = false;
let workspaceSwapped = false;
let projectionSwapped = false;
try {
  await mkdir(targetParent, { recursive: true });
  await cp(sourceDir, stagingDir, { recursive: true, errorOnExist: true });
  const compressedLog = join(stagingDir, 'session.jsonl.zstd');
  const plain = await decompress(await readFile(compressedLog));
  const newline = plain.indexOf(10);
  if (newline < 0) throw new Error('session log has no header');
  const header = JSON.parse(plain.subarray(0, newline).toString('utf8'));
  if (header.type !== 'session' || header.id !== sessionId || header.cwd !== source.path) {
    throw new Error('session header does not match source workspace');
  }
  header.cwd = target.path;
  const nextPlain = Buffer.concat([
    Buffer.from(`${JSON.stringify(header)}\n`, 'utf8'),
    plain.subarray(newline + 1),
  ]);
  await writeFile(compressedLog, await compress(nextPlain), { mode: 0o600 });

  source.sessionIds = source.sessionIds.filter((id) => id !== sessionId);
  target.sessionIds = [sessionId, ...target.sessionIds];
  source.updatedAt = new Date().toISOString();
  target.updatedAt = source.updatedAt;
  projection.identity.cwd = target.path;
  await writeFile(workspaceNext, JSON.stringify(workspaceRoot, null, 2), { mode: 0o600 });
  await writeFile(projectionNext, JSON.stringify(projectionRoot, null, 2), { mode: 0o600 });

  await rename(sourceDir, backupDir);
  sourceBackedUp = true;
  await rename(stagingDir, targetDir);
  targetInstalled = true;
  await rename(workspaceFile, workspaceBackup);
  await rename(workspaceNext, workspaceFile);
  workspaceSwapped = true;
  await rename(projectionFile, projectionBackup);
  await rename(projectionNext, projectionFile);
  projectionSwapped = true;
  await rm(backupDir, { recursive: true, force: true });
  await rm(workspaceBackup, { force: true });
  await rm(projectionBackup, { force: true });
  process.stdout.write(JSON.stringify({ ok: true, sessionId, workspaceId: targetWorkspaceId }));
} catch (error) {
  if (projectionSwapped) {
    await rm(projectionFile, { force: true });
    await rename(projectionBackup, projectionFile);
  }
  if (workspaceSwapped) {
    await rm(workspaceFile, { force: true });
    await rename(workspaceBackup, workspaceFile);
  }
  if (targetInstalled) {
    await rm(targetDir, { recursive: true, force: true });
  }
  if (sourceBackedUp) {
    await rename(backupDir, sourceDir);
  }
  throw error;
} finally {
  await rm(stagingDir, { recursive: true, force: true });
  await rm(workspaceNext, { force: true });
  await rm(projectionNext, { force: true });
}
