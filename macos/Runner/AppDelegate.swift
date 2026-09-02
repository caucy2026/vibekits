import Cocoa
import FlutterMacOS
import WebKit

@main
class AppDelegate: FlutterAppDelegate {
  private var fileChannel: FlutterMethodChannel?
  private var harnessInputChannel: FlutterMethodChannel?
  private var pendingFiles: [String] = []
  private var dartReady = false
  private var webViewMouseMonitor: Any?
  private weak var capturedWebViewResponder: NSView?
  private var webViewInputEnabled = true

  override func applicationDidFinishLaunching(_ notification: Notification) {
    mainFlutterWindow?.acceptsMouseMovedEvents = true
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
      harnessInputChannel = FlutterMethodChannel(
        name: "vibekits/harness_input",
        binaryMessenger: controller.engine.binaryMessenger
      )
      harnessInputChannel?.setMethodCallHandler { [weak self] call, result in
        guard call.method == "setWebViewInputEnabled",
              let enabled = call.arguments as? Bool else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.webViewInputEnabled = enabled
        if !enabled {
          self?.capturedWebViewResponder = nil
        }
        result(nil)
      }
    }
    installWebViewMouseRouting()
  }

  override func applicationWillTerminate(_ notification: Notification) {
    if let monitor = webViewMouseMonitor {
      NSEvent.removeMonitor(monitor)
      webViewMouseMonitor = nil
    }
    super.applicationWillTerminate(notification)
  }

  /// Flutter 3.41's macOS AppKitView composition can paint WKWebView while
  /// window hit-testing still selects FlutterView. In that state the Dart
  /// pointer router sees the click but WebKit never receives mouse-down/up.
  /// Route only events whose coordinates are inside an embedded WKWebView and
  /// only when normal AppKit hit-testing did not already select WebKit.
  private func installWebViewMouseRouting() {
    let mask: NSEvent.EventTypeMask = [
      .leftMouseDown, .leftMouseUp, .leftMouseDragged,
      .rightMouseDown, .rightMouseUp, .rightMouseDragged,
      .otherMouseDown, .otherMouseUp, .otherMouseDragged,
      .mouseMoved, .scrollWheel,
    ]
    webViewMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) {
      [weak self] event in
      guard let self, let window = event.window,
            window === self.mainFlutterWindow,
            self.webViewInputEnabled,
            let contentView = window.contentView else {
        return event
      }

      let responder: NSView?
      switch event.type {
      case .leftMouseUp, .leftMouseDragged,
           .rightMouseUp, .rightMouseDragged,
           .otherMouseUp, .otherMouseDragged:
        responder = self.capturedWebViewResponder ??
          self.webViewResponder(in: contentView, at: event.locationInWindow)
      default:
        responder = self.webViewResponder(
          in: contentView,
          at: event.locationInWindow
        )
      }
      guard let responder else { return event }

      switch event.type {
      case .leftMouseDown:
        self.capturedWebViewResponder = responder
        window.makeFirstResponder(responder)
        responder.mouseDown(with: event)
      case .leftMouseUp:
        responder.mouseUp(with: event)
        self.capturedWebViewResponder = nil
      case .leftMouseDragged:
        responder.mouseDragged(with: event)
      case .rightMouseDown:
        self.capturedWebViewResponder = responder
        window.makeFirstResponder(responder)
        responder.rightMouseDown(with: event)
      case .rightMouseUp:
        responder.rightMouseUp(with: event)
        self.capturedWebViewResponder = nil
      case .rightMouseDragged:
        responder.rightMouseDragged(with: event)
      case .otherMouseDown:
        self.capturedWebViewResponder = responder
        window.makeFirstResponder(responder)
        responder.otherMouseDown(with: event)
      case .otherMouseUp:
        responder.otherMouseUp(with: event)
        self.capturedWebViewResponder = nil
      case .otherMouseDragged:
        responder.otherMouseDragged(with: event)
      case .mouseMoved:
        responder.mouseMoved(with: event)
      case .scrollWheel:
        responder.scrollWheel(with: event)
      default:
        return event
      }
      return nil
    }
  }

  private func webViewResponder(
    in view: NSView,
    at pointInWindow: NSPoint
  ) -> NSView? {
    guard !view.isHidden, view.alphaValue > 0 else { return nil }
    let localPoint = view.convert(pointInWindow, from: nil)
    guard view.bounds.contains(localPoint) else { return nil }

    for child in view.subviews.reversed() {
      if let responder = webViewResponder(in: child, at: pointInWindow) {
        return responder
      }
    }
    guard let webView = view as? WKWebView else { return nil }
    return webView.hitTest(localPoint) ?? webView
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
