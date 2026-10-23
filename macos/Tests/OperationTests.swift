import AppKit
import ApplicationServices

@main
struct OperationTests {
    static func main() throws {
        _ = NSApplication.shared
        let manager = FileManager.default
        try testKeyboardInterception()
        try testUpdateInteractionGate()
        let root = manager.temporaryDirectory.appendingPathComponent("OrbitDropTests-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let sourceAsset = URL(fileURLWithPath: CommandLine.arguments[1])
        let image = root.appendingPathComponent("sample.png")
        try manager.copyItem(at: sourceAsset, to: image)

        let png = try FileOperations.execute(action: .png, sources: [image]).first!
        let jpg = try FileOperations.execute(action: .jpg, sources: [image]).first!
        let tiff = try FileOperations.execute(action: .tiff, sources: [image]).first!
        let bmp = try FileOperations.execute(action: .bmp, sources: [image]).first!
        let compressed = try FileOperations.execute(action: .shrink, sources: [image]).first!
        let resized = try FileOperations.execute(action: .resize, sources: [image]).first!
        let rotated = try FileOperations.execute(action: .rotate, sources: [image]).first!
        let flipped = try FileOperations.execute(action: .flip, sources: [image]).first!
        let grayscale = try FileOperations.execute(action: .grayscale, sources: [image]).first!
        let copied = try FileOperations.execute(action: .copy, sources: [image]).first!
        let imagePDF = try FileOperations.execute(action: .pdf, sources: [image]).first!

        let text = root.appendingPathComponent("notes.txt")
        try "OrbitDrop local conversion test".write(to: text, atomically: true, encoding: .utf8)
        let textPDF = try FileOperations.execute(action: .pdf, sources: [text]).first!
        let archive = try FileOperations.execute(action: .zip, sources: [image, text]).first!

        var outputs = [png, jpg, tiff, bmp, compressed, resized, rotated, flipped, grayscale, copied, imagePDF, textPDF, archive]
        if CommandLine.arguments.count > 2 {
            let docxSource = URL(fileURLWithPath: CommandLine.arguments[2])
            let docx = root.appendingPathComponent("document.docx")
            try manager.copyItem(at: docxSource, to: docx)
            let docxPDF = try FileOperations.execute(action: .pdf, sources: [docx]).first!
            outputs.append(docxPDF)
        }
        for output in outputs {
            guard manager.fileExists(atPath: output.path),
                  (try manager.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
                throw OrbitFileError.conversionFailed("Missing test output: \(output.lastPathComponent)")
            }
        }

        for pdf in outputs.filter({ $0.pathExtension.lowercased() == "pdf" }) {
            let header = try Data(contentsOf: pdf, options: .mappedIfSafe).prefix(4)
            guard String(data: header, encoding: .ascii) == "%PDF" else {
                throw OrbitFileError.conversionFailed("Invalid PDF: \(pdf.lastPathComponent)")
            }
        }

        guard let originalImage = NSImage(contentsOf: image), let resizedImage = NSImage(contentsOf: resized),
              resizedImage.size.width < originalImage.size.width,
              resizedImage.size.height < originalImage.size.height else {
            throw OrbitFileError.conversionFailed("Resize did not reduce the image dimensions.")
        }

        let originalBytes = (try manager.attributesOfItem(atPath: image.path)[.size] as? NSNumber)?.intValue ?? 0
        let compressedBytes = (try manager.attributesOfItem(atPath: compressed.path)[.size] as? NSNumber)?.intValue ?? 0
        guard originalBytes > 0, compressedBytes > 0, compressedBytes <= Int(Double(originalBytes) * 0.70) else {
            throw OrbitFileError.conversionFailed("Compression did not reduce the fixture by at least 30% (\(originalBytes) → \(compressedBytes) bytes).")
        }

        let reduction = 100 - Int((Double(compressedBytes) / Double(originalBytes)) * 100)
        print("PASS: 12 actions; adaptive compression reduced the fixture by \(reduction)%")
    }

    private static func testKeyboardInterception() throws {
        var gate = KeyboardInterceptionGate(triggerCode: 31) // Physical O key on macOS.
        guard gate.keyDown(code: 31, finderFrontmost: true, processing: false) == .began,
              gate.isHeld,
              gate.keyDown(code: 31, finderFrontmost: true, processing: false) == .repeated,
              gate.keyUp(code: 31) == .endedShortPress,
              !gate.isHeld else {
            throw OrbitFileError.conversionFailed("The configured letter key was not fully intercepted.")
        }
        guard gate.keyDown(code: 31, finderFrontmost: true, processing: false) == .began else {
            throw OrbitFileError.conversionFailed("The configured letter key could not start a second gesture.")
        }
        gate.activateGesture()
        guard gate.keyUp(code: 31) == .endedGesture else {
            throw OrbitFileError.conversionFailed("A committed hold was mistaken for an ordinary key press.")
        }
        guard gate.keyDown(code: 31, finderFrontmost: false, processing: false) == .ignored,
              gate.keyDown(code: 0, finderFrontmost: true, processing: false) == .ignored else {
            throw OrbitFileError.conversionFailed("Keyboard interception escaped its Finder/key scope.")
        }
        gate.updateTrigger(56) // Left Shift: modifier-key path.
        guard gate.modifierChanged(code: 56, finderFrontmost: true, processing: false) == .began,
              gate.modifierChanged(code: 56, finderFrontmost: true, processing: false) == .endedShortPress else {
            throw OrbitFileError.conversionFailed("Modifier trigger keys were not intercepted.")
        }
        guard TriggerKey.label(for: 31, characters: "o") == "O",
              TriggerKey.label(for: 123, characters: nil) == "Left Arrow" else {
            throw OrbitFileError.conversionFailed("Recorded key labels were not preserved.")
        }
        guard FinderBridge.isTextInput(role: kAXTextFieldRole as String, subrole: nil),
              FinderBridge.isTextInput(role: kAXTextAreaRole as String, subrole: nil),
              FinderBridge.isTextInput(role: kAXGroupRole as String, subrole: "AXSearchField"),
              !FinderBridge.isTextInput(role: kAXGroupRole as String, subrole: nil) else {
            throw OrbitFileError.conversionFailed("Finder text-entry detection did not protect rename and search fields.")
        }
        print("PASS: quick O presses remain normal; deliberate holds activate the wheel; modifiers pass through")
    }

    private static func testUpdateInteractionGate() throws {
        var gate = UpdateInteractionGate()
        guard gate.requestCheck(manual: false),
              !gate.requestCheck(manual: false),
              !gate.requestCheck(manual: true),
              gate.finishCheck(),
              gate.beginPrompt(),
              !gate.requestCheck(manual: true) else {
            throw OrbitFileError.conversionFailed("Concurrent update checks were not collapsed into one prompt.")
        }
        gate.endPrompt()
        guard gate.requestCheck(manual: false),
              !gate.finishCheck(),
              gate.beginInstall(),
              !gate.beginInstall(),
              !gate.requestCheck(manual: true) else {
            throw OrbitFileError.conversionFailed("Update installation did not suppress checks and duplicate launches.")
        }
        gate.failInstall()
        guard gate.requestCheck(manual: false), !gate.finishCheck() else {
            throw OrbitFileError.conversionFailed("A failed update did not restore future update checks.")
        }
        print("PASS: overlapping update checks collapse into one prompt; installs suppress duplicate checks")
    }
}
