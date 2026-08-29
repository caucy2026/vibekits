import { readFile } from 'node:fs/promises';
import { createSocket } from 'node:dgram';

const GROUP = '239.255.42.99';
const PORT = 47831;
const manifestPath = process.argv[2];
const validateOnly = process.argv.includes('--validate-only');
if (!manifestPath) throw new Error('Usage: node lmcp_reference_peer.mjs <manifest.json> [--validate-only]');

const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
const text = (value, name, max) => {
  if (typeof value !== 'string' || value.length < 1 || value.length > max || /[\x00-\x1f\x7f]/.test(value)) {
    throw new Error(`${name} is invalid`);
  }
  return value;
};
text(manifest.instanceId, 'instanceId', 80);
text(manifest.app?.id, 'app.id', 120);
text(manifest.app?.name, 'app.name', 80);
text(manifest.app?.version, 'app.version', 40);
if (!['ssh-stdio', 'https-streamable-http'].includes(manifest.endpoint?.transport)) throw new Error('endpoint.transport is invalid');
if (!Number.isInteger(manifest.endpoint?.port) || manifest.endpoint.port < 1 || manifest.endpoint.port > 65535) throw new Error('endpoint.port is invalid');
if (manifest.security?.pairingRequired !== true) throw new Error('pairingRequired must be true');
if (!Array.isArray(manifest.security?.authMethods) || manifest.security.authMethods.length === 0) throw new Error('authMethods is required');
if (!Array.isArray(manifest.mcp?.protocolVersions) || manifest.mcp.protocolVersions.length === 0) throw new Error('mcp.protocolVersions is required');

const announcement = () => ({
  protocol: 'lmcp-discovery',
  protocolVersion: '1.0',
  messageType: 'announce',
  ...manifest,
  ttlSeconds: manifest.ttlSeconds ?? 12,
  sentAt: new Date().toISOString(),
});
const payload = () => Buffer.from(JSON.stringify(announcement()), 'utf8');
if (payload().length > 1024) throw new Error('LMCP announcement exceeds 1024 bytes');

if (validateOnly) {
  process.stdout.write(`${JSON.stringify({ ok: true, bytes: payload().length, announcement: announcement() })}\n`);
  process.exit(0);
}

const socket = createSocket({ type: 'udp4', reuseAddr: true });
socket.on('error', (error) => process.stderr.write(`LMCP discovery error: ${error.message}\n`));
const send = () => socket.send(payload(), PORT, GROUP);
socket.bind(0, '0.0.0.0', () => {
  socket.setMulticastTTL(1);
  socket.setMulticastLoopback(true);
  send();
  setInterval(send, 4000).unref();
});
process.on('SIGINT', () => socket.close(() => process.exit(0)));
process.on('SIGTERM', () => socket.close(() => process.exit(0)));
await new Promise(() => {});
