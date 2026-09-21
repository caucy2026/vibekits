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
assert.ok(!source.includes('menu.appendChild(child)'), 'child relations must not duplicate the creation action');
console.log('PASS: context menu keeps one derivation and one delete action without stale duplicates');

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
