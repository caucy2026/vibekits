import { readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const runtime = resolve(process.argv[2] ?? 'native/harness/windows/runtime');

async function replaceOnce(relativePath, before, after) {
  const filename = join(runtime, relativePath);
  const source = await readFile(filename, 'utf8');
  const first = source.indexOf(before);
  if (first < 0) {
    if (source.includes(after)) return;
    throw new Error(`Harness patch target not found: ${relativePath}`);
  }
  if (source.indexOf(before, first + before.length) >= 0) {
    throw new Error(`Harness patch target is ambiguous: ${relativePath}`);
  }
  await writeFile(
    filename,
    `${source.slice(0, first)}${after}${source.slice(first + before.length)}`,
    'utf8',
  );
}

async function replaceOneOf(relativePath, candidates, after) {
  const filename = join(runtime, relativePath);
  const source = await readFile(filename, 'utf8');
  if (source.includes(after)) return;
  const matches = candidates.filter((candidate) => source.includes(candidate));
  if (matches.length !== 1) {
    throw new Error(`Harness patch target count ${matches.length}: ${relativePath}`);
  }
  const before = matches[0];
  await writeFile(filename, source.replace(before, after), 'utf8');
}

await replaceOneOf(
  'node_modules/@deepseek-ai/dsh-client-ui-model-selection/lib/client.js',
  [`\t\t\tconst onBlur = (event) => {
\t\t\t\tif (event.relatedTarget instanceof Node && rootRef.current?.contains(event.relatedTarget)) return;
\t\t\t\tclose();
\t\t\t};`,
  `\t\t\tconst onBlur = () => {
\t\t\t\tqueueMicrotask(() => {
\t\t\t\t\tconst focused = document.activeElement;
\t\t\t\t\tif (focused instanceof Node && rootRef.current?.contains(focused)) return;
\t\t\t\t\tclose();
\t\t\t\t});
\t\t\t};`],
  `\t\t\tconst onBlur = (event) => {
\t\t\t\tif (event.relatedTarget === null) return;
\t\t\t\tif (event.relatedTarget instanceof Node && rootRef.current?.contains(event.relatedTarget)) return;
\t\t\t\tclose();
\t\t\t};`,
);

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-model-selection/lib/client.js',
  `\t\t\t"menu.effort": "推理等级",
\t\t\t"effort.providerDefault": "Default",`,
  `\t\t\t"menu.effort": "推理等级",
\t\t\t"effort.providerDefault": "默认",`,
);

await replaceOneOf(
  'node_modules/@deepseek-ai/dsh-client-ui-permission-presets/lib/client.js',
  [`\t\tfunction displayPermissionPreset(value, name) {
\t\t\treturn value === "danger-full-access" ? "Full access" : displayPresetName(name);
\t\t}`,
  `\t\tfunction displayPermissionPreset(value, name) {
\t\t\tconst language = (document.documentElement.lang || navigator.language || "").toLowerCase();
\t\t\tif (language.startsWith("zh")) return {
\t\t\t\t"read-only": "只读",
\t\t\t\t"workspace-write": "工作区读写",
\t\t\t\t"danger-full-access": "完全访问",
\t\t\t\tcustom: "自定义"
\t\t\t}[value] ?? displayPresetName(name);
\t\t\treturn value === "danger-full-access" ? "Full access" : displayPresetName(name);
\t\t}`],
  `\t\tfunction displayPermissionPreset(value, name) {
\t\t\treturn {
\t\t\t\t"read-only": "只读",
\t\t\t\t"workspace-write": "工作区读写",
\t\t\t\t"danger-full-access": "完全访问",
\t\t\t\tcustom: "自定义"
\t\t\t}[value] ?? displayPresetName(name);
\t\t}`,
);

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js',
  `\t\tfunction optionLabel(option) {
\t\t\treturn option.value === FULL_ACCESS ? "Full access" : displayName(option.name);
\t\t}`,
  `\t\tfunction optionLabel(option) {
\t\t\treturn {
\t\t\t\t"read-only": "只读",
\t\t\t\t"workspace-write": "工作区读写",
\t\t\t\t"danger-full-access": "完全访问",
\t\t\t\tcustom: "自定义"
\t\t\t}[option.value] ?? displayName(option.name);
\t\t}`,
);

const permissionFile =
  'node_modules/@deepseek-ai/dsh-client-ui-permission-presets/lib/client.js';
for (const [before, after] of [
  ['确认启用 Full access？', '确认启用完全访问？'],
  ['启用 Full access 后', '启用完全访问后'],
  ['启用 Full access', '启用完全访问'],
]) {
  const filename = join(runtime, permissionFile);
  const source = await readFile(filename, 'utf8');
  if (!source.includes(before)) {
    if (source.includes(after)) continue;
    throw new Error(`Harness permission locale target not found: ${before}`);
  }
  await writeFile(filename, source.split(before).join(after), 'utf8');
}

console.log(`Patched Harness Web runtime: ${runtime}`);
