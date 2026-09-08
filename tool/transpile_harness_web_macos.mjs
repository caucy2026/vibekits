import { readdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const dist = resolve(process.argv[2] ?? '');
const esbuildModule = resolve(process.argv[3] ?? '');
if (!process.argv[2] || !process.argv[3]) {
  throw new Error(
    'usage: transpile_harness_web_macos.mjs <dsh-web dist> <esbuild module>',
  );
}
const { transform } = await import(pathToFileURL(esbuildModule));

const assets = resolve(dist, 'assets');
const files = (await readdir(assets))
  .filter((name) => name.endsWith('.js'))
  .sort();
if (files.length === 0) {
  throw new Error(`Harness Web JavaScript assets not found: ${assets}`);
}

for (const name of files) {
  const filename = resolve(assets, name);
  const source = await readFile(filename, 'utf8');
  const result = await transform(source, {
    target: 'safari15',
    format: 'esm',
    minify: true,
    legalComments: 'inline',
  });
  await writeFile(filename, result.code, 'utf8');
}

console.log(`Transpiled ${files.length} Harness Web assets for Safari 15+`);
