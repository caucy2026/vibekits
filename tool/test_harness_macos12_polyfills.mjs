import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const indexPath = process.argv[2];
if (!indexPath) throw new Error('usage: test_harness_macos12_polyfills.mjs <dist-macos12/index.html|--source>');

let html;
if (indexPath === '--source') {
  const transpiler = await readFile(
    fileURLToPath(new URL('./transpile_harness_web_macos.mjs', import.meta.url)),
    'utf8',
  );
  const template = transpiler.match(/const promiseWithResolversPolyfill = `([\s\S]*?)`;/);
  assert.ok(template, 'macOS 12 polyfill template must exist');
  html = `<html>${template[1]}<script type="module" src="/boot.js"></script></html>`;
} else {
  html = await readFile(indexPath, 'utf8');
}
const match = html.match(/<script data-vibekits-macos12-polyfill>([\s\S]*?)<\/script>/);
assert.ok(match, 'macOS 12 compatibility polyfill must be embedded');
assert.ok(
  html.indexOf('data-vibekits-macos12-polyfill') < html.indexOf('<script type="module"'),
  'polyfill must run before Harness modules',
);

const context = vm.createContext({});
vm.runInContext('globalThis.Iterator = undefined; Promise.withResolvers = undefined;', context);

// Negative control: the PDF preview's startup expression must fail in a
// Safari 15-like realm before the compatibility script is installed.
assert.throws(
  () => vm.runInContext('typeof Iterator.prototype.join', context),
  /Cannot read properties of undefined/,
);

vm.runInContext(match[1], context);
assert.equal(vm.runInContext('typeof Iterator.prototype.join', context), 'undefined');
vm.runInContext(
  'if (typeof Iterator.prototype.join !== "function") Iterator.prototype.join = function(separator) { return [...this].join(separator); };',
  context,
);
assert.equal(vm.runInContext('[1, 2, 3].values().join("-")', context), '1-2-3');
assert.equal(vm.runInContext('new Map([["a", 1], ["b", 2]]).keys().join(",")', context), 'a,b');
assert.equal(vm.runInContext('typeof Promise.withResolvers', context), 'function');
assert.equal(vm.runInContext('Promise.withResolvers().promise instanceof Promise', context), true);

console.log('macOS 12 Harness Iterator and Promise polyfills passed');
