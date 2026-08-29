const port = Number.parseInt(process.argv[2] ?? '', 10);
if (!Number.isInteger(port)) {
  throw new Error('Usage: node tool/harness_dump_text.mjs <debug-port>');
}

const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) => item.url.startsWith('http://127.0.0.1:'));
if (!target?.webSocketDebuggerUrl) throw new Error('Harness WebView target not found');
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener('open', resolve, { once: true });
  socket.addEventListener('error', reject, { once: true });
});
const id = 1;
socket.send(JSON.stringify({
  id,
  method: 'Runtime.evaluate',
  params: {
    expression: 'document.body.innerText',
    returnByValue: true,
  },
}));
const response = await new Promise((resolve, reject) => {
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== id) return;
    if (message.error) reject(new Error(JSON.stringify(message.error)));
    else resolve(message);
  });
  socket.addEventListener('error', reject, { once: true });
});
console.log(response.result?.result?.value ?? '');
socket.close();
