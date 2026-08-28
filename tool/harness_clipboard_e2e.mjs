import { spawnSync } from 'node:child_process';

const endpoint = 'http://127.0.0.1:9333/json/list';
const marker = `VIBEKITS_CLIPBOARD_E2E_${Date.now()}`;
const appPid = Number.parseInt(process.argv[2] ?? '', 10);
if (!Number.isInteger(appPid) || appPid <= 0) {
  throw new Error('Usage: node tool/harness_clipboard_e2e.mjs <vibekits-pid>');
}

const targets = await (await fetch(endpoint)).json();
const target = targets.find((item) => item.url.startsWith('http://127.0.0.1:'));
if (!target?.webSocketDebuggerUrl) {
  throw new Error('Harness WebView target not found');
}

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener('open', resolve, { once: true });
  socket.addEventListener('error', reject, { once: true });
});

let nextId = 1;
const pending = new Map();
socket.addEventListener('message', (event) => {
  const message = JSON.parse(event.data);
  if (!message.id || !pending.has(message.id)) return;
  const { resolve, reject } = pending.get(message.id);
  pending.delete(message.id);
  if (message.error) reject(new Error(JSON.stringify(message.error)));
  else resolve(message.result);
});

function call(method, params = {}) {
  const id = nextId++;
  socket.send(JSON.stringify({ id, method, params }));
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}

async function dispatchShortcut(key, code, windowsVirtualKeyCode) {
  await call('Input.dispatchKeyEvent', {
    type: 'rawKeyDown',
    modifiers: 2,
    key,
    code,
    windowsVirtualKeyCode,
    nativeVirtualKeyCode: windowsVirtualKeyCode,
  });
  await call('Input.dispatchKeyEvent', {
    type: 'keyUp',
    modifiers: 2,
    key,
    code,
    windowsVirtualKeyCode,
    nativeVirtualKeyCode: windowsVirtualKeyCode,
  });
}

async function evaluate(expression) {
  const result = await call('Runtime.evaluate', {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.text || 'Runtime.evaluate failed');
  }
  return result.result?.value;
}

const editorInfo = await evaluate(`(() => {
  const nodes = [...document.querySelectorAll('textarea, input, [contenteditable]:not([contenteditable="false"])')];
  return nodes.map((node) => ({
    tag: node.tagName,
    contenteditable: node.getAttribute('contenteditable'),
    placeholder: node.getAttribute('placeholder'),
    ariaLabel: node.getAttribute('aria-label'),
    visible: Boolean(node.getClientRects().length),
    text: (node.value ?? node.innerText ?? '').slice(0, 80),
  }));
})()`);

const prepared = await evaluate(`(() => {
  const nodes = [...document.querySelectorAll('textarea, input, [contenteditable]:not([contenteditable="false"])')];
  const editor = nodes.find((node) => node.getClientRects().length &&
    (node.matches('textarea') || node.isContentEditable || node.getAttribute('role') === 'textbox'));
  if (!editor) return false;
  editor.focus();
  editor.click();
  if ('value' in editor) editor.value = '';
  else editor.innerHTML = '';
  editor.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'deleteContentBackward' }));
  return true;
})()`);

if (!prepared) {
  console.error(JSON.stringify({ ok: false, reason: 'editor-not-found', editorInfo }, null, 2));
  process.exitCode = 1;
  socket.close();
} else {
  const runPowerShell = (command) => {
    const result = spawnSync(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', command],
      { encoding: 'utf8' },
    );
    if (result.status !== 0) {
      throw new Error(result.stderr || `PowerShell exited ${result.status}`);
    }
    return result.stdout.trim();
  };

  runPowerShell(
    `Set-Clipboard -Value '${marker}'; ` +
      `$shell = New-Object -ComObject WScript.Shell; ` +
      `[void]$shell.AppActivate(${appPid}); Start-Sleep -Milliseconds 350`,
  );
  await evaluate(`(() => {
    const editor = [...document.querySelectorAll('textarea, [contenteditable]:not([contenteditable="false"])')]
      .find((node) => node.getClientRects().length);
    if (!editor) return false;
    editor.focus();
    editor.click();
    return document.activeElement === editor;
  })()`);
  await dispatchShortcut('v', 'KeyV', 86);
  await new Promise((resolve) => setTimeout(resolve, 1200));

  const pasted = await evaluate(`(() => {
    const node = document.activeElement;
    return String(node?.value ?? node?.innerText ?? '');
  })()`);

  const copyMarker = `${marker}_COPY`;
  const copyPrepared = await evaluate(`(() => {
    const nodes = [...document.querySelectorAll('textarea, input, [contenteditable]:not([contenteditable="false"])')];
    const editor = nodes.find((node) => node.getClientRects().length &&
      (node.matches('textarea') || node.isContentEditable || node.getAttribute('role') === 'textbox'));
    if (!editor) return false;
    editor.focus();
    if ('value' in editor) {
      editor.value = '${copyMarker}';
      editor.select();
    } else {
      editor.textContent = '${copyMarker}';
      const range = document.createRange();
      range.selectNodeContents(editor);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    }
    return true;
  })()`);
  if (!copyPrepared) throw new Error('Could not prepare copy selection');

  await dispatchShortcut('c', 'KeyC', 67);
  await new Promise((resolve) => setTimeout(resolve, 500));
  const copied = runPowerShell('Get-Clipboard -Raw').trim();
  const result = {
    ok: pasted === marker && copied === copyMarker,
    paste: { expected: marker, actual: pasted, passed: pasted === marker },
    copy: { expected: copyMarker, actual: copied, passed: copied === copyMarker },
    editorInfo,
  };
  console.log(JSON.stringify(result, null, 2));
  if (!result.ok) process.exitCode = 1;
  socket.close();
}
