import AppKit

final class ExitMorphOverlay: NSView {
    // Paths and pointer positions below are in the hosting view's coordinates.
    // SwiftUI hosting views can be flipped; the overlay must use the same axes.
    override var isFlipped: Bool { superview?.isFlipped ?? false }
    private var timer: Timer?
    private var path: CGPath?
    private var label = ""
    private var labelPoint = CGPoint.zero
    static func show(ring: RingView, id: String) -> ExitMorphOverlay? {
        guard let window = ring.window, let parent = window.contentView,
              let index = ring.formats.firstIndex(where: { $0.ext == id }) else { return nil }
        let overlay = ExitMorphOverlay(frame: parent.bounds)
        overlay.label = ring.formats[index].name
        let origin = ring.convert(CGPoint.zero, to: parent)
        let unit = ring.convert(CGPoint(x: 1, y: 1), to: parent)
        var transform = CGAffineTransform(a: unit.x-origin.x, b: 0, c: 0, d: unit.y-origin.y, tx: origin.x, ty: origin.y)
        let sector = ring.displaySector(index).copy(using: &transform)!
        let box = sector.boundingBoxOfPath
        let fromLabel = CGPoint(x: box.midX, y: box.midY)
        let mouse = parent.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let card = CGRect(x: mouse.x-52, y: mouse.y-24, width: 104, height: 48)
        let plan = SectorMorph.Plan(card: card, sector: sector)
        parent.addSubview(overlay, positioned: .above, relativeTo: nil)
        overlay.path = sector
        overlay.labelPoint = fromLabel
        overlay.needsDisplay = true
        let start = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1/60, repeats: true) { [weak overlay, weak parent, weak window] timer in
            guard let overlay, let parent, let window else { timer.invalidate(); return }
            if NSEvent.pressedMouseButtons & 1 == 0 && ProcessInfo.processInfo.systemUptime-start > 0.3 {
                overlay.stop()
                DispatchQueue.main.async { SettingsNavigation.shared.clearDrag() }
                return
            }
            let t = min(1, (ProcessInfo.processInfo.systemUptime-start)/0.26)
            let eased = t*t*(3-2*t)
            let point = parent.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            var translation = CGAffineTransform(translationX: (point.x-mouse.x)*eased, y: (point.y-mouse.y)*eased)
            overlay.path = plan.path(to: sector, progress: 1-eased).copy(using: &translation)
            overlay.labelPoint = CGPoint(x: fromLabel.x+(point.x-fromLabel.x)*eased, y: fromLabel.y+(point.y-fromLabel.y)*eased)
            overlay.needsDisplay = true
        }
        overlay.timer = timer; RunLoop.main.add(timer, forMode: .common)
        return overlay
    }
    func stop() { timer?.invalidate(); timer = nil; removeFromSuperview() }
    deinit { timer?.invalidate() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        guard let path, let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(path); context.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor); context.fillPath()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: NSColor.labelColor]
        let text = label as NSString, size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: labelPoint.x-size.width/2, y: labelPoint.y-size.height/2), withAttributes: attributes)
    }
}
