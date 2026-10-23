import AppKit
import ApplicationServices

enum FinderBridge {
    static var isFinderFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    static var isTextInputFocused: Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue else { return false }

        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        return isTextInput(
            role: stringAttribute(kAXRoleAttribute, from: focused),
            subrole: stringAttribute(kAXSubroleAttribute, from: focused)
        )
    }

    static func isTextInput(role: String?, subrole: String?) -> Bool {
        let textRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ]
        let textSubroles: Set<String> = ["AXSearchField", "AXSecureTextField"]
        return role.map(textRoles.contains) == true || subrole.map(textSubroles.contains) == true
    }

    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func selectedURLs() -> [URL] {
        let source = """
        tell application "Finder"
            set selectedItems to selection
            if (count of selectedItems) is 0 then return ""
            set outputText to ""
            repeat with selectedItem in selectedItems
                try
                    set outputText to outputText & POSIX path of (selectedItem as alias) & linefeed
                end try
            end repeat
            return outputText
        end tell
        """

        var error: NSDictionary?
        guard let script = NSAppleScript(source: source),
              let result = script.executeAndReturnError(&error).stringValue else {
            return []
        }

        return result
            .split(whereSeparator: \.isNewline)
            .map { URL(fileURLWithPath: String($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
