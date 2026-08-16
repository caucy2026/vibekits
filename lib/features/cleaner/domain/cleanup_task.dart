/// Cooperative cancellation shared by cleanup scan and delete tasks.
class CleanupCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}
