import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventController: GlobalFinderGestureController!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        eventController = GlobalFinderGestureController()
        requestAccessibilityAndStart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventController?.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.hexagongrid.circle.fill", accessibilityDescription: "OrbitDrop")
                ?? NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "OrbitDrop")
            button.toolTip = "OrbitDrop — right-click selected Finder files"
        }

        let menu = NSMenu()
        let status = NSMenuItem(title: "OrbitDrop is active", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(withTitle: "How to use OrbitDrop", action: #selector(showHelp), keyEquivalent: "")
        menu.addItem(withTitle: "Enable Accessibility Access", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OrbitDrop", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func requestAccessibilityAndStart() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        if trusted {
            eventController.start()
            return
        }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.permissionTimer = nil
            self?.eventController.start()
        }
    }

    @objc private func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Use OrbitDrop directly in Finder"
        alert.informativeText = "1. Select a file on the Desktop or in Finder.\n2. Hold the right mouse button until the wheel appears.\n3. Glide to an action while still holding, then release to run it.\n\nYou can also right-click and release, move over an action, and left-click it. Press Escape to close the wheel. All processing stays on this Mac."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it")
        alert.runModal()
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
