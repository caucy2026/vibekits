import { readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const runtime = resolve(process.argv[2] ?? 'native/harness/macos/runtime');

async function replaceOnce(relativePath, before, after, marker = after) {
  const filename = join(runtime, relativePath);
  const source = await readFile(filename, 'utf8');
  if (source.includes(marker)) return;
  const first = source.indexOf(before);
  if (first < 0 || source.indexOf(before, first + before.length) >= 0) {
    throw new Error(`Harness macOS compatibility target missing or ambiguous: ${relativePath}`);
  }
  await writeFile(
    filename,
    `${source.slice(0, first)}${after}${source.slice(first + before.length)}`,
    'utf8',
  );
}

// DSH 0.1.6 resolves its frontend through dsh-web-app. Keep the official
// location as the default and honor VibeKits' legacy-WebKit path only when the
// macOS host explicitly supplies it.
await replaceOnce(
  'node_modules/@deepseek-ai/dsh-web-app/lib/index.js',
  'return join(dirname(require.resolve("@deepseek-ai/dsh-web-frontend/package.json")), "dist", "index.html");',
  'return process.env.VIBEKITS_DSH_WEB_DIST_INDEX ?? join(dirname(require.resolve("@deepseek-ai/dsh-web-frontend/package.json")), "dist", "index.html");',
  'process.env.VIBEKITS_DSH_WEB_DIST_INDEX ??',
);

// Dynamic client modules are served by their resolved clientPath. Route those
// modules to the separately transpiled Safari 15 copies only for the same
// explicitly selected compatibility frontend.
await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-modules/lib/index.js',
  'clientPath: join(dirname(pkgPath), clientRel),',
  'clientPath: process.env.VIBEKITS_DSH_WEB_DIST_INDEX\n\t\t\t\t\t? join(dirname(pkgPath), clientRel).replace(/\\.js$/, ".macos12.js")\n\t\t\t\t\t: join(dirname(pkgPath), clientRel),',
  '.replace(/\\.js$/, ".macos12.js")',
);

// Older WKWebView versions can reject large combo requests before they reach
// Harness. Singleton batches preserve the official module graph and only
// change transport granularity on every platform build of this macOS runtime.
await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-modules/lib/index.js',
  'const MAX_COMBO_URL_BYTES = 3 * 1024;',
  'const MAX_COMBO_URL_BYTES = 1800;\nconst MAX_COMBO_ENTRIES = 1;',
  'const MAX_COMBO_ENTRIES = 1;',
);
await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-modules/lib/index.js',
  'if (projectedComboUrlBytes(candidate) <= MAX_COMBO_URL_BYTES) {',
  'if (candidate.length <= MAX_COMBO_ENTRIES && projectedComboUrlBytes(candidate) <= MAX_COMBO_URL_BYTES) {',
  'candidate.length <= MAX_COMBO_ENTRIES',
);
