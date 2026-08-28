const port = Number.parseInt(process.argv[2] ?? '', 10);
const prompt = process.argv.slice(3).join(' ').trim();
if (!Number.isInteger(port) || !prompt) {
  throw new Error('Usage: node tool/harness_submit_prompt.mjs <debug-port> <prompt>');
}

const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) => item.url.startsWith('http://127.0.0.1:'));
if (!target?.webSocketDebuggerUrl) throw new Error('Harness WebView target not found');
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener('open', resolve, { once: true });
  socket.addEventListener('error', reject, { once: true });
});
let nextId = 1;
const pending = new Map();
socket.addEventListener('message', (event) => {
  const message = JSON.parse(event.data);
  const item = pending.get(message.id);
  if (!item) return;
  pending.delete(message.id);
  if (message.error) item.reject(new Error(JSON.stringify(message.error)));
  else item.resolve(message.result);
});
function call(method, params = {}) {
  const id = nextId++;
  socket.send(JSON.stringify({ id, method, params }));
  return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
}
async function evaluate(expression) {
  const response = await call('Runtime.evaluate', {
    expression,
    awaitPromise: true,
    returnByValue: true,
  });
  if (response.exceptionDetails) throw new Error(response.exceptionDetails.text);
  return response.result?.value;
}

const prepared = await evaluate(`(() => {
  const editor = [...document.querySelectorAll('textarea')]
    .find((node) => node.getClientRects().length && !node.disabled && !node.readOnly);
  if (!editor) return false;
  const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
  setter.call(editor, ${JSON.stringify(prompt)});
  editor.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }));
  editor.focus();
  return editor.value;
})()`);
if (prepared !== prompt) throw new Error('Harness prompt editor did not accept text');
await new Promise((resolve) => setTimeout(resolve, 250));
await call('Input.dispatchKeyEvent', {
  type: 'rawKeyDown',
  key: 'Enter',
  code: 'Enter',
  windowsVirtualKeyCode: 13,
  nativeVirtualKeyCode: 13,
});
await call('Input.dispatchKeyEvent', {
  type: 'keyUp',
  key: 'Enter',
  code: 'Enter',
  windowsVirtualKeyCode: 13,
  nativeVirtualKeyCode: 13,
});
await new Promise((resolve) => setTimeout(resolve, 500));
const remaining = await evaluate(`(() => {
  const editor = [...document.querySelectorAll('textarea')]
    .find((node) => node.getClientRects().length);
  return editor?.value ?? null;
})()`);
console.log(JSON.stringify({ submitted: remaining === '', remaining }));
socket.close();
if (remaining !== '') process.exitCode = 1;
