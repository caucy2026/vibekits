import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { continuationContext, markContinuationConsumed, apply } from '../native/harness/vibekits-continuation-context.mjs';
const home = mkdtempSync(join(tmpdir(), 'vibekits-handoff-'));
const child = 'session-11111111-1111-1111-1111-111111111111';
try {
  mkdirSync(join(home, 'continuations'));
  mkdirSync(join(home, 'storages'));
  const records = [{continuationSessionId:child, sourceSessionId:'source', workspace:'workspace', summary:'目标：继续实现验收测试'}];
  writeFileSync(join(home, 'continuations/continuations.json'),JSON.stringify({records}));
  writeFileSync(join(home, 'storages/workspace.json'),JSON.stringify({tables:{workspaces:{workspace:{sessionIds:[child]}}}}));
  assert.match(continuationContext(home,child),/继续实现验收测试/);
  records[0].workspace = '/workspace/';
  writeFileSync(join(home, 'continuations/continuations.json'),JSON.stringify({records}));
  assert.match(continuationContext(home,child),/继续实现验收测试/, 'real app persists normalized workspace keys');
  assert.equal(markContinuationConsumed(home, child), true);
  assert.equal(continuationContext(home, child), '', 'handoff is injected only until the first successful assistant message');
  rmSync(join(home, 'continuations', 'consumed'), {recursive:true, force:true});
  assert.equal(continuationContext(home,'session-22222222-2222-2222-2222-222222222222'),'');
  let provider;
  let sessionEvent;
  apply({
    systemPrompt:{context(value){provider=value;}},
    on(name, callback){ if(name === 'session/event') sessionEvent=callback; },
  });
  const previous = process.env.DSH_HOME;
  process.env.DSH_HOME=home;
  assert.match(provider.text({agent:{id:child}}),/目标：/);
  sessionEvent({id:child},{type:'assistant/message'});
  assert.equal(provider.text({agent:{id:child}}), '', 'a successful first assistant reply consumes the handoff');
  rmSync(join(home, 'continuations', 'consumed'), {recursive:true, force:true});
  const { Context } = await import('../native/harness/macos/runtime/node_modules/@deepseek-ai/cordis/lib/index.js');
  const { default: SystemPrompt } = await import('../native/harness/macos/runtime/node_modules/@deepseek-ai/dsh-system-prompt/lib/index.js');
  const ctx = new Context();
  await ctx.plugin(SystemPrompt, {});
  apply(ctx);
  const assembled = await ctx.systemPrompt.assemble({ agent: { id: child } });
  assert.ok(assembled.contexts.some((c) => c.name === 'vibekits:continuation-handoff' && c.text.includes('继续实现验收测试')));
  assert.ok(assembled.sections.some((s) => s.name === 'harness:identity'));
  console.log('PASS: actual official SystemPrompt assembly includes handoff and retains official identity');
  assert.equal(provider.text({}), '');
  if(previous === undefined) delete process.env.DSH_HOME; else process.env.DSH_HOME=previous;
  writeFileSync(join(home, 'storages/workspace.json'),JSON.stringify({tables:{workspaces:{workspace:{sessionIds:[]}}}}));
  assert.equal(continuationContext(home,child),'', 'removed or moved sessions must not receive stale handoffs');
  console.log('PASS: per-session summary, source linkage, unrelated-session isolation and deleted membership');
} finally { rmSync(home,{recursive:true,force:true}); }
