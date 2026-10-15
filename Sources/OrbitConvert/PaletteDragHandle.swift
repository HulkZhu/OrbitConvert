import AppKit
import SwiftUI

struct PaletteDragHandle: NSViewRepresentable {
    let format: Format
    let navigation: SettingsNavigation
    let preferences: Preferences
    let onClick: () -> Void
    func makeNSView(context: Context) -> PaletteDragView { PaletteDragView() }
    func updateNSView(_ view: PaletteDragView, context: Context) {
        view.format = format; view.navigation = navigation; view.onClick = onClick
        view.preferences = preferences
    }
}

final class PaletteDragView: NSView, NSDraggingSource {
    var format: Format!
    weak var navigation: SettingsNavigation?
    var onClick: (() -> Void)?
    weak var preferences: Preferences?
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "添加到所有支持的圆盘", action: #selector(addEverywhere), keyEquivalent: "").target = self
        menu.addItem(withTitle: "从所有圆盘移除 \(format.name)", action: #selector(removeEverywhere), keyEquivalent: "").target = self
        if let source = navigation?.source, let group = WheelOptions.group(for: source) {
            menu.addItem(.separator())
            menu.addItem(withTitle: "添加到所有支持的“\(group)”圆盘", action: #selector(addInGroup), keyEquivalent: "").target = self
            menu.addItem(withTitle: "从所有“\(group)”圆盘移除 \(format.name)", action: #selector(removeInGroup), keyEquivalent: "").target = self
        }
        return menu
    }
    @objc private func addEverywhere() { if let preferences { WheelOptions.setEverywhere(format.ext, included: true, preferences: preferences) } }
    @objc private func removeEverywhere() { if let preferences { WheelOptions.setEverywhere(format.ext, included: false, preferences: preferences) } }
    @objc private func addInGroup() { setInGroup(true) }
    @objc private func removeInGroup() { setInGroup(false) }
    private func setInGroup(_ included: Bool) {
        guard let preferences, let source = navigation?.source, let group = WheelOptions.group(for: source) else { return }
        WheelOptions.setEverywhere(format.ext, included: included, preferences: preferences, group: group)
    }
    private var start: NSPoint?
    private var session: NSDraggingSession?
    private var visible = true
    private var morphActive = false
    private var morphOverlay: DragMorphOverlay?
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil) }
    override func mouseUp(with event: NSEvent) { if start != nil { onClick?() }; start = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let start, session == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 4, let navigation else { return }
        self.start = nil
        navigation.beginDrag(format.ext, fromPalette: true)
        let item = NSDraggingItem(pasteboardWriter: ("orbit-wheel:" + navigation.source + ":" + format.ext) as NSString)
        item.setDraggingFrame(NSRect(x: point.x - 52, y: point.y - 24, width: 104, height: 48), contents: card())
        visible = true
        navigation.cardVisibility = { [weak self] show in self?.showCard(show) }
        navigation.morphImage = { [weak self] image, frame in
            guard let self, self.session != nil, let window = self.window,
                  let content = window.contentView else { return }
            // The native drag image has a mouse-relative offset. Resizing it
            // to the entire wheel changes that offset and makes it fly away.
            // Animate in one stable window coordinate space instead.
            let overlay = self.morphOverlay ?? DragMorphOverlay()
            if overlay.superview == nil { content.addSubview(overlay, positioned: .above, relativeTo: nil) }
            self.morphOverlay = overlay
            overlay.frame = content.convert(window.convertFromScreen(frame), from: nil)
            overlay.image = image
            overlay.needsDisplay = true
            // Only the hand-off needs a synchronous first frame. Subsequent
            // frames are coalesced with normal window drawing.
            if !self.morphActive { overlay.displayIfNeeded() }
            self.hideNativeCard()
            self.morphActive = true
        }
        session = beginDraggingSession(with: [item], event: event, source: self)
        session?.animatesToStartingPositionsOnCancelOrFail = false
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        self.session = nil
        morphOverlay?.removeFromSuperview(); morphOverlay = nil; morphActive = false
        if operation.isEmpty { navigation?.clearDrag() }
        navigation?.cardVisibility = nil
        navigation?.morphImage = nil
    }
    private func showCard(_ show: Bool) {
        guard show != visible || morphActive, let session else { return }
        morphOverlay?.removeFromSuperview(); morphOverlay = nil
        morphActive = false
        visible = show
        let image = show ? card() : nil
        session.enumerateDraggingItems(options: [], for: self, classes: [NSString.self], searchOptions: [:]) { item, _, _ in
            let point = self.convert(self.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
            item.setDraggingFrame(NSRect(x: point.x-52, y: point.y-24, width: 104, height: 48), contents: image)
        }
    }
    private func hideNativeCard() {
        guard visible, let session else { return }
        visible = false
        session.enumerateDraggingItems(options: [], for: self, classes: [NSString.self], searchOptions: [:]) { item, _, _ in
            item.setDraggingFrame(item.draggingFrame, contents: nil)
        }
    }
    private func card() -> NSImage {
        let title = format.name
        return NSImage(size: NSSize(width: 104, height: 48), flipped: false) { rect in
            NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 11.6, yRadius: 11.6).fill()
            let text = title as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.labelColor]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: (104-size.width)/2, y: (48-size.height)/2), withAttributes: attributes)
            return true
        }
    }
}

private final class DragMorphOverlay: NSView {
    var image: NSImage?
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { image?.draw(in: bounds) }
}
