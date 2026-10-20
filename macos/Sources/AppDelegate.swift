import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventController: GlobalFinderGestureController!
    private var updateChecker: UpdateChecker!
    private var permissionTimer: Timer?
    private var triggerMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        eventController = GlobalFinderGestureController()
        updateChecker = UpdateChecker()
        updateChecker.start()
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
            button.toolTip = "OrbitDrop — hold your trigger key on selected Finder files"
        }

        let menu = NSMenu()
        let status = NSMenuItem(title: "OrbitDrop is active", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(withTitle: "How to use OrbitDrop", action: #selector(showHelp), keyEquivalent: "")
        triggerMenuItem = menu.addItem(withTitle: "Trigger key: \(TriggerKey.current.label)…", action: #selector(changeTriggerKey), keyEquivalent: "")
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
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
        alert.informativeText = "1. Select one or more files on the Desktop or in Finder.\n2. Hold \(eventController.triggerKeyLabel) for a moment until the wheel appears.\n3. Keep holding, move the pointer onto an action, then release the key to run it.\n\nChoose a different trigger key from the OrbitDrop menu at any time. Press Escape to close the wheel. All processing stays on this Mac."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it")
        alert.runModal()
    }

    @objc private func changeTriggerKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Choose your OrbitDrop trigger key"
        alert.informativeText = "Select a key to hold after choosing files in Finder. Space is the recommended default."
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        picker.addItems(withTitles: TriggerKey.supported.map(\.label))
        if let index = TriggerKey.supported.firstIndex(of: TriggerKey.current) {
            picker.selectItem(at: index)
        }
        alert.accessoryView = picker
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let selected = TriggerKey.supported[picker.indexOfSelectedItem]
        eventController.setTriggerKey(selected)
        triggerMenuItem.title = "Trigger key: \(selected.label)…"
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func checkForUpdates() {
        updateChecker.check(showCurrent: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
