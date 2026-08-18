const endpoint = process.env.VIBEKITS_TOOL_BRIDGE_URL;
const token = process.env.VIBEKITS_TOOL_BRIDGE_TOKEN;
const workspace = process.cwd();

export const name = 'vibekits-native-approval';
export const inject = ['approval'];

export function apply(ctx) {
  ctx.on('approval/request', async (request, next) => {
    if (!endpoint || !token) return next();
    try {
      const response = await fetch(`${endpoint}/native-approval`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          toolName: request.toolName,
          callId: request.callId,
          reason: request.reason,
          workspace,
        }),
        signal: request.signal,
      });
      if (!response.ok) return 'unavailable';
      const result = await response.json();
      return result.allowed === true ? 'allowed-once' : 'rejected';
    } catch (_) {
      return request.signal?.aborted === true ? 'cancelled' : 'unavailable';
    }
  });
}
