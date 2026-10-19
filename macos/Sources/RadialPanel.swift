import AppKit
import QuartzCore

enum OrbitAction: Int, CaseIterable {
    case pdf, png, jpg, tiff, bmp, zip, shrink, resize, rotate, flip, grayscale, copy

    var title: String {
        switch self {
        case .pdf: return "PDF"
        case .png: return "PNG"
        case .jpg: return "JPG"
        case .tiff: return "TIFF"
        case .bmp: return "BMP"
        case .zip: return "ZIP"
        case .shrink: return "SHRINK"
        case .resize: return "50%"
        case .rotate: return "ROTATE"
        case .flip: return "FLIP"
        case .grayscale: return "GRAY"
        case .copy: return "COPY"
        }
    }

    var detail: String {
        switch self {
        case .pdf: return "Create a PDF"
        case .png: return "Convert to PNG"
        case .jpg: return "Convert to JPG"
        case .tiff: return "Convert to TIFF"
        case .bmp: return "Convert to BMP"
        case .zip: return "Create a ZIP"
        case .shrink: return "Compress the file"
        case .resize: return "Resize image to 50%"
        case .rotate: return "Rotate 90 degrees"
        case .flip: return "Flip horizontally"
        case .grayscale: return "Make grayscale"
        case .copy: return "Create a safe copy"
        }
    }

    var symbol: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .png: return "photo"
        case .jpg: return "photo.fill"
        case .tiff: return "photo.stack"
        case .bmp: return "square.grid.3x3.fill"
        case .zip: return "archivebox.fill"
        case .shrink: return "arrow.down.right.and.arrow.up.left"
        case .resize: return "aspectratio"
        case .rotate: return "rotate.right"
        case .flip: return "arrow.left.and.right"
        case .grayscale: return "circle.lefthalf.filled"
        case .copy: return "doc.on.doc.fill"
        }
    }
}

final class RadialPanel: NSPanel {
    let radialView = RadialView(frame: NSRect(x: 0, y: 0, width: 480, height: 480))

    init() {
        super.init(
            contentRect: radialView.bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = radialView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        animationBehavior = .none
    }

    func show(at point: NSPoint, files: [URL]) {
        radialView.configure(files: files)
        let size = frame.size
        let visible = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: min(max(point.x - size.width / 2, visible.minX), visible.maxX - size.width),
            y: min(max(point.y - size.height / 2, visible.minY), visible.maxY - size.height)
        )
        setFrameOrigin(origin)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func hide(animated: Bool = true) {
        radialView.highlighted = nil
        guard animated, isVisible else {
            alphaValue = 1
            orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
        })
    }

    func showProcessing(_ action: OrbitAction) {
        radialView.showProcessing(action)
    }

    func showSuccess(_ message: String) {
        radialView.showSuccess(message)
    }

    func showFailure() {
        radialView.showFailure()
    }

    func updateHighlight(globalPoint: NSPoint) {
        let local = radialView.convert(convertPoint(fromScreen: globalPoint), from: nil)
        radialView.highlighted = radialView.action(at: local)
    }

    func action(globalPoint: NSPoint) -> OrbitAction? {
        radialView.action(at: radialView.convert(convertPoint(fromScreen: globalPoint), from: nil))
    }
}

final class RadialView: NSView {
    private enum Phase {
        case ready
        case processing(OrbitAction)
        case success(String)
        case failure
    }

    private let center = NSPoint(x: 240, y: 240)
    private let innerRadius: CGFloat = 88
    private let outerRadius: CGFloat = 218
    private(set) var files: [URL] = []
    private var disabledActions = Set<OrbitAction>()
    private var phase: Phase = .ready
    private var pulse: CGFloat = 0
    private var pulseTimer: Timer?
    var highlighted: OrbitAction? {
        didSet {
            if oldValue != highlighted, highlighted != nil {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { false }

    deinit {
        pulseTimer?.invalidate()
    }

    func configure(files: [URL]) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulse = 0
        phase = .ready
        self.files = files
        disabledActions.removeAll()
        let imageExtensions = Set(["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"])
        let documentExtensions = Set(["docx", "rtf", "rtfd", "txt", "html", "htm"])
        let extensions = Set(files.map { $0.pathExtension.lowercased() })
        let allImages = !files.isEmpty && extensions.allSatisfy(imageExtensions.contains)
        let allPdfConvertible = !files.isEmpty && extensions.allSatisfy { imageExtensions.contains($0) || documentExtensions.contains($0) }
        if !allImages {
            disabledActions.formUnion([.png, .jpg, .tiff, .bmp, .resize, .rotate, .flip, .grayscale])
        }
        if !allPdfConvertible { disabledActions.insert(.pdf) }
        highlighted = nil
        needsDisplay = true
    }

    func showProcessing(_ action: OrbitAction) {
        highlighted = action
        phase = .processing(action)
        pulse = 0
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pulse = (self.pulse + 0.055).truncatingRemainder(dividingBy: 1)
            self.needsDisplay = true
        }
        needsDisplay = true
    }

    func showSuccess(_ message: String) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        highlighted = nil
        phase = .success(message)
        needsDisplay = true
    }

    func showFailure() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        highlighted = nil
        phase = .failure
        needsDisplay = true
    }

    func action(at point: NSPoint) -> OrbitAction? {
        guard case .ready = phase else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius, distance <= outerRadius else { return nil }
        let degrees = atan2(dy, dx) * 180 / .pi
        let clockwiseFromTop = (90 - degrees + 360).truncatingRemainder(dividingBy: 360)
        let index = Int(clockwiseFromTop / 30)
        guard let action = OrbitAction(rawValue: index), !disabledActions.contains(action) else { return nil }
        return action
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        drawAmbientGlow()
        for action in OrbitAction.allCases { drawSector(action) }
        drawCenter()
    }

    private func drawAmbientGlow() {
        let glowRect = NSRect(x: center.x - outerRadius - 5, y: center.y - outerRadius - 5, width: (outerRadius + 5) * 2, height: (outerRadius + 5) * 2)
        let glow = NSBezierPath(ovalIn: glowRect)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedRed: 0.35, green: 0.23, blue: 0.95, alpha: 0.24)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = .zero
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor(calibratedWhite: 0.03, alpha: 0.16).setFill()
        glow.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSector(_ action: OrbitAction) {
        let index = CGFloat(action.rawValue)
        let gap: CGFloat = 0.65
        let start = 90 - index * 30 - gap
        let end = 90 - (index + 1) * 30 + gap
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: true)
        path.line(to: point(radius: innerRadius, angle: end))
        path.appendArc(withCenter: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: false)
        path.close()

        let isDisabled = disabledActions.contains(action)
        let isHighlighted = highlighted == action
        let fill: NSColor
        if isDisabled {
            fill = NSColor(calibratedRed: 0.045, green: 0.050, blue: 0.090, alpha: 0.46)
        } else if isHighlighted {
            fill = NSColor(calibratedRed: 0.31, green: 0.20, blue: 0.78, alpha: 0.94)
        } else {
            fill = NSColor(calibratedRed: 0.045, green: 0.050, blue: 0.105, alpha: 0.82)
        }

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        fill.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        (isHighlighted
            ? NSColor(calibratedRed: 0.76, green: 0.96, blue: 0.22, alpha: 0.82)
            : NSColor(calibratedRed: 0.45, green: 0.37, blue: 0.84, alpha: isDisabled ? 0.16 : 0.42)).setStroke()
        path.lineWidth = isHighlighted ? 1.8 : 1
        path.stroke()

        let labelPoint = point(radius: 163, angle: 75 - index * 30)
        let foreground = isDisabled
            ? NSColor(calibratedWhite: 0.52, alpha: 0.66)
            : isHighlighted ? NSColor.white : NSColor(calibratedWhite: 0.93, alpha: 1)
        drawSymbol(action.symbol, at: labelPoint, color: isHighlighted ? brandLime : foreground)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        action.title.draw(in: NSRect(x: labelPoint.x - 34, y: labelPoint.y - 19, width: 68, height: 14), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 8.2, weight: .bold),
            .foregroundColor: foreground,
            .paragraphStyle: paragraph,
            .kern: 0.45,
        ])
    }

    private func drawSymbol(_ name: String, at location: NSPoint, color: NSColor) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let configured = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)) ?? image
        let rect = NSRect(x: location.x - 9, y: location.y + 1, width: 18, height: 18)
        tinted(configured, color: color).draw(in: rect)
    }

    private func drawCenter() {
        let centerRect = NSRect(x: center.x - 82, y: center.y - 82, width: 164, height: 164)
        let circle = NSBezierPath(ovalIn: centerRect)
        NSColor(calibratedRed: 0.025, green: 0.028, blue: 0.064, alpha: 0.96).setFill()
        circle.fill()
        NSColor(calibratedRed: 0.42, green: 0.30, blue: 0.92, alpha: 0.50).setStroke()
        circle.lineWidth = 5
        circle.stroke()

        switch phase {
        case .ready:
            drawBrandMark(y: center.y + 34)
            if let action = highlighted {
                drawCenterLines(kicker: action.title, title: action.detail, footer: "RELEASE TO RUN")
            } else {
                let first = files.first
                let type = files.count > 1 ? "\(files.count) FILES" : (first?.pathExtension.uppercased().isEmpty == false ? first!.pathExtension.uppercased() : "FILE")
                let name = files.count > 1 ? "Batch action" : (first?.lastPathComponent ?? "Selected file")
                drawCenterLines(kicker: type, title: name, footer: "DRAG & RELEASE")
            }
        case .processing(let action):
            drawSpinner()
            drawCenterLines(kicker: action.title, title: "Working locally…", footer: "KEEPING ORIGINAL SAFE", offset: -4)
        case .success(let message):
            drawStatusSymbol("checkmark", color: brandLime)
            drawCenterLines(kicker: "DONE", title: message, footer: "REVEALED IN FINDER", offset: -4)
        case .failure:
            drawStatusSymbol("exclamationmark", color: NSColor(calibratedRed: 1, green: 0.43, blue: 0.50, alpha: 1))
            drawCenterLines(kicker: "NOT COMPLETED", title: "Check the message", footer: "ORIGINAL UNCHANGED", offset: -4)
        }
    }

    private func drawBrandMark(y: CGFloat) {
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 15, y: y - 15, width: 30, height: 30))
        NSColor(calibratedRed: 0.38, green: 0.25, blue: 0.95, alpha: 0.88).setStroke()
        ring.lineWidth = 4
        ring.stroke()
        let orbit = NSBezierPath()
        orbit.appendArc(withCenter: NSPoint(x: center.x, y: y), radius: 20, startAngle: -18, endAngle: 210, clockwise: false)
        brandLime.setStroke()
        orbit.lineWidth = 2
        orbit.stroke()
        brandLime.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x + 16, y: y - 7, width: 7, height: 7)).fill()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: center.x - 5, y: y + 6))
        arrow.line(to: NSPoint(x: center.x + 5, y: y))
        arrow.line(to: NSPoint(x: center.x - 5, y: y - 6))
        arrow.close()
        brandLime.setFill()
        arrow.fill()
    }

    private func drawSpinner() {
        let start = 360 * pulse
        let spinner = NSBezierPath()
        spinner.appendArc(withCenter: NSPoint(x: center.x, y: center.y + 32), radius: 17, startAngle: start, endAngle: start + 245, clockwise: false)
        brandLime.setStroke()
        spinner.lineWidth = 3.2
        spinner.lineCapStyle = .round
        spinner.stroke()
    }

    private func drawStatusSymbol(_ symbol: String, color: NSColor) {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return }
        let configured = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .bold)) ?? image
        let rect = NSRect(x: center.x - 12, y: center.y + 20, width: 24, height: 24)
        tinted(configured, color: color).draw(in: rect)
    }

    private func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let output = NSImage(size: image.size)
        output.lockFocus()
        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1)
        color.setFill()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        output.unlockFocus()
        return output
    }

    private func drawCenterLines(kicker: String, title: String, footer: String, offset: CGFloat = 0) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingMiddle
        kicker.draw(in: NSRect(x: center.x - 56, y: center.y + 4 + offset, width: 112, height: 15), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 8.5, weight: .bold),
            .foregroundColor: brandLime,
            .paragraphStyle: paragraph,
            .kern: 1.0,
        ])
        title.draw(in: NSRect(x: center.x - 60, y: center.y - 17 + offset, width: 120, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
        footer.draw(in: NSRect(x: center.x - 58, y: center.y - 37 + offset, width: 116, height: 12), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 6.6, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.68, alpha: 1),
            .paragraphStyle: paragraph,
            .kern: 0.7,
        ])
    }

    private var brandLime: NSColor {
        NSColor(calibratedRed: 0.76, green: 0.98, blue: 0.16, alpha: 1)
    }

    private func point(radius: CGFloat, angle: CGFloat) -> NSPoint {
        let radians = angle * .pi / 180
        return NSPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
    }
}
