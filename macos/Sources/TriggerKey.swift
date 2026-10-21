import ApplicationServices
import AppKit
import Foundation

struct TriggerKey: Equatable {
    let code: CGKeyCode
    let label: String

    private static let defaultsKey = "OrbitDropTriggerKeyCode"
    private static let defaultsLabelKey = "OrbitDropTriggerKeyLabel"

    static let defaultKey = TriggerKey(code: 49, label: "Space")

    static var current: TriggerKey {
        guard UserDefaults.standard.object(forKey: defaultsKey) != nil else { return defaultKey }
        let code = CGKeyCode(UserDefaults.standard.integer(forKey: defaultsKey))
        let label = UserDefaults.standard.string(forKey: defaultsLabelKey) ?? label(for: code, characters: nil)
        return TriggerKey(code: code, label: label)
    }

    static func save(_ key: TriggerKey) {
        UserDefaults.standard.set(Int(key.code), forKey: defaultsKey)
        UserDefaults.standard.set(key.label, forKey: defaultsLabelKey)
    }

    static func from(event: NSEvent) -> TriggerKey {
        TriggerKey(code: CGKeyCode(event.keyCode), label: label(for: CGKeyCode(event.keyCode), characters: event.charactersIgnoringModifiers))
    }

    static func isModifier(code: CGKeyCode) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(code)
    }

    static func label(for code: CGKeyCode, characters: String?) -> String {
        let named: [CGKeyCode: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y",
            17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
            45: "N", 46: "M",
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
            54: "Right Command", 55: "Command", 56: "Shift", 57: "Caps Lock",
            58: "Option", 59: "Control", 60: "Right Shift", 61: "Right Option",
            62: "Right Control", 63: "Fn", 71: "Clear", 76: "Enter",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
            103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
            111: "F12", 113: "F15", 115: "Home", 116: "Page Up", 117: "Forward Delete",
            118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1",
            123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow"
        ]
        if let name = named[code] { return name }
        let cleaned = characters?.trimmingCharacters(in: .controlCharacters) ?? ""
        return cleaned.isEmpty ? "Key \(code)" : cleaned.uppercased()
    }
}

enum KeyboardInterceptionDecision: Equatable {
    case ignored
    case began
    case repeated
    case ended
}

struct KeyboardInterceptionGate {
    private(set) var triggerCode: CGKeyCode
    private(set) var isHeld = false

    mutating func updateTrigger(_ code: CGKeyCode) {
        triggerCode = code
        isHeld = false
    }

    mutating func cancel() {
        isHeld = false
    }

    mutating func keyDown(code: CGKeyCode, finderFrontmost: Bool, processing: Bool) -> KeyboardInterceptionDecision {
        guard code == triggerCode, finderFrontmost, !processing else { return .ignored }
        if isHeld { return .repeated }
        isHeld = true
        return .began
    }

    mutating func keyUp(code: CGKeyCode) -> KeyboardInterceptionDecision {
        guard code == triggerCode, isHeld else { return .ignored }
        isHeld = false
        return .ended
    }

    mutating func modifierChanged(code: CGKeyCode, finderFrontmost: Bool, processing: Bool) -> KeyboardInterceptionDecision {
        isHeld ? keyUp(code: code) : keyDown(code: code, finderFrontmost: finderFrontmost, processing: processing)
    }
}

final class TriggerKeyRecorderView: NSView {
    private let prompt = NSTextField(labelWithString: "Press any key")
    private let detail = NSTextField(labelWithString: "Letters, numbers, punctuation, arrows, modifiers and function keys are supported.")
    private(set) var recordedKey: TriggerKey?
    var onRecord: ((TriggerKey) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.8).cgColor
        prompt.alignment = .center
        prompt.font = .systemFont(ofSize: 18, weight: .semibold)
        detail.alignment = .center
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        addSubview(prompt)
        addSubview(detail)
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        prompt.frame = NSRect(x: 12, y: 38, width: bounds.width - 24, height: 24)
        detail.frame = NSRect(x: 8, y: 10, width: bounds.width - 16, height: 18)
    }

    override func keyDown(with event: NSEvent) {
        record(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard TriggerKey.isModifier(code: CGKeyCode(event.keyCode)) else { return }
        record(event)
    }

    private func record(_ event: NSEvent) {
        let key = TriggerKey.from(event: event)
        recordedKey = key
        prompt.stringValue = key.label
        detail.stringValue = "Captured. Choose Save to use this key."
        onRecord?(key)
    }
}
