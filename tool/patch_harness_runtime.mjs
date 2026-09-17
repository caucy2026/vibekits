import { readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';

const runtime = resolve(process.argv[2] ?? 'native/harness/windows/runtime');

// WKWebView can reject the official multi-resource combo script before the
// request reaches Harness. Keep each application script in its own supported
// batch; the official client already supports an arbitrary batch list.
await replaceOneOf(
  'node_modules/@deepseek-ai/dsh-client-modules/lib/index.js',
  [
    'const MAX_COMBO_URL_BYTES = 3 * 1024;',
    'const MAX_COMBO_URL_BYTES = 1800;',
  ],
  `const MAX_COMBO_URL_BYTES = 1800;
const MAX_COMBO_ENTRIES = 1;`,
  ['const MAX_COMBO_ENTRIES = 1;'],
);

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-modules/lib/index.js',
  'if (projectedComboUrlBytes(candidate) <= MAX_COMBO_URL_BYTES) {',
  'if (candidate.length <= MAX_COMBO_ENTRIES && projectedComboUrlBytes(candidate) <= MAX_COMBO_URL_BYTES) {',
  'candidate.length <= MAX_COMBO_ENTRIES',
);

async function replaceOnce(relativePath, before, after, marker = after) {
  const filename = join(runtime, relativePath);
  const source = await readFile(filename, 'utf8');
  // Many replacements deliberately keep the original snippet inside the
  // patched result (for example an existing menu action followed by a new
  // action). Check the complete result first, otherwise every build injects
  // the same patch again.
  const markers = Array.isArray(marker) ? marker : [marker];
  if (markers.some((candidate) => source.includes(candidate))) return;
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

async function replaceOneOf(relativePath, candidates, after, compatibleMarkers = []) {
  const filename = join(runtime, relativePath);
  const source = await readFile(filename, 'utf8');
  if (source.includes(after) || compatibleMarkers.some((marker) => source.includes(marker))) return;
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
\t\t\t};`,
  `\t\t\tconst onBlur = (event) => {
\t\t\t\tif (event.relatedTarget instanceof Node && (rootRef.current?.contains(event.relatedTarget) === true || menuRef.current?.contains(event.relatedTarget) === true)) return;
\t\t\t\tclose();
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
  [`"preset.fullAccess": "完全权限"`],
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
  [
    `"access.preset.fullAccess": "完全权限"`,
    `"danger-full-access": "完全访问"`,
  ],
);

// VibeKits treats a message entered while the current turn is running as a
// correction to that same turn. Harness still keeps "queue" available in its
// setting, but a fresh profile defaults to steering at the next safe agent
// step so the latest user instruction can change the active plan immediately.
await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js',
  'const DEFAULT_BUSY_ENTER_BEHAVIOR = "queue";',
  'const DEFAULT_BUSY_ENTER_BEHAVIOR = "steer";',
);

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js',
  '"input.send.steer": "插话发送",',
  '"input.send.steer": "补充并纠正",',
);

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js',
  '"settings.enter.steer": "插话发送",',
  '"settings.enter.steer": "补充并纠正",',
);

// Keep queued-message actions discoverable above the composer, while the
// composer itself stays free of a keyboard-shortcut instruction.
await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js',
  '"placeholder.steerQueue": "Cmd/Ctrl+Enter 插话发送全部排队消息",',
  '"placeholder.steerQueue": "",',
);
{
  const filename = join(runtime, 'node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js');
  const source = await readFile(filename, 'utf8');
  const before = '"placeholder.steerQueue": "Cmd/Ctrl+Enter steers all queued messages",';
  if (source.includes(before)) {
    await writeFile(filename, source.replace(before, '"placeholder.steerQueue": "",'), 'utf8');
  } else if ((source.match(/"placeholder\.steerQueue": ""/g) ?? []).length !== 2) {
    throw new Error('Harness English queue placeholder target missing');
  }
}
await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js',
  '"queue.edit": "编辑排队消息",',
  '"queue.edit": "编辑这条补充",',
);
await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js',
  '"queue.remove": "删除排队消息",',
  '"queue.remove": "删除这条补充",',
);
await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js',
  '"queue.steer": "插话发送",',
  '"queue.steer": "立即补充当前任务",',
);
{
  const relativePath = 'node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js';
  const filename = join(runtime, relativePath);
  const source = await readFile(filename, 'utf8');
  const start = source.indexOf('function QueueDock(');
  const end = source.indexOf('const queueDockEntry =', start);
  if (start < 0 || end < 0) throw new Error(`Harness queue tooltip target missing: ${relativePath}`);
  const before = source.slice(start, end);
  const after = before.replaceAll('side: "bottom",', 'side: "top",');
  if (before !== after) await writeFile(filename, source.slice(0, start) + after + source.slice(end), 'utf8');
}

// The upstream UI only grants once. Remember only an exact request within the
// same session, so a new operation or a new session must still be reviewed.
{
  const relativePath = 'node_modules/@deepseek-ai/dsh-client-ui-approval/lib/client.js';
  const filename = join(runtime, relativePath);
  let source = await readFile(filename, 'utf8');
  const replaceUnique = (before, after) => {
    const first = source.indexOf(before);
    if (first < 0 || source.indexOf(before, first + before.length) >= 0) {
      throw new Error(`Harness approval patch target missing or ambiguous: ${before.slice(0, 60)}`);
    }
    source = source.slice(0, first) + after + source.slice(first + before.length);
  };
  const approvalHelpers = `const vibekitsRememberedApprovals = new Set();
\t\tfunction vibekitsApprovalKey(sessionId, toolName, reason) {
\t\t\treturn "vibekits.approval.v1:" + JSON.stringify([sessionId, toolName, reason ?? ""]);
\t\t}
\t\tfunction vibekitsApprovalRemembered(key) {
\t\t\tif (vibekitsRememberedApprovals.has(key)) return true;
\t\t\ttry { return localStorage.getItem(key) === "allowed"; } catch { return false; }
\t\t}
\t\tfunction vibekitsRememberApproval(key) {
\t\t\tvibekitsRememberedApprovals.add(key);
\t\t\ttry { localStorage.setItem(key, "allowed"); } catch {}
\t\t}
\t\tfunction ApprovalFlow({ pending, detail, t }) {`;
  if (!source.includes('function vibekitsApprovalRemembered(key)')) {
    if (source.includes('const vibekitsRememberedApprovals = new Set();')) {
      replaceUnique(`const vibekitsRememberedApprovals = new Set();
\t\tfunction vibekitsApprovalKey(sessionId, toolName, reason) {
\t\t\treturn JSON.stringify([sessionId, toolName, reason ?? ""]);
\t\t}
\t\tfunction ApprovalFlow({ pending, detail, t }) {`, approvalHelpers);
    } else {
      replaceUnique('function ApprovalFlow({ pending, detail, t }) {', approvalHelpers);
    }
  }
  if (!source.includes('children: t("allowSameTask")')) {
    replaceUnique(`children: t("allowOnce")
\t\t\t\t\t\t\t})]`, `children: t("allowOnce")
\t\t\t\t\t\t\t}), (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.Button, {
\t\t\t\t\t\t\t\tvariant: "outline",
\t\t\t\t\t\t\t\tdisabled: answered,
\t\t\t\t\t\t\t\tonClick: () => {
\t\t\t\t\t\t\t\t\tvibekitsRememberApproval(vibekitsApprovalKey(pending.sessionId, pending.toolName, pending.reason));
\t\t\t\t\t\t\t\t\tanswer("allowed-once");
\t\t\t\t\t\t\t\t},
\t\t\t\t\t\t\t\tchildren: t("allowSameTask")
\t\t\t\t\t\t\t})]`);
  } else if (source.includes('vibekitsRememberedApprovals.add(vibekitsApprovalKey(')) {
    replaceUnique('vibekitsRememberedApprovals.add(vibekitsApprovalKey(pending.sessionId, pending.toolName, pending.reason));', 'vibekitsRememberApproval(vibekitsApprovalKey(pending.sessionId, pending.toolName, pending.reason));');
  }
  if (!source.includes('allowSameTask: "本任务同类操作不再询问"')) {
    replaceUnique('allowOnce: "允许一次"', 'allowOnce: "允许一次",\n\t\t\tallowSameTask: "本任务同类操作不再询问"');
  }
  if (!source.includes('allowSameTask: "Allow same request in this task"')) {
    replaceUnique('allowOnce: "Allow once"', 'allowOnce: "Allow once",\n\t\t\tallowSameTask: "Allow same request in this task"');
  }
  if (source.includes('vibekitsRememberedApprovals.has(vibekitsApprovalKey(sessionId,')) {
    replaceUnique('vibekitsRememberedApprovals.has(vibekitsApprovalKey(sessionId,', 'vibekitsApprovalRemembered(vibekitsApprovalKey(sessionId,');
  } else if (!source.includes('vibekitsApprovalRemembered(vibekitsApprovalKey(sessionId,')) {
    replaceUnique('const pending = new PendingApproval(sessionId, {', 'if (vibekitsApprovalRemembered(vibekitsApprovalKey(sessionId, request.toolName, request.reason))) return "allowed-once";\n\t\t\tconst pending = new PendingApproval(sessionId, {');
  }
  await writeFile(filename, source, 'utf8');
}

await replaceOneOf(
  'node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js',
  [`\t\t\t(0, react.useEffect)(() => {
\t\t\t\tif (inputState.draft === "" && storedDraft !== "") inputActions.setDraft(storedDraft);
\t\t\t\tconst unmirror = bindDraftMirror(actions.setDraft);
\t\t\t\treturn () => {
\t\t\t\t\tunmirror();
\t\t\t\t};
\t\t\t}, [inputActions]);`],
  `\t\t\t(0, react.useEffect)(() => {
\t\t\t\tif (inputState.draft === "" && storedDraft !== "") inputActions.setDraft(storedDraft);
\t\t\t}, [inputActions, inputState.draft, storedDraft]);
\t\t\t(0, react.useEffect)(() => {
\t\t\t\tconst unmirror = bindDraftMirror(actions.setDraft);
\t\t\t\treturn () => {
\t\t\t\t\tunmirror();
\t\t\t\t};
\t\t\t}, [actions, bindDraftMirror, inputActions]);`,
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
\t\t\t\t\t\t\t\t\tif (id === "delete") {
\t\t\t\t\t\t\t\t\t\tconst message = JSON.stringify({
\t\t\t\t\t\t\t\t\t\t\ttype: "vibekits.deleteSession",
\t\t\t\t\t\t\t\t\t\t\tsessionId: node.id,
\t\t\t\t\t\t\t\t\t\t\ttitle
\t\t\t\t\t\t\t\t\t\t});
\t\t\t\t\t\t\t\t\t\tif (window.chrome?.webview?.postMessage) window.chrome.webview.postMessage(message);
\t\t\t\t\t\t\t\t\t\telse window.VibekitsHost?.postMessage(message);
\t\t\t\t\t\t\t\t\t}`,
  `type: "vibekits.deleteSession"`,
);

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-workspace/lib/client.js',
  `\t\t\tconst now = Date.now();
\t\t\tconst commitSessionDrag = (activeDrag, over) => {`,
  `\t\t\tconst now = Date.now();
\t\t\tconst requestSessionProjectMove = (activeDrag, targetWorkspaceId) => {
\t\t\t\tif (activeDrag.accountKey === "" || activeDrag.accountKey === targetWorkspaceId) return;
\t\t\t\tconst source = orderedWorkspaces.find((workspace) => workspace.workspaceId === activeDrag.accountKey);
\t\t\t\tconst target = orderedWorkspaces.find((workspace) => workspace.workspaceId === targetWorkspaceId);
\t\t\t\tif (source === void 0 || target === void 0) return;
\t\t\t\tconst message = JSON.stringify({
\t\t\t\t\ttype: "vibekits.moveSession",
\t\t\t\t\tsessionId: activeDrag.sessionId,
\t\t\t\t\tsourceWorkspaceId: source.workspaceId,
\t\t\t\t\tsourceLabel: source.title,
\t\t\t\t\ttargetWorkspaceId: target.workspaceId,
\t\t\t\t\ttargetLabel: target.title
\t\t\t\t});
\t\t\t\tif (window.chrome?.webview?.postMessage) window.chrome.webview.postMessage(message);
\t\t\t\telse window.VibekitsHost?.postMessage(message);
\t\t\t};
\t\t\tconst commitSessionDrag = (activeDrag, over) => {`,
  `type: "vibekits.moveSession"`,
);

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-ui-workspace/lib/client.js',
  `\t\t\t\t\t\t\t\tonDragOver: workspaceDrag === null || hoverWorkspace === void 0 ? void 0 : (e) => {
\t\t\t\t\t\t\t\t\te.preventDefault();
\t\t\t\t\t\t\t\t\te.dataTransfer.dropEffect = "move";
\t\t\t\t\t\t\t\t\thoverWorkspace(workspaceGroupHalf(e));
\t\t\t\t\t\t\t\t},
\t\t\t\t\t\t\t\tonDrop: workspaceDrag === null || dropWorkspace === void 0 ? void 0 : (e) => {
\t\t\t\t\t\t\t\t\te.preventDefault();
\t\t\t\t\t\t\t\t\tdropWorkspace(workspaceGroupHalf(e));
\t\t\t\t\t\t\t\t},`,
  `\t\t\t\t\t\t\t\tonDragOver: (e) => {
\t\t\t\t\t\t\t\t\tif (workspaceDrag !== null && hoverWorkspace !== void 0) {
\t\t\t\t\t\t\t\t\t\te.preventDefault();
\t\t\t\t\t\t\t\t\t\te.dataTransfer.dropEffect = "move";
\t\t\t\t\t\t\t\t\t\thoverWorkspace(workspaceGroupHalf(e));
\t\t\t\t\t\t\t\t\t\treturn;
\t\t\t\t\t\t\t\t\t}
\t\t\t\t\t\t\t\t\tif (drag !== null && workspaceId !== void 0 && drag.accountKey !== workspaceId) {
\t\t\t\t\t\t\t\t\t\te.preventDefault();
\t\t\t\t\t\t\t\t\t\te.dataTransfer.dropEffect = "move";
\t\t\t\t\t\t\t\t\t}
\t\t\t\t\t\t\t\t},
\t\t\t\t\t\t\t\tonDrop: (e) => {
\t\t\t\t\t\t\t\t\tif (workspaceDrag !== null && dropWorkspace !== void 0) {
\t\t\t\t\t\t\t\t\t\te.preventDefault();
\t\t\t\t\t\t\t\t\t\tdropWorkspace(workspaceGroupHalf(e));
\t\t\t\t\t\t\t\t\t\treturn;
\t\t\t\t\t\t\t\t\t}
\t\t\t\t\t\t\t\t\tif (drag !== null && workspaceId !== void 0 && drag.accountKey !== workspaceId) {
\t\t\t\t\t\t\t\t\t\te.preventDefault();
\t\t\t\t\t\t\t\t\t\tsessionDropCommitted.current = true;
\t\t\t\t\t\t\t\t\t\tsetDrag(null);
\t\t\t\t\t\t\t\t\t\trequestSessionProjectMove(drag, workspaceId);
\t\t\t\t\t\t\t\t\t}
\t\t\t\t\t\t\t\t},`,
  `requestSessionProjectMove(drag, workspaceId);`,
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
for (const [candidates, after] of [
  [['确认启用 Full access？', '确认启用完全权限？'], '确认启用完全访问？'],
  [['启用 Full access 后', '启用完全权限后'], '启用完全访问后'],
  [['启用 Full access', '启用完全权限'], '启用完全访问'],
]) {
  const filename = join(runtime, permissionFile);
  const source = await readFile(filename, 'utf8');
  if (source.includes(after)) continue;
  const matches = candidates.filter((candidate) => source.includes(candidate));
  if (matches.length !== 1) {
    throw new Error(`Harness permission locale target count ${matches.length}: ${candidates.join(' | ')}`);
  }
  await writeFile(filename, source.split(matches[0]).join(after), 'utf8');
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
const appBootSource = await readFile(join(runtime, appBootFile), 'utf8');
const usesLockedModuleFallback = appBootSource.includes(
  'async function healProfilesModuleFallback(options)',
);
if (!usesLockedModuleFallback) {
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
}

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-web-app/lib/index.js',
  `function resolveDistIndex() {
	const require = createRequire(import.meta.url);
	try {
		return join(dirname(require.resolve("@deepseek-ai/dsh-web-frontend/package.json")), "dist", "index.html");`,
  `function resolveDistIndex() {
	const compatibilityIndex = process.env.VIBEKITS_DSH_WEB_DIST_INDEX;
	if (compatibilityIndex) return compatibilityIndex;
	const require = createRequire(import.meta.url);
	try {
		return join(dirname(require.resolve("@deepseek-ai/dsh-web-frontend/package.json")), "dist", "index.html");`,
  'const compatibilityIndex = process.env.VIBEKITS_DSH_WEB_DIST_INDEX;',
);

await replaceOnce(
  'node_modules/@deepseek-ai/dsh-client-modules/lib/index.js',
  'clientPath: join(dirname(pkgPath), clientRel),',
  `clientPath: process.env.VIBEKITS_DSH_WEB_DIST_INDEX
					? join(dirname(pkgPath), clientRel).replace(/\\.js$/, ".macos12.js")
					: join(dirname(pkgPath), clientRel),`,
  'join(dirname(pkgPath), clientRel).replace(/\\.js$/, ".macos12.js")',
);

console.log(`Patched Harness Web runtime: ${runtime}`);
