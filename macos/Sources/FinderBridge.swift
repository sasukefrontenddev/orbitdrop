import AppKit

enum FinderBridge {
    static var isFinderFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
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
