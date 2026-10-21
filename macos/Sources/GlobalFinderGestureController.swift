import AppKit
import ApplicationServices

private let orbitEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<GlobalFinderGestureController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}

enum KeyboardInterceptionStatus: Equatable {
    case needsAccessibility
    case verifying
    case ready
    case failed
}

final class GlobalFinderGestureController {
    private static let selfTestMarker: Int64 = 0x4F52424954445250
    private let panel = RadialPanel()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeFiles: [URL] = []
    private var gestureOrigin: NSPoint?
    private var wheelVisible = false
    private var gestureSequence = 0
    private var isProcessing = false
    private var triggerKey = TriggerKey.current
    private var keyGate = KeyboardInterceptionGate(triggerCode: TriggerKey.current.code)
    private var selfTestGeneration = 0
    private var selfTestSawKeyDown = false
    private var selfTestCompletions: [(Bool) -> Void] = []

    var onStatusChange: ((KeyboardInterceptionStatus) -> Void)?
    private(set) var status: KeyboardInterceptionStatus = .verifying {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }

    var triggerKeyLabel: String { triggerKey.label }

    func setTriggerKey(_ key: TriggerKey) {
        dismiss()
        triggerKey = key
        keyGate.updateTrigger(key.code)
        TriggerKey.save(key)
    }

    func start() {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
            status = .needsAccessibility
            return
        }
        status = .verifying
        let types: [CGEventType] = [.mouseMoved, .keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: orbitEventCallback,
            userInfo: pointer
        ) else {
            status = .failed
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        runInterceptionSelfTest()
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil
        eventTap = nil
        keyGate.cancel()
        status = AXIsProcessTrusted() ? .failed : .needsAccessibility
    }

    func runInterceptionSelfTest(completion: ((Bool) -> Void)? = nil) {
        if let completion { selfTestCompletions.append(completion) }
        guard let eventTap, CGEvent.tapIsEnabled(tap: eventTap) else {
            completeSelfTest(success: false)
            return
        }
        status = .verifying
        selfTestGeneration += 1
        let generation = selfTestGeneration
        selfTestSawKeyDown = false
        for isDown in [true, false] {
            guard let testEvent = CGEvent(keyboardEventSource: nil, virtualKey: 79, keyDown: isDown) else { continue }
            testEvent.setIntegerValueField(.eventSourceUserData, value: Self.selfTestMarker)
            testEvent.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, generation == self.selfTestGeneration, self.status == .verifying else { return }
            self.completeSelfTest(success: false)
        }
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.selfTestMarker {
            if type == .keyDown { selfTestSawKeyDown = true }
            if type == .keyUp, selfTestSawKeyDown { completeSelfTest(success: true) }
            return nil
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            status = .verifying
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                runInterceptionSelfTest()
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            switch keyGate.keyDown(code: keyCode, finderFrontmost: FinderBridge.isFinderFrontmost, processing: isProcessing) {
            case .began:
                beginGesture()
                return nil
            case .repeated:
                return nil
            case .ignored, .ended:
                if wheelVisible, keyCode == 53 {
                    dismiss()
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }

        case .flagsChanged:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard TriggerKey.isModifier(code: keyCode), keyCode == triggerKey.code else {
                return Unmanaged.passUnretained(event)
            }
            switch keyGate.modifierChanged(code: keyCode, finderFrontmost: FinderBridge.isFinderFrontmost, processing: isProcessing) {
            case .began:
                beginGesture()
                return nil
            case .ended:
                endGesture()
                return nil
            case .repeated:
                return nil
            case .ignored:
                return Unmanaged.passUnretained(event)
            }

        case .mouseMoved:
            guard wheelVisible else { return Unmanaged.passUnretained(event) }
            panel.updateHighlight(globalPoint: NSEvent.mouseLocation)
            return Unmanaged.passUnretained(event)

        case .keyUp:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard keyGate.keyUp(code: keyCode) == .ended else { return Unmanaged.passUnretained(event) }
            endGesture()
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func beginGesture() {
        let point = NSEvent.mouseLocation
        gestureOrigin = point
        activeFiles = []
        wheelVisible = false
        panel.hide(animated: false)
        gestureSequence += 1
        let sequence = gestureSequence
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.keyGate.isHeld, self.gestureSequence == sequence, self.gestureOrigin != nil,
                  FinderBridge.isFinderFrontmost else { return }
            let files = FinderBridge.selectedURLs()
            guard self.keyGate.isHeld, self.gestureSequence == sequence, !files.isEmpty else { return }
            self.activeFiles = files
            self.wheelVisible = true
            self.panel.show(at: point, files: files)
        }
    }

    private func endGesture() {
        if wheelVisible {
            perform(panel.action(globalPoint: NSEvent.mouseLocation))
        } else {
            gestureSequence += 1
            gestureOrigin = nil
            activeFiles = []
        }
    }

    private func completeSelfTest(success: Bool) {
        selfTestGeneration += 1
        status = success ? .ready : (AXIsProcessTrusted() ? .failed : .needsAccessibility)
        let completions = selfTestCompletions
        selfTestCompletions.removeAll()
        completions.forEach { $0(success) }
    }

    private func perform(_ action: OrbitAction?) {
        let files = activeFiles
        guard let action else {
            dismiss()
            return
        }
        gestureSequence += 1
        wheelVisible = false
        keyGate.cancel()
        gestureOrigin = nil
        isProcessing = true
        panel.showProcessing(action)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        FileOperations.perform(action: action, sources: files) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let outputs):
                let message = outputs.count == 1 ? outputs[0].lastPathComponent : "Created \(outputs.count) files"
                self.panel.showSuccess(message)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { [weak self] in
                    self?.finishProcessing()
                }
            case .failure(let error):
                self.panel.showFailure()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                    self?.finishProcessing()
                    FileOperations.showError(error)
                }
            }
        }
    }

    private func finishProcessing() {
        isProcessing = false
        activeFiles = []
        panel.hide()
    }

    private func dismiss() {
        gestureSequence += 1
        wheelVisible = false
        keyGate.cancel()
        gestureOrigin = nil
        activeFiles = []
        panel.hide()
    }
}
