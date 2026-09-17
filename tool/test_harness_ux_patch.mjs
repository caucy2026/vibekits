import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import vm from 'node:vm';

const runtime = resolve(process.argv[2] ?? 'native/harness/macos/runtime');
const approval = await readFile(join(runtime,
  'node_modules/@deepseek-ai/dsh-client-ui-approval/lib/client.js'), 'utf8');
const conversation = await readFile(join(runtime,
  'node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js'), 'utf8');
const css = await readFile('assets/harness/codex_conversation_ux.js', 'utf8');

const start = approval.indexOf('const vibekitsRememberedApprovals = new Set();');
const end = approval.indexOf('function ApprovalFlow({ pending, detail, t }) {', start);
assert.ok(start >= 0 && end > start, 'approval helper is packaged');
const storage = new Map();
const context = vm.createContext({
  localStorage: {
    getItem: (key) => storage.get(key) ?? null,
    setItem: (key, value) => storage.set(key, value),
  },
});
vm.runInContext(`${approval.slice(start, end)}\n`
  + 'globalThis.testApproval = { key: vibekitsApprovalKey, remembered: vibekitsApprovalRemembered, remember: vibekitsRememberApproval };', context);
const { key, remembered, remember } = context.testApproval;
const approved = key('session-a', 'bash', 'write /repo/a.dart');
assert.equal(remembered(approved), false);
remember(approved);
assert.equal(remembered(approved), true);
assert.equal(storage.get(approved), 'allowed');
assert.equal(remembered(key('session-b', 'bash', 'write /repo/a.dart')), false);
assert.equal(remembered(key('session-a', 'different-tool', 'write /repo/a.dart')), false);
assert.equal(remembered(key('session-a', 'bash', 'write /repo/b.dart')), false);
assert.match(approval, /vibekitsApprovalRemembered\(vibekitsApprovalKey\(sessionId, request\.toolName, request\.reason\)\)/);
assert.match(approval, /children: t\("allowSameTask"\)/);

const queueStart = conversation.indexOf('function QueueDock(');
const queueEnd = conversation.indexOf('const queueDockEntry =', queueStart);
assert.ok(queueStart >= 0 && queueEnd > queueStart);
const queue = conversation.slice(queueStart, queueEnd);
assert.match(queue, /kind: "steer"/);
assert.doesNotMatch(queue, /side: "bottom"/);
assert.match(queue, /side: "top"/);
assert.match(conversation, /"queue\.steer": "立即补充当前任务"/);
assert.equal((conversation.match(/"placeholder\.steerQueue": ""/g) ?? []).length, 2);
assert.match(css, /\[data-composer-card\] \[data-input-scroll\] \[contenteditable="true"\]/);
assert.match(css, /cursor: text !important/);
console.log('Harness approval scope, queue actions, tooltip placement, and text cursor passed');
