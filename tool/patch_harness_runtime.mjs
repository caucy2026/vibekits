import { readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const runtime = resolve(process.argv[2] ?? 'native/harness/windows/runtime');

async function replaceOnce(relativePath, before, after, marker = after) {
  const filename = join(runtime, relativePath);
  const source = await readFile(filename, 'utf8');
  // Many replacements deliberately keep the original snippet inside the
  // patched result (for example an existing menu action followed by a new
  // action). Check the complete result first, otherwise every build injects
  // the same patch again.
  if (source.includes(marker)) return;
  const first = source.indexOf(before);
  if (first < 0) {
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

async function replaceRegexOnce(relativePath, pattern, after, marker = after) {
  const filename = join(runtime, relativePath);
  const source = await readFile(filename, 'utf8');
  if (source.includes(marker)) return;
  const matches = [...source.matchAll(pattern)];
  if (matches.length !== 1) {
    throw new Error(`Harness regex patch target count ${matches.length}: ${relativePath}`);
  }
  await writeFile(filename, source.replace(pattern, after), 'utf8');
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

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-workspace/lib/client.js',
  `\t\t\t\t{
\t\t\t\t\tid: "archive",
\t\t\t\t\tlabel: t("menu.archiveSession"),
\t\t\t\t\ticon: (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.IconArchiveOutline20, { size: 16 })
\t\t\t\t}
\t\t\t];`,
  `\t\t\t\t{
\t\t\t\t\tid: "archive",
\t\t\t\t\tlabel: t("menu.archiveSession"),
\t\t\t\t\ticon: (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.IconArchiveOutline20, { size: 16 })
\t\t\t\t},
\t\t\t\t{
\t\t\t\t\tid: "delete",
\t\t\t\t\tlabel: t("menu.deleteSession"),
\t\t\t\t\ticon: (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.IconTrashOutline16, {})
\t\t\t\t}
\t\t\t];`,
);

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-workspace/lib/client.js',
  `\t\t\t\t\t\t\t\t\tif (id === "archive") onArchive(node.id);`,
  `\t\t\t\t\t\t\t\t\tif (id === "archive") onArchive(node.id);
\t\t\t\t\t\t\t\t\tif (id === "delete") window.chrome?.webview?.postMessage({
\t\t\t\t\t\t\t\t\t\ttype: "vibekits.deleteSession",
\t\t\t\t\t\t\t\t\t\tsessionId: node.id,
\t\t\t\t\t\t\t\t\t\ttitle
\t\t\t\t\t\t\t\t\t});`,
  `type: "vibekits.deleteSession"`,
);

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-workspace/lib/client.js',
  `\t\t\t"menu.archiveSession": "归档会话",`,
  `\t\t\t"menu.archiveSession": "归档会话",
\t\t\t"menu.deleteSession": "删除会话",`,
);

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-workspace/lib/client.js',
  `\t\t\t"menu.archiveSession": "Archive session",`,
  `\t\t\t"menu.archiveSession": "Archive session",
\t\t\t"menu.deleteSession": "Delete session",`,
);

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-settings-models/lib/client.js',
  `\t\t\t\t\t\t\tdisabled: disabled || keyLocked,
\t\t\t\t\t\t\tonChange: (event) => {
\t\t\t\t\t\t\t\tsetKeyDraft(event.target.value);
\t\t\t\t\t\t\t}`,
  `\t\t\t\t\t\t\tdisabled: disabled || keyLocked,
\t\t\t\t\t\t\tonKeyDown: (event) => {
\t\t\t\t\t\t\t\tif (!(event.ctrlKey || event.metaKey) || event.key.toLowerCase() !== "v") return;
\t\t\t\t\t\t\t\tevent.preventDefault();
\t\t\t\t\t\t\t\tnavigator.clipboard.readText().then((text) => {
\t\t\t\t\t\t\t\t\tsetKeyDraft(text);
\t\t\t\t\t\t\t\t}).catch(() => {});
\t\t\t\t\t\t\t},
\t\t\t\t\t\t\tonChange: (event) => {
\t\t\t\t\t\t\t\tsetKeyDraft(event.target.value);
\t\t\t\t\t\t\t}`,
);

// rc.7 shipped the transition tokens as a standalone CSS file. rc.2 moved
// them into the official frontend bundle, so only patch the legacy layout
// when that source file is actually present.
try {
	await replaceOnce(
		'node_modules/@deepseek-ai/dsh-client-ui-theme/lib/styles/base.css',
		`  --ds-transition-duration: 0.2s;
  --ds-transition-duration-fast: 0.1s;
  --ds-transition-duration-slow: 0.3s;`,
		`  --ds-transition-duration: 0.08s;
  --ds-transition-duration-fast: 0.06s;
  --ds-transition-duration-slow: 0.12s;`,
	);
} catch (error) {
	if (error?.code !== 'ENOENT') throw error;
}

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-settings-models/lib/client.js',
  `\t\t\t\t\t\t\t\tdisabled,
\t\t\t\t\t\t\t\tonChange: (event) => {
\t\t\t\t\t\t\t\t\tsetKeyDraft(event.target.value);
\t\t\t\t\t\t\t\t}`,
  `\t\t\t\t\t\t\t\tdisabled,
\t\t\t\t\t\t\t\tonKeyDown: (event) => {
\t\t\t\t\t\t\t\t\tif (!(event.ctrlKey || event.metaKey) || event.key.toLowerCase() !== "v") return;
\t\t\t\t\t\t\t\t\tevent.preventDefault();
\t\t\t\t\t\t\t\t\tnavigator.clipboard.readText().then((text) => {
\t\t\t\t\t\t\t\t\t\tsetKeyDraft(text);
\t\t\t\t\t\t\t\t\t}).catch(() => {});
\t\t\t\t\t\t\t\t},
\t\t\t\t\t\t\t\tonChange: (event) => {
\t\t\t\t\t\t\t\t\tsetKeyDraft(event.target.value);
\t\t\t\t\t\t\t\t}`,
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

// Official DSH heals its profile fallback by walking the complete transitive
// dependency graph and checking one junction for every package. The bundled
// Windows runtime contains tens of thousands of files, so Defender and a busy
// system drive can turn that synchronous walk into a 30-50 second cold boot.
// A single junction to the installation-owned node_modules directory provides
// the exact same Node parent-directory fallback and is also correct on the
// first launch. Profile-local plugins still take precedence in their own
// node_modules directory.
const appBootFile =
  'node_modules/@deepseek-ai/dsh-app-boot/lib/index.js';
await replaceOnce(
  appBootFile,
  'existsSync, lstatSync, mkdirSync, readFileSync, readlinkSync, symlinkSync, unlinkSync, writeFileSync',
  'existsSync, lstatSync, mkdirSync, readFileSync, readlinkSync, rmSync, symlinkSync, unlinkSync, writeFileSync',
  'readlinkSync, rmSync, symlinkSync',
);
await replaceRegexOnce(
  appBootFile,
  /function healProfilesModuleFallback\(installAnchor, home = resolveDshHome\(\)\) \{[\s\S]*?\n\}\n(?=\/\*\*\n\* Read a profile's manifest\.)/g,
  `function healProfilesModuleFallback(installAnchor, home = resolveDshHome()) {
	const modulesDir = join(join(home, PROFILES_DIR), "node_modules");
	const runtimeModules = dirname(dirname(dirname(installAnchor)));
	let stat;
	try {
		stat = lstatSync(modulesDir);
	} catch {
		stat = void 0;
	}
	if (stat?.isSymbolicLink() && readlinkSync(modulesDir) === runtimeModules) return;
	if (stat !== void 0) {
		if (stat.isSymbolicLink()) unlinkSync(modulesDir);
		else rmSync(modulesDir, { recursive: true, force: true });
	}
	mkdirSync(dirname(modulesDir), { recursive: true });
	symlinkSync(runtimeModules, modulesDir, "junction");
}`,
  'const runtimeModules = dirname(dirname(dirname(installAnchor)));',
);

console.log(`Patched Harness Web runtime: ${runtime}`);
