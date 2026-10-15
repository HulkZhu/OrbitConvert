import AppKit

// Only the rounded sector paths receive glass; the root view is fully transparent.
final class RingView: NSView {
    let file: URL
    private(set) var formats: [Format]
    let original: String
    let glassDensity: Double
    let clearGlass: Bool
    let glassColor: NSColor
    let textScale: Double
    let centerTextScale: Double
    var colorWash: NSColor {
        let rgb = glassColor.usingColorSpace(.sRGB) ?? .white
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        let chromatic = (components.max()! - components.min()!) > 0.05
        let alpha = glassDensity <= 0 ? 0 : (chromatic ? 0.22 + glassDensity * 0.30 : glassDensity * 0.25)
        return rgb.withAlphaComponent(alpha)
    }
    var highlightWash: NSColor {
        glassColor.withAlphaComponent(min(0.78, max(0.32, colorWash.alphaComponent + 0.22)))
    }
    let onChoose: (URL, Format) -> Void
    var feedbackEnabled = false
    var hovered: Int? { didSet { if hovered != oldValue { animateHover() } } }
    private var expansion: [Double] = []
    private var animationTimer: Timer?
    private var animationStart: TimeInterval = 0
    private var animationFrom: [Double] = []
    private var animationTo: [Double] = []
    private var layoutTimer: Timer?
    private var angles: [Double] = []
    private var spans: [Double] = []
    private var opacities: [Double] = []
    private var cardFrames: [String: CGRect] = [:]
    private var morphPlans: [String: SectorMorph.Plan] = [:]
    private var morphTargets: [String: CGPath] = [:]
    private var framePaths: [Int: CGPath] = [:]
    private var cardProgress = 1.0
    private var nativeMorphID: String?
    private var plates: [NSView] = []
    private var tracking: NSTrackingArea?

    init(file: URL, formats: [Format], original: String, glassDensity: Double = 0.08, clearGlass: Bool = true, glassColor: NSColor = .white, textScale: Double = 1, centerTextScale: Double = 1, onChoose: @escaping (URL, Format) -> Void) {
        self.file = file; self.formats = formats; self.original = original; self.onChoose = onChoose
        self.glassDensity = glassDensity; self.clearGlass = clearGlass
        self.glassColor = glassColor
        self.centerTextScale = min(2, max(0.6, centerTextScale))
        self.textScale = min(1.6, max(0.8, textScale))
        super.init(frame: NSRect(x: 0, y: 0, width: 440, height: 440))
        expansion = Array(repeating: 0, count: formats.count)
        angles = formats.indices.map { Double($0) * 2 * .pi / Double(formats.count) + .pi / 2 }
        spans = Array(repeating: 2 * .pi / Double(max(1, formats.count)), count: formats.count)
        opacities = Array(repeating: 1, count: formats.count)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        for _ in formats {
            let plate: NSView
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView(frame: bounds)
                glass.style = clearGlass ? .clear : .regular
                glass.cornerRadius = 0
                plate = glass
            } else {
                // Older macOS cannot render Apple's Liquid Glass.
                plate = NSView(frame: bounds)
                plate.wantsLayer = true
                plate.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            plate.wantsLayer = true
            addSubview(plate); plates.append(plate)
        }
        if #available(macOS 26.0, *) {
            let centre = NSGlassEffectView(frame: NSRect(x: 155, y: 192, width: 130, height: 56))
            centre.style = clearGlass ? .clear : .regular
            centre.tintColor = colorWash
            centre.cornerRadius = 28
            addSubview(centre)
        }
        let labels = Canvas(owner: self)
        addSubview(labels)
        refresh()
    }
    required init?(coder: NSCoder) { nil }
    func setFormats(_ next: [Format], insertionPoint: CGPoint? = nil) {
        guard next.map(\.ext) != formats.map(\.ext) else { return }
        layoutTimer?.invalidate(); animationTimer?.invalidate()
        let previous = Dictionary(uniqueKeysWithValues: formats.indices.map { (formats[$0].ext, ($0, angles[$0], spans[$0], opacities[$0])) })
        let oldPlates = plates
        let nextIDs = Set(next.map(\.ext))
        for i in formats.indices where !nextIDs.contains(formats[i].ext) { oldPlates[i].removeFromSuperview() }
        formats = next
        cardFrames = cardFrames.filter { nextIDs.contains($0.key) && cardProgress < 1 }
        morphPlans = morphPlans.filter { cardFrames[$0.key] != nil }
        morphTargets = morphTargets.filter { cardFrames[$0.key] != nil }
        if let point = insertionPoint {
            for format in next where previous[format.ext] == nil {
                cardFrames[format.ext] = CGRect(x: point.x - 104 * 440 / 340 / 2, y: point.y - 48 * 440 / 340 / 2, width: 104 * 440 / 340, height: 48 * 440 / 340)
            }
        }
        let addedCard = next.contains { previous[$0.ext] == nil && cardFrames[$0.ext] != nil }
        cardProgress = cardFrames.isEmpty ? 1 : (addedCard ? 0 : cardProgress)
        let fromCardProgress = cardProgress
        let width = 2 * Double.pi / Double(max(1, next.count))
        let targetAngles = next.indices.map { Double($0) * width + .pi / 2 }
        angles = next.indices.map { index in
            guard let old = previous[next[index].ext] else { return targetAngles[index] }
            let difference = atan2(sin(old.1 - targetAngles[index]), cos(old.1 - targetAngles[index]))
            return targetAngles[index] + difference
        }
        spans = next.map { previous[$0.ext]?.2 ?? max(0.45, width * 0.65) }
        opacities = next.map { previous[$0.ext]?.3 ?? 1 }
        expansion = Array(repeating: 0, count: next.count)
        plates = next.map { format in
            if let old = previous[format.ext] { return oldPlates[old.0] }
            let plate: NSView
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView(frame: bounds)
                glass.style = clearGlass ? .clear : .regular; glass.cornerRadius = 0
                plate = glass
            } else {
                plate = NSView(frame: bounds); plate.wantsLayer = true
                plate.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            plate.wantsLayer = true
            addSubview(plate, positioned: .below, relativeTo: subviews.last)
            return plate
        }
        let fromAngles = angles, fromSpans = spans, fromOpacity = opacities
        let start = ProcessInfo.processInfo.systemUptime
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, window != nil else {
            angles = targetAngles; spans = Array(repeating: width, count: next.count)
            opacities = Array(repeating: 1, count: next.count); cardProgress = 1; refresh(); return
        }
        refresh()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self, self.window != nil else { timer.invalidate(); return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime - start) / (self.cardFrames.isEmpty ? 0.22 : 0.32))
            let eased = t * t * (3 - 2 * t)
            self.cardProgress = fromCardProgress + (1-fromCardProgress)*eased
            self.angles = next.indices.map { fromAngles[$0] + (targetAngles[$0] - fromAngles[$0]) * eased }
            self.spans = fromSpans.map { $0 + (width - $0) * eased }
            self.opacities = fromOpacity.map { $0 + (1 - $0) * eased }
            self.refresh()
            if t >= 1 { timer.invalidate(); self.layoutTimer = nil }
        }
        layoutTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self)
        tracking = area; addTrackingArea(area)
        super.updateTrackingAreas()
    }
    func sector(_ index: Int, expanded: Bool = false) -> CGPath {
        SectorGeometry.sector(index, count: formats.count, expanded: expanded)
    }
    func index(at point: NSPoint) -> Int? {
        // Hit-testing uses the same rounded paths as drawing, including the gaps.
        if let hovered, sector(hovered, expanded: true).contains(point) { return hovered }
        return formats.indices.first { sector($0).contains(point) }
    }
    func update(at point: NSPoint) {
        let next = index(at: point)
        if next != hovered { hovered = next }
    }
    private func animateHover() {
        animationTimer?.invalidate()
        animationFrom = expansion
        animationTo = formats.indices.map { hovered == $0 ? 1 : 0 }
        if feedbackEnabled, hovered != nil { WheelHaptics.play(Preferences.shared.hapticMode) }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, window != nil else {
            expansion = animationTo; refresh(); return
        }
        animationStart = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self, self.window != nil else { timer.invalidate(); return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime - self.animationStart) / 0.18)
            let eased = t * t * (3 - 2 * t)
            self.expansion = zip(self.animationFrom, self.animationTo).map { $0 + ($1 - $0) * eased }
            self.refresh()
            if t >= 1 { timer.invalidate(); self.animationTimer = nil }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { animationTimer?.invalidate(); animationTimer = nil; layoutTimer?.invalidate(); layoutTimer = nil }
    }
    deinit { animationTimer?.invalidate(); layoutTimer?.invalidate() }
    func displaySector(_ index: Int) -> CGPath {
        if let cached = framePaths[index] { return cached }
        let sector = SectorGeometry.sector(index, count: formats.count, expansion: expansion[index], angle: angles[index], span: spans[index])
        var path = sector
        let id = formats[index].ext
        if let frame = cardFrames[id], cardProgress < 1 {
            if morphPlans[id] == nil {
                let target = SectorGeometry.sector(index, count: formats.count)
                morphTargets[id] = target
                morphPlans[id] = SectorMorph.Plan(card: frame, sector: target)
            }
            // Do not remap contour points against an expanding sector each
            // frame: its perimeter parameterization shifts and visibly twists.
            path = morphPlans[id]!.path(to: morphTargets[id]!, progress: cardProgress)
        }
        framePaths[index] = path
        return path
    }
    func displayWash(_ index: Int) -> NSColor {
        colorWash.blended(withFraction: expansion[index], of: highlightWash) ?? colorWash
    }
    private func refresh() {
        framePaths.removeAll(keepingCapacity: true)
        nativeMorphID = nil
        if let window, let deliver = SettingsNavigation.shared.morphImage,
           SettingsNavigation.shared.previewIDs != nil,
           let index = formats.indices.first(where: { cardFrames[formats[$0].ext] != nil }), cardProgress < 1 {
            nativeMorphID = formats[index].ext
            let path = displaySector(index), progress = cardProgress
            let card = cardFrames[formats[index].ext]!
            let angle = angles[index], title = formats[index].name as NSString
            let center = CGPoint(x: card.midX + (220 + cos(angle)*134-card.midX)*progress,
                                 y: card.midY + (220 + sin(angle)*134-card.midY)*progress)
            let wash = NSColor.windowBackgroundColor.withAlphaComponent(0.9).blended(withFraction: progress, of: colorWash) ?? colorWash
            let image = NSImage(size: bounds.size, flipped: false) { _ in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.addPath(path); context.setFillColor(wash.cgColor); context.fillPath()
                context.addPath(path); context.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor); context.strokePath()
                let font = (22 * 440 / 340) * (1-progress) + 17*self.textScale*progress
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: font, weight: .medium), .foregroundColor: NSColor.labelColor]
                let size = title.size(withAttributes: attributes)
                title.draw(at: CGPoint(x: center.x-size.width/2, y: center.y-size.height/2), withAttributes: attributes)
                return true
            }
            deliver(image, window.convertToScreen(convert(bounds, to: nil)))
        } else if !cardFrames.isEmpty, SettingsNavigation.shared.previewIDs != nil {
            SettingsNavigation.shared.cardVisibility?(false)
        }
        for (index, plate) in plates.enumerated() {
            let mask = plate.layer?.mask as? CAShapeLayer ?? CAShapeLayer()
            mask.frame = bounds
            CATransaction.begin(); CATransaction.setDisableActions(true)
            plate.alphaValue = formats[index].ext == nativeMorphID ? 0 : opacities[index]
            mask.path = displaySector(index)
            plate.layer?.mask = mask
            if #available(macOS 26.0, *), let glass = plate as? NSGlassEffectView {
                glass.tintColor = displayWash(index)
            }
            CATransaction.commit()
        }
        subviews.last?.needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) { update(at: convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { update(at: convert(event.locationInWindow, from: nil)) }
    override func mouseDown(with event: NSEvent) { update(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hovered = nil }
    override func mouseUp(with event: NSEvent) {
        if let hit = index(at: convert(event.locationInWindow, from: nil)) { onChoose(file, formats[hit]) }
        else { window?.orderOut(nil) }
    }
    final class Canvas: NSView {
        weak var owner: RingView?
        init(owner: RingView) { self.owner = owner; super.init(frame: owner.bounds) }
        required init?(coder: NSCoder) { nil }
        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            guard let owner, let context = NSGraphicsContext.current?.cgContext else { return }
            for index in owner.formats.indices {
                if owner.formats[index].ext == owner.nativeMorphID { continue }
                context.saveGState()
                context.setAlpha(owner.opacities[index])
                let amount = owner.expansion[index]
                let path = owner.displaySector(index)
                // Native clear-glass tint can be barely visible on bright backgrounds.
                // Add a translucent wash ABOVE the native glass, retaining its optics.
                context.addPath(path)
                context.setFillColor(owner.displayWash(index).cgColor)
                context.fillPath()
                context.addPath(path)
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.6 + 0.35 * amount).cgColor)
                context.setLineWidth(1 + 1.5 * amount)
                context.strokePath()
                let angle = owner.angles[index]
                let label = owner.formats[index].name as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: (17 + 2 * amount) * owner.textScale, weight: .semibold), .foregroundColor: NSColor.labelColor]
                let size = label.size(withAttributes: attributes)
                var labelCenter = NSPoint(x: 220 + cos(angle) * 134, y: 220 + sin(angle) * 134)
                if let card = owner.cardFrames[owner.formats[index].ext], owner.cardProgress < 1 {
                    labelCenter = NSPoint(x: card.midX+(labelCenter.x-card.midX)*owner.cardProgress, y: card.midY+(labelCenter.y-card.midY)*owner.cardProgress)
                }
                label.draw(at: NSPoint(x: labelCenter.x-size.width/2, y: labelCenter.y-size.height/2), withAttributes: attributes)
                context.restoreGState()
            }
            let title = owner.original as NSString
            owner.colorWash.setFill()
            NSBezierPath(roundedRect: NSRect(x: 155, y: 192, width: 130, height: 56), xRadius: 28, yRadius: 28).fill()
            let requested = 23 * owner.centerTextScale
            let natural = title.size(withAttributes: [.font: NSFont.systemFont(ofSize: requested, weight: .bold)]).width
            let fitted = requested * min(1, 136 / max(1, natural))
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fitted, weight: .bold), .foregroundColor: NSColor.labelColor]
            let size = title.size(withAttributes: attributes)
            title.draw(at: NSPoint(x: 220 - size.width / 2, y: 220 - size.height / 2), withAttributes: attributes)
        }
    }
}

final class FilePreview: NSView {
    let icon: NSImage
    let name: String
    init(file: URL, count: Int = 1) {
        icon = NSWorkspace.shared.icon(forFile: file.path); name = count > 1 ? "\(count) 个文件" : file.lastPathComponent
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 96))
    }
    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        icon.draw(in: NSRect(x: 8, y: 28, width: 48, height: 56))
        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: NSRect(x: 43, y: 24, width: 24, height: 24)).fill()
        ("+" as NSString).draw(at: NSPoint(x: 47, y: 22), withAttributes: [.font: NSFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: NSColor.white])
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingMiddle
        (name as NSString).draw(in: NSRect(x: 2, y: 2, width: 156, height: 19), withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white, .backgroundColor: NSColor.systemBlue, .paragraphStyle: style])
    }
}
