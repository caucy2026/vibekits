import 'dart:math' as math;

/// Bounded recovery policy for the local Harness Web process.
///
/// Startup retries and post-start crashes use the same small, deterministic
/// backoff budget. A stable session resets the budget so a transient failure
/// hours later can still heal itself, while a crash loop always stops and
/// remains visible to the user.
class HarnessStartupRecovery {
  HarnessStartupRecovery({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 800),
  }) : assert(maxAttempts > 0);

  final int maxAttempts;
  final Duration baseDelay;
  int _attempts = 0;

  int get attempts => _attempts;

  Duration? nextDelay() {
    if (_attempts >= maxAttempts) return null;
    final int multiplier = math.pow(2, _attempts).toInt();
    _attempts += 1;
    return Duration(milliseconds: baseDelay.inMilliseconds * multiplier);
  }

  void markStable() => _attempts = 0;
}
