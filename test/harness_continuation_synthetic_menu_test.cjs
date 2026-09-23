const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/harness/codex_conversation_ux.js', 'utf8');
const start = source.indexOf('  const showSyntheticContinuationMenu =');
const end = source.indexOf('  window.__vibekitsSetSessionDeleteState =', start);
assert.ok(start >= 0 && end > start);

class Element {
  children = [];
  handlers = {};
  style = {};
  classList = {contains: (name) =>
    (this.className || '').split(' ').includes(name)};
  offsetParent = {};
  appendChild(child) { child.parentElement = this; this.children.push(child); }
  setAttribute() {}
  addEventListener(name, handler) { this.handlers[name] = handler; }
  focus() {}
  remove() { this.removed = true; }
  contains(target) { return this === target || this.children.includes(target); }
  closest(selector) {
    if (selector === '.vibekits-synthetic-session-menu') {
      let node = this;
      while (node) {
        if (node.classList.contains('vibekits-synthetic-session-menu')) return node;
        node = node.parentElement;
      }
    }
    return null;
  }
  querySelectorAll(selector) {
    if (selector.startsWith('.')) {
      return this.children.filter((child) => child.classList.contains(selector.slice(1)));
    }
    return this.children;
  }
  cloneNode() {
    const clone = new Element();
    clone.className = this.className;
    clone.textContent = this.textContent;
    return clone;
  }
  getBoundingClientRect() { return {left: 250, right: 400, bottom: 160, width: 160, height: 210}; }
}
const body = new Element();
const documentHandlers = {};
const document = {
  body,
  querySelector: () => body.children.find((child) =>
    child.className === 'vibekits-synthetic-session-menu' && !child.removed) || null,
  querySelectorAll: (selector) => selector === '[role="menu"]'
    ? body.children.filter((child) =>
      !child.removed && child.classList.contains('vibekits-synthetic-session-menu'))
    : selector.startsWith('button,')
      ? body.children.filter((child) => !child.removed)
        .flatMap((child) => child.children) : [],
  createElement: () => new Element(),
  addEventListener: (name, handler) => { documentHandlers[name] = handler; },
};
const calls = [];
const sourceRow = new Element();
sourceRow.className = 'official-row';
sourceRow.__reactFiber$test = {memoizedProps: {
  onRename: (...args) => calls.push(['rename', ...args]),
  onFork: (...args) => calls.push(['fork', ...args]),
  onArchive: (...args) => calls.push(['archive', ...args]),
}};
const child = new Element();
child.className = 'vibekits-synthetic-continuation-row';
const context = {
  document,
  Element,
  HTMLElement: Element,
  window: {innerWidth: 800, innerHeight: 600},
  contextSessionRow: null,
  visibleSessionRows: () => [child, sourceRow],
  sessionIdForRow: () => 'session-child',
  sessionTitleForRow: () => 'Child',
  requestContinuationFromMenu: () => calls.push(['derive', context.contextSessionRow]),
  requestDeleteFromMenu: () => calls.push(['delete', context.contextSessionRow]),
  replaceMenuItemLabel: (item, label) => { item.textContent = label; },
  replaceNewSessionIcon: () => {},
  replaceDeleteSessionIcon: () => {},
  requestAnimationFrame: (callback) => callback(),
  postHostMessage: () => {},
};
vm.runInNewContext(
  source.slice(start, end) +
    source.slice(
      source.indexOf('  const decorateSessionContextMenu ='),
      source.indexOf('  if (!window.__vibekitsSessionContextMenuInstalled)'),
    ) +
    'globalThis.showMenu = showSyntheticContinuationMenu;' +
    'globalThis.decorateMenu = decorateSessionContextMenu;',
  context,
);
const action = {getBoundingClientRect: () => ({left: 250, bottom: 160})};
const labels = ['重命名', '分叉会话', '归档会话', '派生会话', '删除会话'];
for (let index = 0; index < labels.length; index += 1) {
  context.showMenu(child, action);
  const menu = body.children.at(-1);
  assert.deepEqual(menu.children.map((item) => item.textContent), labels);
  assert.equal(menu.style.left, '236px', 'menu stays within the session sidebar');
  context.contextSessionRow = child;
  context.decorateMenu();
  assert.deepEqual(menu.children.map((item) => item.textContent), labels,
    'official menu decoration must not append duplicate actions to synthetic menu');
  menu.children[index].handlers.click({preventDefault() {}, stopPropagation() {}});
  assert.equal(menu.removed, true);
}
assert.deepEqual(calls, [
  ['rename', 'session-child', 'Child'],
  ['fork', 'session-child'],
  ['archive', 'session-child'],
  ['derive', child],
  ['delete', child],
]);
const nativeMenu = new Element();
const archive = new Element();
archive.textContent = '归档会话';
nativeMenu.appendChild(archive);
body.appendChild(nativeMenu);
context.contextSessionRow = child;
context.decorateMenu();
context.decorateMenu();
assert.deepEqual(nativeMenu.children.map((item) => item.textContent),
  ['归档会话', '派生会话', '删除会话'],
  'native menu without role=menu must receive each extension action exactly once');
const installerStart = source.indexOf(
  '  if (!window.__vibekitsSessionContextMenuInstalled)', end,
);
const installerEnd = source.indexOf('    // React may reconcile', installerStart);
assert.ok(installerStart >= 0 && installerEnd > installerStart);
vm.runInNewContext(source.slice(installerStart, installerEnd) + '  }', context);
context.showMenu(child, action);
const outsideMenu = body.children.at(-1);
documentHandlers.pointerdown({target: new Element()});
assert.equal(outsideMenu.removed, true, 'outside click closes the menu');
context.showMenu(child, action);
const escapeMenu = body.children.at(-1);
documentHandlers.keydown({key: 'Escape'});
assert.equal(escapeMenu.removed, true, 'Escape closes the menu');
console.log('PASS: derived menu retains all five actions on the child session');
