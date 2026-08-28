const port = Number.parseInt(process.argv[2] ?? '9333', 10);
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
  const resolve = pending.get(message.id);
  if (!resolve) return;
  pending.delete(message.id);
  resolve(message.result);
});
function call(method, params = {}) {
  const id = nextId++;
  socket.send(JSON.stringify({ id, method, params }));
  return new Promise((resolve) => pending.set(id, resolve));
}
const response = await call('Runtime.evaluate', {
  expression: `document.body.innerText.slice(-16000)`,
  returnByValue: true,
});
console.log(response.result.value);
socket.close();
