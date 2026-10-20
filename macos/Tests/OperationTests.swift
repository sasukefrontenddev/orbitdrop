import AppKit

@main
struct OperationTests {
    static func main() throws {
        _ = NSApplication.shared
        let manager = FileManager.default
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
}
