import Cocoa
import FlutterMacOS
import WebKit

@main
class AppDelegate: FlutterAppDelegate {
  private var fileChannel: FlutterMethodChannel?
  private var harnessInputChannel: FlutterMethodChannel?
  private var simulatorHostChannel: FlutterMethodChannel?
  private var storeHostChannel: FlutterMethodChannel?
  private var deviceDebugChannel: FlutterMethodChannel?
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
      simulatorHostChannel = FlutterMethodChannel(
        name: "vibekits/simulator_host",
        binaryMessenger: controller.engine.binaryMessenger
      )
      simulatorHostChannel?.setMethodCallHandler { [weak self] call, result in
        guard call.method == "setRemoteLoginEnabled",
              let enabled = call.arguments as? Bool else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.setRemoteLoginEnabled(enabled, result: result)
      }
      storeHostChannel = FlutterMethodChannel(
        name: "org.rustdesk.rustdesk/host",
        binaryMessenger: controller.engine.binaryMessenger
      )
      storeHostChannel?.setMethodCallHandler { [weak self] call, result in
        guard let self,
              let arguments = call.arguments as? [String: Any],
              let packageName = arguments["packageName"] as? String,
              self.isSafeStorePackageName(packageName) else {
          result(false)
          return
        }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
          withBundleIdentifier: packageName
        ) else {
          result(false)
          return
        }
        switch call.method {
        case "isStoreApplicationInstalled":
          result(true)
        case "openStoreApplication":
          let configuration = NSWorkspace.OpenConfiguration()
          configuration.activates = true
          NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
          ) { _, error in
            result(error == nil)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      deviceDebugChannel = FlutterMethodChannel(
        name: "vibekits/device_debug",
        binaryMessenger: controller.engine.binaryMessenger
      )
      deviceDebugChannel?.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "screenCapturePermissionStatus":
          result(CGPreflightScreenCaptureAccess())
        case "requestScreenCapturePermission":
          result(CGRequestScreenCaptureAccess())
        case "captureScreen":
          self?.captureScreen(result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    installWebViewMouseRouting()
  }

  /// Capture one current-screen frame inside the signed VibeKits process.
  /// This is invoked only by the explicitly authorized simulator MCP tool; it
  /// does not start a desktop session or share a continuous screen stream.
  private func captureScreen(result: @escaping FlutterResult) {
    guard CGPreflightScreenCaptureAccess() else {
      CGRequestScreenCaptureAccess()
      result(FlutterError(
        code: "SCREEN_CAPTURE_PERMISSION_REQUIRED",
        message: "请在系统设置中允许 VibeKits 录制屏幕后重试",
        details: nil
      ))
      return
    }
    guard let image = CGWindowListCreateImage(
      .infinite,
      .optionOnScreenOnly,
      kCGNullWindowID,
      [.bestResolution, .boundsIgnoreFraming]
    ) else {
      result(FlutterError(
        code: "SCREEN_CAPTURE_FAILED",
        message: "无法读取当前屏幕",
        details: nil
      ))
      return
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("vibekits-simulator-screenshots", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      let path = directory.appendingPathComponent(
        "screen-\(Int(Date().timeIntervalSince1970 * 1000)).png"
      )
      let representation = NSBitmapImageRep(cgImage: image)
      guard let png = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "VibeKitsScreenCapture", code: 1)
      }
      try png.write(to: path, options: .atomic)
      result([
        "ok": true,
        "path": path.path,
        "width": image.width,
        "height": image.height,
        "bytes": png.count,
      ])
    } catch {
      result(FlutterError(
        code: "SCREEN_CAPTURE_WRITE_FAILED",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private func isSafeStorePackageName(_ value: String) -> Bool {
    guard !value.isEmpty else { return false }
    return value.range(
      of: "^[A-Za-z0-9._-]+$",
      options: .regularExpression
    ) != nil
  }

  /// Ask macOS to update its built-in SSH launchd service using the system
  /// authorization panel.
  /// The bridge accepts no command text or credentials: Dart can only request
  /// the fixed on/off operation, and the administrator password remains owned
  /// by macOS SecurityAgent.
  private func setRemoteLoginEnabled(
    _ enabled: Bool,
    result: @escaping FlutterResult
  ) {
    let command = enabled
      ? "/bin/launchctl enable system/com.openssh.sshd; /bin/launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || /bin/launchctl kickstart -k system/com.openssh.sshd"
      : "/bin/launchctl bootout system/com.openssh.sshd 2>/dev/null; /bin/launchctl disable system/com.openssh.sshd"
    DispatchQueue.global(qos: .userInitiated).async {
      let process = Process()
      let output = Pipe()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = [
        "-e",
        "do shell script \"\(command)\" with administrator privileges"
      ]
      process.standardOutput = output
      process.standardError = output
      do {
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        DispatchQueue.main.async {
          if process.terminationStatus == 0 {
            result(["ok": true, "enabled": enabled, "message": message])
          } else {
            result(FlutterError(
              code: "REMOTE_LOGIN_AUTHORIZATION_FAILED",
              message: message.isEmpty ? "macOS administrator authorization was cancelled" : message,
              details: nil
            ))
          }
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "REMOTE_LOGIN_LAUNCH_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
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
