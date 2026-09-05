import { access } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const runtime = resolve(process.argv[2] ?? 'native/harness/windows/runtime');
const agentsHome = resolve(process.argv[3] ?? join(process.env.USERPROFILE ?? '', '.codex'));
const expectedName = process.argv[4] ?? 'vibekits-remote-node';
const moduleUrl = pathToFileURL(
  join(
    runtime,
    'node_modules',
    '@deepseek-ai',
    'dsh-skill-filesystem',
    'lib',
    'index.js',
  ),
);
const { FileSystemSkillProvider } = await import(moduleUrl.href);
const lifecycle = new AbortController();
const warnings = [];
const provider = new FileSystemSkillProvider(
  {
    get: () => undefined,
    logger: { warn: (message) => warnings.push(String(message)) },
  },
  { invalidate: () => {}, signal: lifecycle.signal },
  { agentsHome, includeDefaultRoots: true, watch: false },
);

try {
  const observation = await provider.list({ cwd: process.cwd() });
  const candidates = Array.isArray(observation)
    ? observation
    : observation.candidates;
  const candidate = candidates.find((item) => item.name === expectedName);
  if (candidate === undefined) {
    throw new Error(
      `Harness did not discover skill ${JSON.stringify(expectedName)} under ${agentsHome}`,
    );
  }
  const skill = await provider.get(candidate, {});
  if (skill === undefined || skill.name !== expectedName) {
    throw new Error(`Harness could not load skill ${JSON.stringify(expectedName)}`);
  }
  if (!skill.content.includes('VibeKits Cross-Platform Remote Nodes')) {
    throw new Error('Harness loaded unexpected skill content');
  }
  if (skill.resourceBase?.kind !== 'directory') {
    throw new Error('Harness did not expose a directory resource base');
  }
  await access(join(skill.resourceBase.path, 'references', 'common-contract.md'));
  console.log(
    JSON.stringify({
      ok: true,
      name: skill.name,
      source: skill.source,
      modelInvocable: skill.invocation.modelInvocable,
      userInvocable: skill.invocation.userInvocable,
      resourceBase: skill.resourceBase.path,
      warnings,
    }),
  );
} finally {
  lifecycle.abort();
  await provider.dispose();
}
