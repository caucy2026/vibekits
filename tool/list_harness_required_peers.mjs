import { access, readFile, readdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const root = resolve(process.argv[2] ?? 'node_modules');

async function packageDirectories() {
  const result = [];
  for (const entry of await readdir(root, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name === '.bin') continue;
    if (!entry.name.startsWith('@')) {
      result.push(join(root, entry.name));
      continue;
    }
    for (const scoped of await readdir(join(root, entry.name), {
      withFileTypes: true,
    })) {
      if (scoped.isDirectory()) result.push(join(root, entry.name, scoped.name));
    }
  }
  return result;
}

async function exists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

const missing = new Map();
for (const directory of await packageDirectories()) {
  const manifestPath = join(directory, 'package.json');
  if (!(await exists(manifestPath))) continue;
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  for (const [name, range] of Object.entries(manifest.peerDependencies ?? {})) {
    if (manifest.peerDependenciesMeta?.[name]?.optional === true) continue;
    if (await exists(join(root, ...name.split('/'), 'package.json'))) continue;
    const ranges = missing.get(name) ?? new Set();
    ranges.add(range);
    missing.set(name, ranges);
  }
}

const specs = [...missing.entries()]
  .sort(([left], [right]) => left.localeCompare(right))
  .map(([name, ranges]) => `${name}@${[...ranges][0]}`);
if (process.argv.includes('--null')) {
  process.stdout.write(specs.join('\0'));
} else {
  process.stdout.write(JSON.stringify(specs));
}
