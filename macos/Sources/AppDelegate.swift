import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventController: GlobalFinderGestureController!
    private var updateChecker: UpdateChecker!
    private var permissionTimer: Timer?
    private var triggerMenuItem: NSMenuItem!
    private var keyboardStatusItem: NSMenuItem!
    private var repairAccessItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard activateExistingInstanceIfNeeded() == false else { return }
        eventController = GlobalFinderGestureController()
        configureStatusItem()
        eventController.onStatusChange = { [weak self] status in
            DispatchQueue.main.async { self?.updateKeyboardStatus(status) }
        }
        updateChecker = UpdateChecker()
        updateChecker.start()
        requestAccessibilityAndStart()
    }

    private func activateExistingInstanceIfNeeded() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentPID && !$0.isTerminated }) else { return false }
        existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true
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
        keyboardStatusItem = NSMenuItem(title: "Keyboard: checking…", action: nil, keyEquivalent: "")
        keyboardStatusItem.isEnabled = false
        menu.addItem(keyboardStatusItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "How to use OrbitDrop", action: #selector(showHelp), keyEquivalent: "")
        triggerMenuItem = menu.addItem(withTitle: "Record trigger key… (\(TriggerKey.current.label))", action: #selector(changeTriggerKey), keyEquivalent: "")
        menu.addItem(withTitle: "Run keyboard self-test…", action: #selector(runKeyboardSelfTest), keyEquivalent: "")
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        repairAccessItem = menu.addItem(withTitle: "Repair Keyboard Access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
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

        updateKeyboardStatus(.needsAccessibility)

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
        alert.informativeText = "1. Confirm the menu says Keyboard: ready.\n2. Select one or more files on the Desktop or in Finder.\n3. Hold \(eventController.triggerKeyLabel) for a quarter-second to open OrbitDrop.\n4. Keep holding, move the pointer onto an action, then release the key to run it.\n\nA quick press still behaves like the normal key. While renaming or typing in Finder, OrbitDrop pauses its trigger so every character works normally. Modifier keys keep their normal behavior even while used as the trigger. Use Record trigger key to press the exact key you want. All processing stays on this Mac."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it")
        alert.runModal()
    }

    @objc private func changeTriggerKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Record your OrbitDrop trigger key"
        alert.informativeText = "Press the physical key you want to hold in Finder. There is no preset list."
        let recorder = TriggerKeyRecorderView(frame: NSRect(x: 0, y: 0, width: 390, height: 78))
        alert.accessoryView = recorder
        let saveButton = alert.addButton(withTitle: "Save")
        saveButton.isEnabled = false
        alert.addButton(withTitle: "Cancel")
        recorder.onRecord = { _ in saveButton.isEnabled = true }
        DispatchQueue.main.async { alert.window.makeFirstResponder(recorder) }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let selected = recorder.recordedKey else { return }
        eventController.setTriggerKey(selected)
        triggerMenuItem.title = "Record trigger key… (\(selected.label))"
        if let button = statusItem.button {
            button.toolTip = "OrbitDrop — hold \(selected.label) on selected Finder files"
        }
    }

    @objc private func runKeyboardSelfTest() {
        eventController.runInterceptionSelfTest { [weak self] success in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = success ? "Keyboard interception passed" : "Keyboard interception needs attention"
            alert.informativeText = success
                ? "OrbitDrop generated a harmless test keystroke, captured it at the system input layer, and suppressed it before Finder could receive it. Your \(self.eventController.triggerKeyLabel) hold interaction is ready."
                : "OrbitDrop could not capture and suppress its harmless test keystroke. Open Keyboard Access, remove any stale OrbitDrop entry if present, add the copy in Applications, enable it, then reopen OrbitDrop and run this test again."
            alert.alertStyle = success ? .informational : .warning
            alert.addButton(withTitle: success ? "Done" : "Open Keyboard Access")
            alert.addButton(withTitle: "Close")
            if alert.runModal() == .alertFirstButtonReturn, !success { self.openAccessibilitySettings() }
        }
    }

    @objc private func openAccessibilitySettings() {
        let alert = NSAlert()
        alert.messageText = "Allow OrbitDrop to intercept its trigger key"
        alert.informativeText = "In Privacy & Security → Accessibility, enable the OrbitDrop copy located in your Applications folder. If OrbitDrop is already listed but the menu does not say Keyboard: ready, remove that stale entry, add OrbitDrop again, and reopen the app. This access is required to stop Finder’s letter-search behavior; it is not used to upload or record typing."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateKeyboardStatus(_ status: KeyboardInterceptionStatus) {
        switch status {
        case .ready:
            keyboardStatusItem.title = "Keyboard: ready ✓"
            repairAccessItem.isHidden = true
        case .verifying:
            keyboardStatusItem.title = "Keyboard: verifying…"
            repairAccessItem.isHidden = false
        case .needsAccessibility:
            keyboardStatusItem.title = "Keyboard: access required ⚠"
            repairAccessItem.isHidden = false
        case .failed:
            keyboardStatusItem.title = "Keyboard: interception failed ⚠"
            repairAccessItem.isHidden = false
        }
    }

    @objc private func checkForUpdates() {
        updateChecker.check(showCurrent: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
