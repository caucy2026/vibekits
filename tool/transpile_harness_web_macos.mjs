import { readdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const dist = resolve(process.argv[2] ?? '');
const esbuildModule = resolve(process.argv[3] ?? '');
const modules = process.argv[4] ? resolve(process.argv[4]) : null;
if (!process.argv[2] || !process.argv[3]) {
  throw new Error(
    'usage: transpile_harness_web_macos.mjs <dsh-web dist> <esbuild module>',
  );
}
const { transform } = await import(pathToFileURL(esbuildModule));

function macos12ClientSource(filename, source) {
  if (filename.endsWith('/dsh-api-gateway/lib/client.js')) {
    const target = 'AbortSignal.any';
    if (!source.includes(target)) {
      throw new Error(`Harness AbortSignal.any target not found: ${filename}`);
    }
    return `${source.replaceAll(target, 'macos12AbortSignalAny')}
function macos12AbortSignalAny(signals) {
	const controller = new AbortController();
	const abort = (signal) => controller.abort(signal.reason);
	for (const signal of signals) {
		if (signal.aborted) {
			abort(signal);
			break;
		}
		signal.addEventListener("abort", () => abort(signal), { once: true });
	}
	return controller.signal;
}
`;
  }
  if (!filename.endsWith('/dsh-client-connection/lib/client.js')) return source;
  const target = 'const send = doFetch ?? ((input, init) => globalThis.fetch(input, init));';
  if (!source.includes(target)) {
    throw new Error(`Harness connection fetch target not found: ${filename}`);
  }
  return source.replace(target, `const send = doFetch ?? ((input, init = {}) => new Promise((resolve, reject) => {
			const request = new XMLHttpRequest();
			request.open(init.method ?? "GET", String(input), true);
			for (const [name, value] of Object.entries(init.headers ?? {})) request.setRequestHeader(name, String(value));
			request.onload = () => resolve({
				ok: request.status >= 200 && request.status < 300,
				status: request.status,
				json: () => Promise.resolve(JSON.parse(request.responseText))
			});
			request.onerror = () => reject(new Error("Harness RPC network request failed"));
			request.onabort = () => reject(new Error("Harness RPC network request aborted"));
			if (init.signal !== void 0) {
				if (init.signal.aborted) return request.abort();
				init.signal.addEventListener("abort", () => request.abort(), { once: true });
			}
			request.send(init.body ?? null);
		}));`);
}

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

const clientBundles = [];
async function collectClientBundles(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      await collectClientBundles(path);
    } else if (entry.name === 'client.js' && dirname(path).endsWith('/lib')) {
      clientBundles.push(path);
    }
  }
}

if (modules !== null) {
  await collectClientBundles(modules);
  for (const filename of clientBundles.sort()) {
    const source = macos12ClientSource(
      filename,
      await readFile(filename, 'utf8'),
    );
    const result = await transform(source, {
      target: 'safari15',
      format: 'iife',
      minify: true,
      legalComments: 'inline',
    });
    await writeFile(filename.replace(/\.js$/, '.macos12.js'), result.code, 'utf8');
  }
}

console.log(
  `Transpiled ${files.length} Harness Web assets and ${clientBundles.length} client bundles for Safari 15+`,
);
