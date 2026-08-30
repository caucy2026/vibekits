import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var fileChannel: FlutterMethodChannel?
  private var pendingFiles: [String] = []
  private var dartReady = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController
        as? FlutterViewController {
      fileChannel = FlutterMethodChannel(
        name: "vibekits/file_drop",
        binaryMessenger: controller.engine.binaryMessenger
      )
      fileChannel?.setMethodCallHandler { [weak self] call, result in
        if call.method == "ready" {
          self?.dartReady = true
          self?.flushPendingFiles()
        }
        result(nil)
      }
    }
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    enqueueFiles(urls.filter(\.isFileURL).map(\.path))
    application.activate(ignoringOtherApps: true)
  }

  private func enqueueFiles(_ filenames: [String]) {
    for path in filenames where !path.isEmpty && !pendingFiles.contains(path) {
      pendingFiles.append(path)
    }
    flushPendingFiles()
  }

  private func flushPendingFiles() {
    guard dartReady, let channel = fileChannel, !pendingFiles.isEmpty else { return }
    let batch = pendingFiles
    pendingFiles.removeAll()
    channel.invokeMethod("filesDropped", arguments: batch)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
