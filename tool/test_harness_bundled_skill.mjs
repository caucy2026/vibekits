import { randomUUID } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const runtime = process.argv[2];
if (!runtime) {
  throw new Error('usage: node test_harness_bundled_skill.mjs <runtime directory>');
}

const runtimeRoot = resolve(runtime);
process.env.DSH_BUNDLED_SKILL_DIR = join(runtimeRoot, 'builtin-skills');
const moduleUrl = pathToFileURL(
  join(
    runtimeRoot,
    'node_modules',
    '@deepseek-ai',
    'dsh-skill-filesystem',
    'lib',
    'index.js',
  ),
);
const { FileSystemSkillProvider } = await import(moduleUrl.href);
const emptyHome = join(tmpdir(), `vibekits-clean-skill-probe-${randomUUID()}`);
const warnings = [];
const provider = new FileSystemSkillProvider(
  {
    get: () => undefined,
    logger: { warn: (message) => warnings.push(message) },
  },
  { invalidate() {}, signal: new AbortController().signal },
  { watch: false, dshHome: emptyHome, agentsHome: emptyHome },
);

try {
  const result = await provider.list({});
  const candidates = Array.isArray(result) ? result : result.candidates;
  const candidate = candidates.find(
    (item) => item.name === 'vibekits-remote-simulator',
  );
  if (!candidate || candidate.source !== 'bundled') {
    throw new Error('clean Harness profile did not discover bundled remote simulator');
  }
  const skill = await provider.get(candidate, {});
  if (
    !skill?.invocation.modelInvocable ||
    !skill.description.includes('帮我调试远程') ||
    !skill.content.includes('vibekits.simulator.connect') ||
    !skill.content.includes('vibekits.simulator.disconnect')
  ) {
    throw new Error('bundled remote simulator is not automatically invocable');
  }
  if (warnings.length > 0) {
    throw new Error(`Harness skill discovery warning: ${warnings.join('; ')}`);
  }
  process.stdout.write(
    `Verified clean Harness skill catalog: ${skill.name} (source=${candidate.source}, modelInvocable=true)\n`,
  );
} finally {
  await provider.dispose();
}
