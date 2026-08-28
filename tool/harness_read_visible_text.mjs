const port = Number.parseInt(process.argv[2] ?? '', 10);
if (!Number.isInteger(port)) throw new Error('Usage: node tool/harness_read_visible_text.mjs <debug-port>');
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
const response = await call('Runtime.evaluate', {
  expression: `(() => document.body?.innerText ?? '')()`,
  returnByValue: true,
});
const text = response.result?.value ?? '';
console.log(text.slice(-24000));
socket.close();
