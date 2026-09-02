// Keep every bundled Harness Node process tied to the VibeKits App lifetime.
//
// NODE_OPTIONS imports this module in the official DSH process. Child Node
// processes inherit the same environment, so plugin/MCP workers cannot remain
// behind if the desktop process exits before Flutter disposes its widgets.
const parentPid = Number.parseInt(
  process.env.VIBEKITS_PARENT_PID ?? '',
  10,
);

if (Number.isSafeInteger(parentPid) && parentPid > 1) {
  const parentIsAlive = () => {
    try {
      process.kill(parentPid, 0);
      return true;
    } catch (error) {
      // EPERM means the process exists but cannot be signalled. Only ESRCH is
      // proof that the owning VibeKits process has disappeared.
      return error?.code !== 'ESRCH';
    }
  };

  if (!parentIsAlive()) process.exit(0);

  const timer = setInterval(() => {
    if (!parentIsAlive()) process.exit(0);
  }, 750);
  timer.unref();
}
