import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, CaptureServiceDelegate {
  private var statusItem: NSStatusItem?
  private let store = FrameStore()
  private var capture: CaptureService!
  private var server: HttpServer!
  private let port: UInt16

  override init() {
    if let raw = ProcessInfo.processInfo.environment["OBS_BRIDGE_PORT"], let value = UInt16(raw) {
      port = value
    } else {
      port = BridgeVersion.defaultPort
    }
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    capture = CaptureService(store: store)
    capture.delegate = self
    server = HttpServer(store: store, port: port)

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem?.button {
      button.title = "OBS↕"
      button.toolTip = "\(BridgeVersion.appName) v\(BridgeVersion.version)"
    }
    rebuildMenu(status: "Starting…")

    do {
      try server.start()
      rebuildMenu(status: "Listening on 127.0.0.1:\(port)")
    } catch {
      rebuildMenu(status: "HTTP failed: \(error.localizedDescription)")
    }
    capture.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    capture.stop()
    server.stop()
  }

  func captureServiceDidUpdateStatus(_ text: String) {
    DispatchQueue.main.async {
      self.rebuildMenu(status: text)
    }
  }

  private func rebuildMenu(status: String) {
    let menu = NSMenu()
    menu.addItem(withTitle: "\(BridgeVersion.appName) v\(BridgeVersion.version)", action: nil, keyEquivalent: "")
    menu.addItem(withTitle: status, action: nil, keyEquivalent: "")
    let snap = store.snapshot()
    if snap.width > 0 && snap.height > 0 {
      menu.addItem(withTitle: "Frame \(snap.width)×\(snap.height)", action: nil, keyEquivalent: "")
    }
    menu.addItem(NSMenuItem.separator())
    menu.addItem(withTitle: "Health http://127.0.0.1:\(port)/health", action: #selector(openHealth), keyEquivalent: "")
    menu.addItem(withTitle: "Restart capture", action: #selector(restartCapture), keyEquivalent: "r")
    menu.addItem(NSMenuItem.separator())
    menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
    for item in menu.items {
      item.target = self
      if item.action == nil {
        item.isEnabled = false
      }
    }
    statusItem?.menu = menu
    statusItem?.button?.toolTip = "\(BridgeVersion.appName) v\(BridgeVersion.version)\n\(status)"
  }

  @objc private func openHealth() {
    if let url = URL(string: "http://127.0.0.1:\(port)/health") {
      NSWorkspace.shared.open(url)
    }
  }

  @objc private func restartCapture() {
    capture.start()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}
