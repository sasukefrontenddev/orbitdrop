import AppKit
import ApplicationServices

private let orbitEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<GlobalFinderGestureController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}

final class GlobalFinderGestureController {
    private let panel = RadialPanel()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeFiles: [URL] = []
    private var gestureOrigin: NSPoint?
    private var wheelVisible = false
    private var gestureSequence = 0
    private var isProcessing = false

    func start() {
        guard eventTap == nil else { return }
        let types: [CGEventType] = [.rightMouseDown, .rightMouseDragged, .rightMouseUp, .leftMouseDown, .keyDown]
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
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        runLoopSource = nil
        eventTap = nil
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .rightMouseDown:
            guard !isProcessing, FinderBridge.isFinderFrontmost else { return Unmanaged.passUnretained(event) }
            let point = NSEvent.mouseLocation
            gestureOrigin = point
            activeFiles = []
            wheelVisible = false
            panel.hide(animated: false)
            gestureSequence += 1
            let sequence = gestureSequence
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                guard let self, self.gestureSequence == sequence, self.gestureOrigin != nil,
                      FinderBridge.isFinderFrontmost else { return }
                let files = FinderBridge.selectedURLs()
                guard !files.isEmpty else { return }
                self.activeFiles = files
                self.wheelVisible = true
                self.panel.show(at: point, files: files)
            }
            return Unmanaged.passUnretained(event)

        case .rightMouseDragged:
            guard wheelVisible else { return Unmanaged.passUnretained(event) }
            panel.updateHighlight(globalPoint: NSEvent.mouseLocation)
            return nil

        case .rightMouseUp:
            guard wheelVisible else {
                gestureSequence += 1
                gestureOrigin = nil
                return Unmanaged.passUnretained(event)
            }
            let point = NSEvent.mouseLocation
            let movement = gestureOrigin.map { hypot(point.x - $0.x, point.y - $0.y) } ?? 0
            if movement < 22 {
                gestureOrigin = nil
                panel.updateHighlight(globalPoint: NSPoint(x: -10_000, y: -10_000))
                return nil
            }
            perform(panel.action(globalPoint: point))
            return nil

        case .leftMouseDown:
            guard wheelVisible else { return Unmanaged.passUnretained(event) }
            perform(panel.action(globalPoint: NSEvent.mouseLocation))
            return nil

        case .keyDown:
            guard wheelVisible, event.getIntegerValueField(.keyboardEventKeycode) == 53 else {
                return Unmanaged.passUnretained(event)
            }
            dismiss()
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func perform(_ action: OrbitAction?) {
        let files = activeFiles
        guard let action else {
            dismiss()
            return
        }
        gestureSequence += 1
        wheelVisible = false
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
        gestureOrigin = nil
        activeFiles = []
        panel.hide()
    }
}
