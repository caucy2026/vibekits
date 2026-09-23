const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('assets/harness/codex_conversation_ux.js', 'utf8');
const start = source.indexOf('  window.__vibekitsRenderContinuationProgress =');
const end = source.indexOf('  window.__vibekitsSetContinuationProgress =', start);
assert.ok(start >= 0 && end > start);
const currentRender = source.slice(start, end);

function runRender(renderSource, isError) {
  let textMutations = 0;
  let retryRemovals = 0;
  let retryPresent = true;
  const classes = new Set(isError ? ['is-error'] : []);
  class Element {
    offsetParent = {};
    style = {};
    getBoundingClientRect() { return {left: 12, top: 100, width: 400}; }
  }
  const body = new Element();
  const label = {
    value: '正在创建派生会话…',
    get textContent() { return this.value; },
    set textContent(value) { this.value = value; textMutations++; },
  };
  const retry = {remove() { retryRemovals++; retryPresent = false; }};
  const card = new Element();
  card.parentElement = body;
  card.classList = {
    add(name) { classes.add(name); },
    remove(name) { classes.delete(name); },
    toggle(name, enabled) { if (enabled) classes.add(name); else classes.delete(name); },
  };
  card.querySelector = (selector) => selector.includes('label')
    ? label : retryPresent ? retry : null;
  const context = {
    window: {__vibekitsCurrentSessionId: () => 'session-source'},
    HTMLElement: Element,
    document: {
      body,
      getElementById: () => card,
      querySelector: () => new Element(),
      querySelectorAll: () => [new Element()],
    },
    sessionTitleForRow: () => '来源会话',
    findConversationHost: () => new Element(),
    composerAnchor: null,
    continuationRequestInFlight: false,
    contextSessionRow: null,
    continuationProgress: {
      status: '正在创建派生会话…',
      sessionIds: ['session-source'],
      sessionTitles: [],
      isError,
    },
  };
  vm.runInNewContext(renderSource, context);
  for (let i = 0; i < 3; i++) {
    context.window.__vibekitsRenderContinuationProgress();
  }
  context.window.__vibekitsCurrentSessionId = () => 'unrelated-session';
  context.window.__vibekitsRenderContinuationProgress();
  assert.equal(card.style.display, 'none', 'third session must hide scoped state');
  context.window.__vibekitsCurrentSessionId = () => 'session-source';
  context.window.__vibekitsRenderContinuationProgress();
  assert.equal(card.style.display, '', 'returning restores scoped state');
  return {textMutations, retryRemovals, errorVisible: classes.has('is-error')};
}

assert.deepEqual(runRender(currentRender, false), {
  textMutations: 0, retryRemovals: 1, errorVisible: false,
});
assert.deepEqual(runRender(currentRender, true), {
  textMutations: 0, retryRemovals: 0, errorVisible: true,
});

// Negative control: the previous unconditional assignment and error reset
// reproduce the observed childList loop and disappearing retry control.
const oldRender = currentRender
  .replace(
    /const label = card\.querySelector\('\.vibekits-continuation-progress-label'\);[\s\S]*?\n    }\n    card\.classList\.toggle/,
    "card.querySelector('.vibekits-continuation-progress-label').textContent =\n      continuationProgress.status;\n    card.classList.toggle",
  )
  .replace(
    /card\.classList\.toggle\('is-error', continuationProgress\.isError === true\);[\s\S]*?\n    }/,
    "card.classList.remove('is-error');\n    card.querySelector('.vibekits-continuation-retry')?.remove();",
  );
assert.notEqual(oldRender, currentRender);
const oldResult = runRender(oldRender, true);
assert.equal(oldResult.textMutations, 4);
assert.equal(oldResult.retryRemovals, 1);
assert.equal(oldResult.errorVisible, false);
console.log('PASS: repeated progress render is idempotent; error and retry survive');
