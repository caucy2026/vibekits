const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('assets/harness/codex_conversation_ux.js', 'utf8');
const start = source.indexOf('  window.__vibekitsOpenNewestEmptySession =');
const end = source.indexOf('  window.__vibekitsSetContinuationProgress =', start);
for (const labelSource of ['aria-label', 'title', 'text']) {
  let clicks = 0;
  class HTMLElement {
    offsetParent = {};
    textContent = labelSource === 'text' ? '新建会话' : '';
    getAttribute(name) { return name === labelSource ? '新建会话' : null; }
    click() { clicks++; }
  }
  const context = {
    window: {}, HTMLElement,
    contextSessionRow: null,
    Node: {DOCUMENT_POSITION_FOLLOWING: 4},
    document: {
      querySelector: () => null,
      querySelectorAll: () => [new HTMLElement()],
    },
    requestAnimationFrame: (fn) => fn(), focusVisibleComposer() {},
  };
  vm.runInNewContext(source.slice(start, end), context);
  assert.equal(context.window.__vibekitsOpenNewestEmptySession(), true);
  assert.equal(clicks, 1, `${labelSource} button must activate once`);
}
assert.ok(!source.includes('menu.remove()'), 'React owns menu disposal');
console.log('PASS: icon-only and text new-session buttons; official menu ownership');
const navigation = source.slice(
  source.indexOf('  const openThroughOfficialWorkspace ='),
  source.indexOf('  window.__vibekitsOpenSessionByTitle ='),
);
let opened = '';
class OfficialElement {
  classList = {contains: () => false};
  __reactFiber$test = {memoizedProps: {open(id){opened=id;}}, return:null};
}
const probe = new OfficialElement();
const ctx = {
  window: {}, HTMLElement: OfficialElement,
  visibleSessionRows: () => [probe],
  sessionIdForRow: () => '', requestAnimationFrame: (fn) => fn(),
  focusVisibleComposer() {},
};
vm.runInNewContext(navigation, ctx);
const target = 'session-11111111-1111-1111-1111-111111111111';
assert.equal(ctx.window.__vibekitsOpenSession(target),true);
assert.equal(opened,target);
assert.equal(ctx.window.__vibekitsOpenSession('not-a-session'),false);
assert.equal(opened,target);
console.log('PASS: hidden blank session navigation uses official live workspace callback; invalid IDs rejected');
assert.ok(source.includes("for (const duplicate of existingActions.slice(1)) duplicate.remove()"));
assert.ok(source.includes("for (const duplicate of existingDeleteActions.slice(1)) duplicate.remove()"));
assert.ok(source.includes("replaceMenuItemLabel(deleteItem, '删除会话')"));
assert.ok(source.includes("type: 'vibekits.deleteSession'"));
assert.ok(source.includes("confirmed: true"));
assert.ok(source.includes("confirm.textContent = '确认删除'"));
assert.ok(source.includes("confirm.textContent = '正在删除…'"));
assert.ok(source.includes('document.body.appendChild(backdrop)'));
assert.ok(source.includes("confirm.className = 'vibekits-delete-confirm-button'"));
assert.ok(source.includes('window.__vibekitsSetSessionDeleteState'));
assert.ok(source.includes("action?.closest('[role=\"treeitem\"]')"));
assert.ok(!source.includes('menu.appendChild(child)'), 'child relations must not duplicate the creation action');
console.log('PASS: context menu keeps one derivation and one delete action without stale duplicates');

const deleteRequestStart = source.indexOf('  const requestDeleteFromMenu =');
const deleteRequestEnd = source.indexOf('  window.__vibekitsSetSessionDeleteState =', deleteRequestStart);
const postedDeletes = [];
class DialogElement {
  constructor(tag = 'div') {
    this.tag = tag;
    this.children = [];
    this.listeners = {};
    this.style = {};
    this.disabled = false;
    this.textContent = '';
  }
  setAttribute() {}
  append(...children) { this.children.push(...children); }
  appendChild(child) { this.children.push(child); return child; }
  addEventListener(name, listener) { this.listeners[name] = listener; }
  remove() { this.removed = true; }
  focus() { this.focused = true; }
}
const dialogBody = new DialogElement('body');
const dialogContext = {
  window: {
    __vibekitsCurrentSessionId: () => target,
    setTimeout: (callback) => callback(),
  },
  document: {
    querySelector: () => null,
    createElement: (tag) => new DialogElement(tag),
    dispatchEvent() {},
    body: dialogBody,
  },
  KeyboardEvent: class {},
  contextSessionRow: {},
  continuationRelations: [],
  sessionTitleForRow: () => '待删除会话',
  sessionIdForRow: () => target,
  postHostMessage: (message) => postedDeletes.push(message),
};
vm.runInNewContext(
  `${source.slice(deleteRequestStart, deleteRequestEnd)}\nwindow.__testDelete = requestDeleteFromMenu;`,
  dialogContext,
);
dialogContext.window.__testDelete();
assert.equal(postedDeletes.length, 0, 'opening confirmation must not delete');
const cancelledConfirmation = dialogBody.children.at(-1);
const cancelledActions = cancelledConfirmation.children[0].children[2];
cancelledActions.children[0].listeners.click();
assert.equal(cancelledConfirmation.removed, true, 'cancel closes the confirmation');
assert.equal(postedDeletes.length, 0, 'cancel must not post a delete request');
dialogContext.window.__testDelete();
const confirmation = dialogBody.children.at(-1);
const actions = confirmation.children[0].children[2];
const confirmDelete = actions.children[1];
assert.equal(confirmDelete.textContent, '确认删除');
confirmDelete.listeners.click();
assert.equal(postedDeletes.length, 1, 'confirm button posts exactly one delete');
assert.equal(postedDeletes[0].confirmed, true);
assert.equal(postedDeletes[0].sessionId, target);
assert.equal(confirmDelete.disabled, true);
assert.equal(confirmDelete.textContent, '正在删除…');
console.log('PASS: delete opens visible confirmation and only confirmation posts the request');

const deleteStateStart = source.indexOf('  window.__vibekitsSetSessionDeleteState =');
const deleteStateEnd = source.indexOf('  const decorateSessionContextMenu =', deleteStateStart);
let removed = 0;
class DeleteRow {
  style = {};
  attributes = new Set();
  title = '';
  toggleAttribute(name, enabled) {
    if (enabled) this.attributes.add(name); else this.attributes.delete(name);
  }
  getBoundingClientRect() { return {height: 42}; }
  remove() { removed++; }
}
const deleteRow = new DeleteRow();
const deleteContext = {
  window: {setTimeout: (callback) => callback()},
  HTMLElement: DeleteRow,
  HTMLButtonElement: class {},
  document: {querySelector: () => null},
  visibleSessionRows: () => [deleteRow],
  sessionIdForRow: () => target,
  sessionTitleForRow: () => '待删除会话',
  requestAnimationFrame: (callback) => callback(),
};
vm.runInNewContext(source.slice(deleteStateStart, deleteStateEnd), deleteContext);
assert.equal(deleteContext.window.__vibekitsSetSessionDeleteState(target, '', 'deleting'), true);
assert.equal(deleteRow.attributes.has('aria-busy'), true);
assert.equal(deleteRow.style.pointerEvents, 'none');
assert.equal(deleteRow.style.opacity, '0.58');
assert.equal(deleteContext.window.__vibekitsSetSessionDeleteState(target, '', 'failed', '删除失败'), true);
assert.equal(deleteRow.attributes.has('aria-busy'), false);
assert.equal(deleteRow.style.pointerEvents, '');
assert.equal(deleteRow.title, '删除失败');
assert.equal(deleteContext.window.__vibekitsSetSessionDeleteState(target, '', 'deleted'), true);
assert.equal(deleteRow.style.maxHeight, '0');
assert.equal(removed, 1);
console.log('PASS: deleting one session only fades and collapses its own sidebar row');

const selectStart = source.indexOf('  window.__vibekitsSelectVisibleSession =');
const selectEnd = source.indexOf('  window.__vibekitsOpenSessionByTitle =', selectStart);
let selected = 0;
class VisibleElement {
  classList = {contains: () => false};
  querySelector() { return {click(){selected++;}}; }
}
const selectContext = {
  window: {__vibekitsRenderContinuationProgress(){selected++;}},
  HTMLElement: VisibleElement,
  visibleSessionRows: () => [new VisibleElement()],
  sessionIdForRow: () => target,
  requestAnimationFrame: (callback) => callback(),
  focusVisibleComposer(){selected++;},
};
vm.runInNewContext(source.slice(selectStart, selectEnd), selectContext);
assert.equal(selectContext.window.__vibekitsSelectVisibleSession(target), true);
assert.equal(selected, 3, 'selection, scoped progress, and composer focus all run');
assert.equal(selectContext.window.__vibekitsSelectVisibleSession('missing'), false);
console.log('PASS: newly created visible session is selected in-place without reload');

// Official SessionNodeItem has node.id in its props, no DOM id or link.
const identitySource = source.slice(source.indexOf('  const sessionIdForRow ='), source.indexOf('  const sessionTitleForRow ='));
class IdentityRow {
  constructor(id) { this.__reactFiber$test = {memoizedProps: {}, return: {memoizedProps: {node: {id}}, return: null}}; }
  matches() { return false; }
  querySelector() { return null; }
}
const identityContext = {HTMLElement: IdentityRow, window: {}};
vm.runInNewContext(identitySource + '\nwindow.identify = sessionIdForRow;', identityContext);
const firstId = 'session-11111111-1111-1111-1111-111111111111';
const secondId = 'session-22222222-2222-2222-2222-222222222222';
assert.equal(identityContext.window.identify(new IdentityRow(firstId)), firstId);
assert.equal(identityContext.window.identify(new IdentityRow(secondId)), secondId);
assert.equal(identityContext.window.identify(new IdentityRow('workspace-test')), '');
console.log('PASS: ungrouped rows without DOM IDs resolve their own official node.id');
