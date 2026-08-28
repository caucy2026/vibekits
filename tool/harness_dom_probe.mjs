const portArgument = process.argv.find((value) => value.startsWith('--port='));
const debugPort = Number.parseInt(portArgument?.slice('--port='.length) ?? '9333', 10);
const targets = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json();
const target = targets.find((item) => item.url.startsWith('http://127.0.0.1:'));
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener('open', resolve, { once: true });
  socket.addEventListener('error', reject, { once: true });
});
let id = 1;
const pending = new Map();
socket.addEventListener('message', (event) => {
  const message = JSON.parse(event.data);
  const item = pending.get(message.id);
  if (!item) return;
  pending.delete(message.id);
  item(message.result);
});
function call(method, params) {
  const current = id++;
  socket.send(JSON.stringify({ id: current, method, params }));
  return new Promise((resolve) => pending.set(current, resolve));
}
const result = await call('Runtime.evaluate', {
  expression: `(() => { const e = [...document.querySelectorAll('textarea')].find(x => x.getClientRects().length); if (!e) return null; ${process.argv.includes('--clear') ? "e.value=''; e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'deleteContentBackward'}));" : ''} const r=e.getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height,dpr:devicePixelRatio,outerWidth,outerHeight,innerWidth,innerHeight,value:e.value}; })()`,
  returnByValue: true,
});
console.log(JSON.stringify(result.result.value));
socket.close();
