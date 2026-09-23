/// Compile-time distribution policy.
///
/// Direct builds (including Uptodown) may expose the KEMI application center.
/// The Mac App Store build excludes it completely: it is never a dormant or
/// remotely enabled feature in the binary submitted to Apple.
abstract final class AppDistribution {
  static const String channel = String.fromEnvironment(
    'VIBEKITS_DISTRIBUTION',
    defaultValue: 'direct',
  );

  static const String macAppStore = 'mac-app-store';
  static const String macAppStoreDisplayVersion = String.fromEnvironment(
    'VIBEKITS_APP_STORE_DISPLAY_VERSION',
    defaultValue: '',
  );
  static const bool includesAppCenter = channel != macAppStore;
  static const bool isMacAppStoreBuild = !includesAppCenter;
  static const int appCenterAutomaticRevealLaunch = 10;
  static const Duration appCenterAutomaticRevealAge = Duration(days: 7);

  static bool appCenterUsageGateReached({
    required int launchCount,
    required int firstLaunchAtEpochMs,
    DateTime? now,
  }) {
    if (launchCount >= appCenterAutomaticRevealLaunch) return true;
    if (firstLaunchAtEpochMs <= 0) return false;
    final DateTime firstLaunch = DateTime.fromMillisecondsSinceEpoch(
      firstLaunchAtEpochMs,
      isUtc: true,
    );
    final DateTime current = (now ?? DateTime.now()).toUtc();
    return !current.isBefore(firstLaunch.add(appCenterAutomaticRevealAge));
  }
}
