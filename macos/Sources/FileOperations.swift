import AppKit

enum OrbitFileError: LocalizedError {
    case unsupported(String)
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let message), .conversionFailed(let message): return message
        }
    }
}

enum FileOperations {
    private static let imageExtensions = Set(["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"])

    static func perform(action: OrbitAction, sources: [URL], completion: @escaping (Result<[URL], Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let outputs = try execute(action: action, sources: sources)
                DispatchQueue.main.async {
                    NSSound(named: "Glass")?.play()
                    NSWorkspace.shared.activateFileViewerSelecting(outputs)
                    completion(.success(outputs))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    static func execute(action: OrbitAction, sources: [URL]) throws -> [URL] {
        guard !sources.isEmpty else { return [] }
        if action == .zip && sources.count > 1 {
            return [try zipTogether(sources)]
        }
        return try sources.map { source in
            switch action {
            case .pdf: return try convertToPDF(source)
            case .png: return try convertImage(source, format: .png, quality: 1)
            case .jpg: return try convertImage(source, format: .jpeg, quality: 0.86)
            case .tiff: return try convertImage(source, format: .tiff, quality: 1)
            case .bmp: return try convertImage(source, format: .bmp, quality: 1)
            case .zip: return try zip(source)
            case .shrink:
                return imageExtensions.contains(source.pathExtension.lowercased())
                    ? try convertImage(source, format: .jpeg, quality: 0.62, suffix: " compressed")
                    : try zip(source, suffix: " compressed")
            case .copy: return try copy(source)
            case .resize: return try editImage(source, operation: .resize)
            case .rotate: return try editImage(source, operation: .rotate)
            case .flip: return try editImage(source, operation: .flip)
            case .grayscale: return try editImage(source, operation: .grayscale)
            }
        }
    }

    private static func convertToPDF(_ source: URL) throws -> URL {
        let output = uniqueURL(beside: source, stem: source.deletingPathExtension().lastPathComponent, extension: "pdf")
        if imageExtensions.contains(source.pathExtension.lowercased()) {
            guard let image = NSImage(contentsOf: source) else {
                throw OrbitFileError.conversionFailed("The image could not be opened.")
            }
            let page = NSSize(width: 595, height: 842)
            let view = ImagePDFView(frame: NSRect(origin: .zero, size: page), image: image)
            try view.dataWithPDF(inside: view.bounds).write(to: output, options: .atomic)
            return output
        }

        var attributes: NSDictionary?
        let attributed: NSAttributedString
        do {
            attributed = try NSAttributedString(url: source, options: [:], documentAttributes: &attributes)
        } catch {
            throw OrbitFileError.unsupported("This document type cannot be rendered by macOS. DOCX, RTF, TXT, and HTML are supported.")
        }

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595, height: 842)
        printInfo.topMargin = 48
        printInfo.bottomMargin = 48
        printInfo.leftMargin = 52
        printInfo.rightMargin = 52
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output

        let contentWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 842))
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(attributed)
        textView.sizeToFit()
        textView.frame.size.width = contentWidth

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), FileManager.default.fileExists(atPath: output.path) else {
            throw OrbitFileError.conversionFailed("macOS could not create the PDF.")
        }
        return output
    }

    private static func convertImage(_ source: URL, format: NSBitmapImageRep.FileType, quality: Double, suffix: String = "") throws -> URL {
        guard let image = NSImage(contentsOf: source),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            throw OrbitFileError.unsupported("This image format is not supported by macOS.")
        }
        let ext: String
        switch format {
        case .png: ext = "png"
        case .tiff: ext = "tiff"
        case .bmp: ext = "bmp"
        default: ext = "jpg"
        }
        let properties: [NSBitmapImageRep.PropertyKey: Any] = format == .jpeg ? [.compressionFactor: quality] : [:]
        guard let data = bitmap.representation(using: format, properties: properties) else {
            throw OrbitFileError.conversionFailed("The image could not be converted.")
        }
        let stem = source.deletingPathExtension().lastPathComponent + suffix
        let output = uniqueURL(beside: source, stem: stem, extension: ext)
        try data.write(to: output, options: .atomic)
        return output
    }

    private enum ImageEdit {
        case resize, rotate, flip, grayscale

        var suffix: String {
            switch self {
            case .resize: return " resized"
            case .rotate: return " rotated"
            case .flip: return " flipped"
            case .grayscale: return " grayscale"
            }
        }
    }

    private static func editImage(_ source: URL, operation: ImageEdit) throws -> URL {
        guard let image = NSImage(contentsOf: source), image.size.width > 0, image.size.height > 0 else {
            throw OrbitFileError.unsupported("This image format is not supported by macOS.")
        }

        let outputImage: NSImage
        if operation == .grayscale {
            let width = max(1, image.representations.first?.pixelsWide ?? Int(image.size.width))
            let height = max(1, image.representations.first?.pixelsHigh ?? Int(image.size.height))
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: .alphaNonpremultiplied,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
            ), let pixels = bitmap.bitmapData else {
                throw OrbitFileError.conversionFailed("The grayscale edit could not be created.")
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            for row in 0..<height {
                for column in 0..<width {
                    let offset = row * bitmap.bytesPerRow + column * 4
                    let luminance = UInt8(min(255, Int(Double(pixels[offset]) * 0.2126 + Double(pixels[offset + 1]) * 0.7152 + Double(pixels[offset + 2]) * 0.0722)))
                    pixels[offset] = luminance
                    pixels[offset + 1] = luminance
                    pixels[offset + 2] = luminance
                }
            }
            outputImage = NSImage(size: NSSize(width: width, height: height))
            outputImage.addRepresentation(bitmap)
        } else {
            let targetSize: NSSize
            switch operation {
            case .resize:
                targetSize = NSSize(width: max(1, image.size.width / 2), height: max(1, image.size.height / 2))
            case .rotate:
                targetSize = NSSize(width: image.size.height, height: image.size.width)
            default:
                targetSize = image.size
            }

            outputImage = NSImage(size: targetSize)
            outputImage.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            let transform = NSAffineTransform()
            switch operation {
            case .rotate:
                transform.translateX(by: targetSize.width / 2, yBy: targetSize.height / 2)
                transform.rotate(byDegrees: -90)
                transform.translateX(by: -image.size.width / 2, yBy: -image.size.height / 2)
            case .flip:
                transform.translateX(by: targetSize.width, yBy: 0)
                transform.scaleX(by: -1, yBy: 1)
            default: break
            }
            transform.concat()
            image.draw(in: NSRect(origin: .zero, size: operation == .resize ? targetSize : image.size), from: .zero, operation: .sourceOver, fraction: 1)
            outputImage.unlockFocus()
        }

        guard let tiff = outputImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw OrbitFileError.conversionFailed("The edited image could not be saved.")
        }
        let output = uniqueURL(beside: source, stem: source.deletingPathExtension().lastPathComponent + operation.suffix, extension: "png")
        try data.write(to: output, options: .atomic)
        return output
    }

    private static func zip(_ source: URL, suffix: String = "") throws -> URL {
        let output = uniqueURL(beside: source, stem: source.deletingPathExtension().lastPathComponent + suffix, extension: "zip")
        try run("/usr/bin/ditto", arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, output.path])
        return output
    }

    private static func zipTogether(_ sources: [URL]) throws -> URL {
        let directory = sources[0].deletingLastPathComponent()
        let output = uniqueURL(in: directory, stem: "OrbitDrop Archive", extension: "zip")
        let arguments = ["-r", "-q", output.path] + sources.map(\.path)
        try run("/usr/bin/zip", arguments: arguments)
        return output
    }

    private static func copy(_ source: URL) throws -> URL {
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent + " copy"
        let output = uniqueURL(beside: source, stem: stem, extension: ext)
        try FileManager.default.copyItem(at: source, to: output)
        return output
    }

    private static func uniqueURL(beside source: URL, stem: String, extension ext: String) -> URL {
        uniqueURL(in: source.deletingLastPathComponent(), stem: stem, extension: ext)
    }

    private static func uniqueURL(in directory: URL, stem: String, extension ext: String) -> URL {
        let cleanedExtension = ext.isEmpty ? "" : ".\(ext)"
        var candidate = directory.appendingPathComponent("\(stem)\(cleanedExtension)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem) \(counter)\(cleanedExtension)")
            counter += 1
        }
        return candidate
    }

    private static func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw OrbitFileError.conversionFailed(detail?.isEmpty == false ? detail! : "The file operation failed.")
        }
    }

    static func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.messageText = "OrbitDrop couldn’t finish that action"
        alert.runModal()
    }
}

private final class ImagePDFView: NSView {
    private let image: NSImage

    init(frame frameRect: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let margin: CGFloat = 36
        let available = bounds.insetBy(dx: margin, dy: margin)
        let scale = min(available.width / image.size.width, available.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = NSRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2, width: size.width, height: size.height)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}
