import { readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const runtime = resolve(process.argv[2]);
const filename = join(runtime,
  'node_modules/@deepseek-ai/dsh-client-ui-model-selection/lib/client.js');
const source = await readFile(filename, 'utf8');
const oldBlur = `\t\t\tconst onBlur = (event) => {
\t\t\t\tif (event.relatedTarget instanceof Node && (rootRef.current?.contains(event.relatedTarget) === true || menuRef.current?.contains(event.relatedTarget) === true)) return;
\t\t\t\tclose();
\t\t\t};`;
const newBlur = `\t\t\tconst onBlur = (event) => {
\t\t\t\tif (event.relatedTarget === null) return;
\t\t\t\tif (event.relatedTarget instanceof Node && (rootRef.current?.contains(event.relatedTarget) === true || menuRef.current?.contains(event.relatedTarget) === true)) return;
\t\t\t\tclose();
\t\t\t};`;
if (source.includes(newBlur)) {
  console.log('Harness Windows model menu focus patch already present');
} else if (source.split(oldBlur).length === 2) {
  await writeFile(filename, source.replace(oldBlur, newBlur), 'utf8');
  console.log('Patched Harness Windows model menu focus');
} else {
  throw new Error('Harness model menu focus patch target changed');
}
