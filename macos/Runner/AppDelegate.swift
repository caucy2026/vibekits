import Cocoa
import ApplicationServices
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
  private var harnessFunctionKeyMonitor: Any?
  private var harnessShortcutsEnabled = false
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
        guard let enabled = call.arguments as? Bool else {
          result(FlutterMethodNotImplemented)
          return
        }
        switch call.method {
        case "setWebViewInputEnabled":
          self?.webViewInputEnabled = enabled
          if !enabled {
            self?.capturedWebViewResponder = nil
          }
          result(nil)
        case "setHarnessShortcutsEnabled":
          self?.harnessShortcutsEnabled = enabled
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
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
        let applicationURL = self.storeApplicationURL(packageName)
        switch call.method {
        case "getStoreApplicationVersion":
          guard let applicationURL else {
            result(["installed": false])
            return
          }
          guard let bundle = Bundle(url: applicationURL),
                bundle.bundleIdentifier == packageName else {
            result(["installed": true])
            return
          }
          let rawCode = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
          let code = rawCode.flatMap { Int($0) }
          result(["installed": true, "versionCode": (code ?? 0) > 0 ? code! : 0])
        case "isStoreApplicationInstalled":
          result(applicationURL != nil)
        case "openStoreApplication":
          guard let applicationURL else {
            result(false)
            return
          }
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
        case "inspectApplicationUI":
          self?.inspectApplicationUI(call.arguments, result: result)
        case "performApplicationUIAction":
          self?.performApplicationUIAction(call.arguments, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    installWebViewMouseRouting()
    installHarnessFunctionKeyMonitor()
  }

  private func storeApplicationURL(_ packageName: String) -> URL? {
    if let indexed = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: packageName
    ), Bundle(url: indexed)?.bundleIdentifier == packageName {
      return indexed
    }
    let folders = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                   FileManager.default.homeDirectoryForCurrentUser
                     .appendingPathComponent("Applications", isDirectory: true)]
    for folder in folders {
      guard let entries = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ) else { continue }
      for entry in entries where entry.pathExtension.lowercased() == "app" {
        if Bundle(url: entry)?.bundleIdentifier == packageName {
          return entry
        }
      }
    }
    return nil
  }

  private func accessibilityAuthorized(prompt: Bool) -> Bool {
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
    ] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  private func targetApplication(
    _ arguments: [String: Any]
  ) throws -> NSRunningApplication {
    let bundleId = (arguments["bundleId"] as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let appName = (arguments["appName"] as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let matches: [NSRunningApplication]
    if !bundleId.isEmpty {
      matches = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleId
      )
    } else {
      matches = NSWorkspace.shared.runningApplications.filter {
        ($0.localizedName ?? "").caseInsensitiveCompare(appName) == .orderedSame
      }
    }
    guard matches.count == 1, let app = matches.first else {
      throw NSError(
        domain: "VibeKitsDeviceUI",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey:
          matches.isEmpty ? "目标 App 未运行" : "目标 App 不唯一，请使用精确 Bundle ID"]
      )
    }
    return app
  }

  private func axAttribute(
    _ element: AXUIElement,
    _ attribute: String
  ) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
      element,
      attribute as CFString,
      &value
    ) == .success else { return nil }
    return value
  }

  private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    guard let value = axAttribute(element, attribute) else { return nil }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
  }

  private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
    (axAttribute(element, attribute) as? NSNumber)?.boolValue
  }

  private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    axAttribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
  }

  private func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let positionRef = axAttribute(element, kAXPositionAttribute as String),
          let sizeRef = axAttribute(element, kAXSizeAttribute as String),
          CFGetTypeID(positionRef) == AXValueGetTypeID(),
          CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &point),
          AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
  }

  private func axSummary(
    _ element: AXUIElement,
    index: Int,
    depth: Int,
    parent: Int?
  ) -> [String: Any] {
    let role = axString(element, kAXRoleAttribute as String) ?? ""
    var item: [String: Any] = [
      "index": index,
      "depth": depth,
      "role": role,
    ]
    if let parent { item["parent"] = parent }
    let scalarAttributes: [(String, String)] = [
      ("subrole", kAXSubroleAttribute as String),
      ("title", kAXTitleAttribute as String),
      ("description", kAXDescriptionAttribute as String),
      ("identifier", kAXIdentifierAttribute as String),
    ]
    for (name, attribute) in scalarAttributes {
      if let value = axString(element, attribute), !value.isEmpty {
        item[name] = String(value.prefix(512))
      }
    }
    if role != "AXSecureTextField",
       let value = axString(element, kAXValueAttribute as String),
       !value.isEmpty {
      item["value"] = String(value.prefix(512))
    }
    if let enabled = axBool(element, kAXEnabledAttribute as String) {
      item["enabled"] = enabled
    }
    if let focused = axBool(element, kAXFocusedAttribute as String) {
      item["focused"] = focused
    }
    if let frame = axFrame(element) {
      item["frame"] = [
        "x": frame.origin.x,
        "y": frame.origin.y,
        "width": frame.size.width,
        "height": frame.size.height,
      ]
    }
    var actions: CFArray?
    if AXUIElementCopyActionNames(element, &actions) == .success,
       let names = actions as? [String], !names.isEmpty {
      item["actions"] = names
    }
    return item
  }

  private func collectAXTree(
    root: AXUIElement,
    maxDepth: Int,
    maxNodes: Int
  ) -> (nodes: [[String: Any]], elements: [AXUIElement], truncated: Bool) {
    var nodes: [[String: Any]] = []
    var elements: [AXUIElement] = []
    var truncated = false
    func walk(_ element: AXUIElement, depth: Int, parent: Int?) {
      guard nodes.count < maxNodes else { truncated = true; return }
      let index = nodes.count
      nodes.append(axSummary(element, index: index, depth: depth, parent: parent))
      elements.append(element)
      guard depth < maxDepth else {
        if !axChildren(element).isEmpty { truncated = true }
        return
      }
      for child in axChildren(element) {
        guard nodes.count < maxNodes else { truncated = true; break }
        walk(child, depth: depth + 1, parent: index)
      }
    }
    walk(root, depth: 0, parent: nil)
    return (nodes, elements, truncated)
  }

  private func inspectApplicationUI(
    _ rawArguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard let arguments = rawArguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "缺少目标 App", details: nil))
      return
    }
    let prompt = arguments["promptPermission"] as? Bool ?? false
    guard accessibilityAuthorized(prompt: prompt) else {
      result([
        "ok": false,
        "authorized": false,
        "requiresUserApproval": true,
        "permission": "macOS Accessibility",
        "message": "请在系统设置的隐私与安全性 > 辅助功能中允许 VibeKits",
      ])
      return
    }
    do {
      let app = try targetApplication(arguments)
      let root = AXUIElementCreateApplication(app.processIdentifier)
      let maxDepth = min(max(arguments["maxDepth"] as? Int ?? 8, 1), 12)
      let maxNodes = min(max(arguments["maxNodes"] as? Int ?? 400, 1), 1000)
      let tree = collectAXTree(root: root, maxDepth: maxDepth, maxNodes: maxNodes)
      result([
        "ok": true,
        "authorized": true,
        "bundleId": app.bundleIdentifier ?? "",
        "appName": app.localizedName ?? "",
        "pid": app.processIdentifier,
        "nodes": tree.nodes,
        "nodeCount": tree.nodes.count,
        "truncated": tree.truncated,
      ])
    } catch {
      result(FlutterError(code: "UI_INSPECT_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  private func performApplicationUIAction(
    _ rawArguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard accessibilityAuthorized(prompt: false) else {
      result(FlutterError(
        code: "ACCESSIBILITY_PERMISSION_REQUIRED",
        message: "VibeKits 尚未获得 macOS 辅助功能权限",
        details: ["requiresUserApproval": true]
      ))
      return
    }
    guard let arguments = rawArguments as? [String: Any],
          let action = arguments["action"] as? String else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "缺少控件动作", details: nil))
      return
    }
    do {
      let app = try targetApplication(arguments)
      let root = AXUIElementCreateApplication(app.processIdentifier)
      _ = app.activate(options: [.activateIgnoringOtherApps])
      if action == "activate" {
        result(["ok": true, "action": action, "pid": app.processIdentifier])
        return
      }
      if action == "typeText" {
        let text = arguments["value"] as? String ?? ""
        guard text.count <= 4096,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
          throw NSError(domain: "VibeKitsDeviceUI", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "无法创建键盘事件"])
        }
        let units = Array(text.utf16)
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        result(["ok": true, "action": action, "characters": text.count])
        return
      }
      if action == "key" {
        let key = arguments["key"] as? String ?? ""
        let codes: [String: CGKeyCode] = [
          "enter": 36, "escape": 53, "tab": 48, "backspace": 51,
          "delete": 117, "left": 123, "right": 124, "down": 125, "up": 126,
        ]
        guard let code = codes[key],
              let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
          throw NSError(domain: "VibeKitsDeviceUI", code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "不支持的按键"])
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        result(["ok": true, "action": action, "key": key])
        return
      }
      if action == "click" {
        guard let x = arguments["x"] as? Double,
              let y = arguments["y"] as? Double else {
          throw NSError(domain: "VibeKitsDeviceUI", code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "坐标不完整"])
        }
        let tree = collectAXTree(root: root, maxDepth: 2, maxNodes: 40)
        let point = CGPoint(x: x, y: y)
        let appFrames = tree.elements.compactMap { element -> CGRect? in
          guard axString(element, kAXRoleAttribute as String) == (kAXWindowRole as String)
          else { return nil }
          return axFrame(element)
        }
        guard appFrames.contains(where: { $0.contains(point) }) else {
          throw NSError(domain: "VibeKitsDeviceUI", code: 6,
                        userInfo: [NSLocalizedDescriptionKey: "坐标不在目标 App 窗口内"])
        }
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        result(["ok": true, "action": action, "x": x, "y": y, "boundedToTargetWindow": true])
        return
      }

      let identifier = arguments["identifier"] as? String ?? ""
      let title = arguments["title"] as? String ?? ""
      let role = arguments["role"] as? String ?? ""
      let tree = collectAXTree(root: root, maxDepth: 12, maxNodes: 1000)
      let matches = tree.elements.enumerated().filter { index, element in
        let node = tree.nodes[index]
        if !identifier.isEmpty && (node["identifier"] as? String ?? "") != identifier { return false }
        if !title.isEmpty && (node["title"] as? String ?? "").caseInsensitiveCompare(title) != .orderedSame { return false }
        if !role.isEmpty && (node["role"] as? String ?? "") != role { return false }
        return true
      }
      guard matches.count == 1, let match = matches.first else {
        throw NSError(
          domain: "VibeKitsDeviceUI",
          code: 7,
          userInfo: [NSLocalizedDescriptionKey:
            matches.isEmpty ? "未找到匹配控件" : "匹配到多个控件，请增加 identifier/title/role 限定"]
        )
      }
      let error: AXError
      if action == "press" {
        error = AXUIElementPerformAction(match.element, kAXPressAction as CFString)
      } else if action == "setValue" {
        error = AXUIElementSetAttributeValue(
          match.element,
          kAXValueAttribute as CFString,
          (arguments["value"] as? String ?? "") as CFTypeRef
        )
      } else {
        throw NSError(domain: "VibeKitsDeviceUI", code: 8,
                      userInfo: [NSLocalizedDescriptionKey: "不支持的控件动作"])
      }
      guard error == .success else {
        throw NSError(domain: "VibeKitsDeviceUI", code: Int(error.rawValue),
                      userInfo: [NSLocalizedDescriptionKey: "系统控件操作失败：\(error.rawValue)"])
      }
      result([
        "ok": true,
        "action": action,
        "matched": tree.nodes[match.offset],
        "pid": app.processIdentifier,
      ])
    } catch {
      result(FlutterError(code: "UI_ACTION_FAILED", message: error.localizedDescription, details: nil))
    }
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
    if let monitor = harnessFunctionKeyMonitor {
      NSEvent.removeMonitor(monitor)
      harnessFunctionKeyMonitor = nil
    }
    super.applicationWillTerminate(notification)
  }

  private func installHarnessFunctionKeyMonitor() {
    let positions: [UInt16: Int] = [
      122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6,
      98: 7, 100: 8, 101: 9, 109: 10, 103: 11, 111: 12,
    ]
    harnessFunctionKeyMonitor = NSEvent.addLocalMonitorForEvents(
      matching: .keyDown
    ) { [weak self] event in
      guard let self,
            self.harnessShortcutsEnabled,
            event.window === self.mainFlutterWindow,
            event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
            let position = positions[event.keyCode] else {
        return event
      }
      self.harnessInputChannel?.invokeMethod(
        "sessionFunctionKey",
        arguments: position
      )
      return nil
    }
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
        responder.mouseDown(with: event)
        self.restoreWebViewTextResponder(responder, in: window)
      case .leftMouseUp:
        responder.mouseUp(with: event)
        self.capturedWebViewResponder = nil
      case .leftMouseDragged:
        responder.mouseDragged(with: event)
      case .rightMouseDown:
        self.capturedWebViewResponder = responder
        responder.rightMouseDown(with: event)
        self.restoreWebViewTextResponder(responder, in: window)
      case .rightMouseUp:
        responder.rightMouseUp(with: event)
        self.capturedWebViewResponder = nil
      case .rightMouseDragged:
        responder.rightMouseDragged(with: event)
      case .otherMouseDown:
        self.capturedWebViewResponder = responder
        responder.otherMouseDown(with: event)
        self.restoreWebViewTextResponder(responder, in: window)
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

  /// WebKit may choose its internal text client while handling mouseDown.
  /// Keep that choice: forcing the outer WKWebView to be first responder before
  /// the click leaves macOS IME without the editor caret rectangle, so marked
  /// Chinese text and its candidate window can appear at the window origin.
  private func restoreWebViewTextResponder(_ hitView: NSView, in window: NSWindow) {
    var ancestor: NSView? = hitView
    while ancestor != nil && !(ancestor is WKWebView) {
      ancestor = ancestor?.superview
    }
    guard let webView = ancestor else { return }
    if let current = window.firstResponder as? NSView,
       current is NSTextInputClient,
       current.isDescendant(of: webView) { return }
    if let client = webViewTextClient(in: webView) {
      window.makeFirstResponder(client)
    } else {
      window.makeFirstResponder(hitView)
    }
  }

  private func webViewTextClient(in view: NSView) -> NSView? {
    for child in view.subviews.reversed() {
      if let client = webViewTextClient(in: child) { return client }
    }
    return view is NSTextInputClient ? view : nil
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
