import AppKit
import SwiftUI
import ApplicationServices
import ImageIO
import UniformTypeIdentifiers

struct Format: Identifiable {
    let name: String
    let ext: String
    let type: UTType
    var id: String { ext }
    static let all = [Format(name: "PNG", ext: "png", type: .png),
                      Format(name: "JPEG", ext: "jpg", type: .jpeg),
                      Format(name: "WebP", ext: "webp", type: .webP),
                      Format(name: "HEIC", ext: "heic", type: .heic),
                      Format(name: "PDF", ext: "pdf", type: .pdf),
                      Format(name: "DOCX", ext: "docx", type: UTType(filenameExtension: "docx")!),
                      Format(name: "TXT", ext: "txt", type: .plainText),
                      Format(name: "PPTX", ext: "pptx", type: UTType(filenameExtension: "pptx") ?? .data),
                      Format(name: "Excel", ext: "xlsx", type: UTType(filenameExtension: "xlsx") ?? .data),
                      Format(name: "TIFF", ext: "tiff", type: .tiff),
                      Format(name: "BMP", ext: "bmp", type: .bmp),
                      Format(name: "GIF", ext: "gif", type: .gif)] +
        [("MOV", "mov"), ("MP4", "mp4"), ("M4V", "m4v"), ("WAV", "wav"), ("MP3", "mp3"), ("FLAC", "flac"), ("AAC", "m4a"), ("ALAC", "alac"), ("AIFF", "aiff")].map {
            Format(name: $0.0, ext: $0.1, type: UTType(filenameExtension: $0.1 == "alac" ? "m4a" : $0.1) ?? .data)
        }
}

final class State: ObservableObject {
    @Published var message = "选择格式"
    @Published var busy = false
    @Published var hovered: Int? = nil
    @Published var stage = "读取文件…"
    @Published var fraction: Double? = nil
}

struct Glass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

enum WheelGeometry {
    static let inner = 78.0
    static let outer = 185.0
    static func index(dx: Double, dy: Double, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let radius = hypot(dx, dy)
        guard radius >= inner, radius <= outer * 1.06 else { return nil }
        let step = 2 * Double.pi / Double(count)
        let angle = (atan2(dy, dx) - Double.pi / 2 + step / 2 + 2 * Double.pi).truncatingRemainder(dividingBy: 2 * Double.pi)
        return min(count - 1, Int(angle / step))
    }
}


struct ConversionProgress: View {
    @ObservedObject var state: State
    let name: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(name).lineLimit(1).font(.system(size: 12, weight: .semibold))
            ProgressView(value: state.fraction).progressViewStyle(.linear)
            Text(state.stage).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(20).frame(width: 320, height: 110).background(Glass()).clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

enum FinderFile {
    static var failure = "未识别到点击的文件"
    static func selected() -> URL? {
        let files = selectedFiles()
        return files.count == 1 ? files.first : nil
    }
    static func selectedFiles() -> [URL] {
        var error: NSDictionary?
        let source = """
        tell application id "com.apple.finder"
            set pickedItems to (get selection)
            set pickedCount to count of pickedItems
            if pickedCount < 1 or pickedCount > 500 then return {}
            set paths to {}
            repeat with pickedItem in pickedItems
                set end of paths to POSIX path of (pickedItem as alias)
            end repeat
        end tell
        return paths
        """
        guard let script = NSAppleScript(source: source), script.compileAndReturnError(&error) else {
            failure = "Finder 脚本编译失败：\(error?.description ?? "无法创建脚本")"
            return []
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            failure = "Finder 读取错误：\(error.description)"
            return []
        }
        guard result.numberOfItems > 0, result.numberOfItems <= 500 else {
            failure = "请在 Finder 中选中 1–500 个同类型文件。"
            return []
        }
        return (1...result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0) }
    }
    static func namesIn(_ element: AXUIElement, depth: Int = 0) -> Set<String> {
        var names = Set<String>()
        for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
            if let value = attribute(element, key) as? String { names.insert(value) }
        }
        if depth < 3, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children.prefix(40) { names.formUnion(namesIn(child, depth: depth + 1)) }
        }
        return names
    }
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    static func at(_ point: CGPoint) -> URL? {
        failure = "未识别到文件；可先选中文件，再从菜单栏选择“转换选中的文件”"
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder" else { return nil }
        var names = Set<String>()
        for _ in 0..<7 {
            if let value = attribute(element, kAXURLAttribute) {
                if let url = value as? URL, url.isFileURL { return url }
                if let text = value as? String, let url = URL(string: text), url.isFileURL { return url }
            }
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            if [kAXWindowRole, kAXScrollAreaRole, kAXOutlineRole, kAXListRole, kAXApplicationRole].contains(role) { break }
            names.formUnion(namesIn(element))
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            element = unsafeBitCast(parent, to: AXUIElement.self)
        }
        // Never convert a stale selection unless its name matches the clicked AX element.
        return selectedFiles().first { url in
            let displayName = FileManager.default.displayName(atPath: url.path)
            return names.contains(url.lastPathComponent) || names.contains(displayName)
        }
    }
}

// Only lifecycle suspension may automatically reconnect. Faults always disarm it.
struct InputLifecycle {
    enum Pause: Hashable { case sleep, session }
    var pauses: Set<Pause> = []
    var resumePending = false
    mutating func suspend(_ reason: Pause, connected: Bool) {
        if pauses.isEmpty { resumePending = connected }
        pauses.insert(reason)
    }
    mutating func resume(_ reason: Pause) { pauses.remove(reason) }
    mutating func disarm() { resumePending = false }
    mutating func takeResume(trusted: Bool) -> Bool {
        guard trusted else { disarm(); return false }
        guard pauses.isEmpty, resumePending else { return false }
        resumePending = false
        return true
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!
    var tap: CFMachPort?
    var source: CFRunLoopSource?
    var panel: NSPanel?
    var state = State()
    var monitors: [Any] = []
    static let selectionTag: Int64 = 0x4F52424954
    var gesture = CapturedGesture()
    var ringGestureID: Int?
    var previewPanel: NSPanel?
    let fileLookup = DispatchQueue(label: "OrbitConvert.fileLookup", qos: .userInitiated)
    var activeFile: URL?
    var activeFiles: [URL] = []
    var activeFormats: [Format] = []
    var progressPanel: NSPanel?
    var permissionTimer: Timer?
    var listenerSuspended = false
    var inputLifecycle = InputLifecycle()
    var capturedAt: TimeInterval?
    var diagnostic: NSMenuItem!
    var listenerStatus: NSMenuItem!
    var settingsWindow: NSWindow?
    var pendingOpenFiles: [String]?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Preferences.shared.showDock ? .regular : .accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "OrbitConvert")
        status.button?.title = ""
        status.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.addItem(withTitle: "按设置的快捷键拖动，移到格式后松开", action: nil, keyEquivalent: "")
        diagnostic = menu.addItem(withTitle: "正在检查权限…", action: nil, keyEquivalent: "")
        listenerStatus = menu.addItem(withTitle: "鼠标监听：未连接", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "转换文件 / 解压选中的 RAR", action: #selector(convertSelected), keyEquivalent: "").target = self
        menu.addItem(withTitle: "启用辅助功能 / 重新连接", action: #selector(enable), keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 OrbitConvert", action: #selector(quit), keyEquivalent: "q").target = self
        status.menu = menu
        // Never interrupt a captured drag or a password dialog with onboarding.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard !self.state.busy, !self.gesture.ownsMouse, NSApp.modalWindow == nil else { return }
            timer.invalidate()
            RARDefaultApplication.askIfNeeded()
        }
        connect(prompt: false)
        permissionTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.inputLifecycle.resumePending && !AXIsProcessTrusted() {
                self.disconnectInput("辅助功能权限已撤销，请授权后手动重新连接")
            }
            if let tap = self.tap {
                if !AXIsProcessTrusted() || !CGEvent.tapIsEnabled(tap: tap) {
                    self.disconnectInput("权限已撤销或监听已停用，请授权后手动重新连接")
                } else if let start = self.capturedAt, ProcessInfo.processInfo.systemUptime - start > 30 {
                    self.disconnectInput("拖拽超时，已释放鼠标；请手动重新连接")
                }
            }
        }
        RunLoop.main.add(permissionTimer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(suspendInput), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(suspendInput), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resumeInput), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resumeInput), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            if event.type == .keyDown && event.keyCode != 53 { return }
            if event.type == .keyDown {
                self?.gesture.cancel()
                self?.clearGestureUI()
                return
            }
            if self?.gesture.ownsMouse != true { self?.panel?.orderOut(nil) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 {
                SettingsNavigation.shared.clearDrag()
                self?.gesture.cancel(); self?.clearGestureUI(); return nil
            }; return event
        }) { monitors.append(monitor) }
        if let files = pendingOpenFiles {
            pendingOpenFiles = nil
            application(NSApp, openFiles: files)
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func openLicenses() { SettingsNavigation.shared.tab = "开源许可"; openSettings() }
    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 824, height: 733), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "OrbitConvert 设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreferencesView(preferences: .shared))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func report(_ message: String) {
        diagnostic.title = message
        status.button?.toolTip = message
    }
    @objc func convertSelected() {
        guard !gesture.ownsMouse, !state.busy else { return }
        let files = FinderFile.selectedFiles()
        guard let file = files.first else { notice(FinderFile.failure); return }
        if files.count == 1 && file.pathExtension.lowercased() == "rar" { startExtraction(file) } else { show(files) }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard status != nil else { pendingOpenFiles = filenames; return }
        guard filenames.count == 1, let name = filenames.first, URL(fileURLWithPath: name).pathExtension.lowercased() == "rar", !state.busy else {
            notice("请一次打开一个 RAR 文件，并等待当前任务完成。")
            sender.reply(toOpenOrPrint: .failure); return
        }
        startExtraction(URL(fileURLWithPath: name)); sender.reply(toOpenOrPrint: .success)
    }
    func startExtraction(_ file: URL) {
        // Double-click remains direct; modifier-drag offers the radial action.
        startConversion(file, WheelOptions.extract)
    }
    func notice(_ message: String) {
        report(message)
        let floating = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        floating.isOpaque = false; floating.backgroundColor = .clear; floating.level = .popUpMenu
        floating.hidesOnDeactivate = false
        floating.contentView = NSHostingView(rootView: Text(message).font(.system(size: 13)).padding(18).frame(width: 340, height: 100).background(Glass()).clipShape(RoundedRectangle(cornerRadius: 18)))
        let mouse = NSEvent.mouseLocation
        let bounds = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!).visibleFrame
        floating.setFrameOrigin(NSPoint(x: min(max(mouse.x - 170, bounds.minX), bounds.maxX - 340), y: min(max(mouse.y - 110, bounds.minY), bounds.maxY - 100)))
        panel?.orderOut(nil); panel = floating; floating.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak floating] in floating?.orderOut(nil) }
    }
    @objc func enable() {
        guard inputLifecycle.pauses.isEmpty else { return }
        inputLifecycle.disarm()
        listenerSuspended = false
        connect(prompt: true)
    }
    @objc func suspendInput(_ notification: Notification) {
        let reason: InputLifecycle.Pause = notification.name == NSWorkspace.willSleepNotification ? .sleep : .session
        let connected = !listenerSuspended && tap.map { CGEvent.tapIsEnabled(tap: $0) } == true && AXIsProcessTrusted()
        inputLifecycle.suspend(reason, connected: connected)
        disconnectInput("会话已暂停，鼠标监听已释放；恢复会话后将检查权限并自动连接", lifecyclePause: true)
    }
    @objc func resumeInput(_ notification: Notification) {
        inputLifecycle.resume(notification.name == NSWorkspace.didWakeNotification ? .sleep : .session)
        guard inputLifecycle.resumePending else { return }
        guard AXIsProcessTrusted() else {
            disconnectInput("辅助功能权限不可用，请授权后手动重新连接")
            return
        }
        guard inputLifecycle.takeResume(trusted: true) else { return }
        clearGestureUI() // Never carry a captured gesture across a session boundary.
        connect(prompt: false)
    }
    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        disconnectInput("已退出")
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
    }
    func disconnectInput(_ reason: String, lifecyclePause: Bool = false) {
        if !lifecyclePause { inputLifecycle.disarm() }
        listenerSuspended = true
        gesture.abort()
        capturedAt = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes); CFRunLoopSourceInvalidate(source) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; source = nil
        // Never perform window/menu work inside the synchronous system input callback.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.listenerSuspended else { return }
            self.clearGestureUI()
            self.listenerStatus?.title = "鼠标监听：已安全停用"
            if self.diagnostic != nil { self.report(reason) }
        }
    }
    func inputMustPassThrough(systemDisabled: Bool, trusted: Bool) -> Bool {
        if listenerSuspended { return true }
        if systemDisabled || !trusted {
            disconnectInput("系统停用监听或辅助功能权限已撤销；已释放输入，请授权后手动重新连接")
            return true
        }
        return false
    }
    func connect(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            disconnectInput("辅助功能权限不可用，已释放鼠标")
            listenerStatus.title = "鼠标监听：缺少辅助功能权限"
            report("等待辅助功能权限，授权后请点击重新连接"); return
        }
        if let tap {
            if CGEvent.tapIsEnabled(tap: tap) { return }
            disconnectInput("已清理失效监听")
        }
        listenerSuspended = false
        let mask = [CGEventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .leftMouseDragged, .rightMouseDragged, .mouseMoved, .keyDown].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<Delegate>.fromOpaque(context).takeUnretainedValue()
            let disabled = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
            if owner.inputMustPassThrough(systemDisabled: disabled, trusted: disabled || owner.listenerSuspended ? false : AXIsProcessTrusted()) {
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown {
                if event.getIntegerValueField(.keyboardEventKeycode) == 53,
                   event.flags.contains([.maskControl, .maskAlternate, .maskCommand]) {
                    owner.disconnectInput("紧急释放已生效；请手动重新连接")
                }
                return Unmanaged.passUnretained(event)
            }
            if event.getIntegerValueField(.eventSourceUserData) == Delegate.selectionTag {
                return Unmanaged.passUnretained(event)
            }
            let point = event.location
            let down = type == .leftMouseDown || type == .rightMouseDown
            let moved = type == .leftMouseDragged || type == .rightMouseDragged || type == .mouseMoved
            let up = type == .leftMouseUp || type == .rightMouseUp
            if down {
                let held = event.flags.union(CGEventSource.flagsState(.combinedSessionState))
                let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
                let finder = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder"
                    || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
                guard Preferences.shared.matchesShortcut(held), finder, !owner.state.busy else {
                    return Unmanaged.passUnretained(event)
                }
                let id = owner.gesture.begin(point)
                owner.capturedAt = ProcessInfo.processInfo.systemUptime
                owner.activeFile = nil
                DispatchQueue.main.async { owner.prepareGesture(id: id, origin: point) }
                return nil // Finder never receives this physical down, drag or up.
            }
            if moved, owner.gesture.ownsMouse {
                owner.gesture.move(point)
                DispatchQueue.main.async { owner.updateGestureUI() }
                return nil
            }
            if up, owner.gesture.ownsMouse {
                let ending = owner.gesture.end(point)
                owner.capturedAt = nil
                DispatchQueue.main.async { owner.finishGesture(ending) }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            listenerStatus.title = "鼠标监听：创建失败"
            report("无法监听点击，请检查辅助功能权限后重新连接"); return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        listenerStatus.title = "鼠标监听：已连接，等待 ⌃⌥ 拖动"
        report("已就绪 · ⌃⌥ 拖动文件")
    }
    static func screenPoint(_ point: CGPoint) -> NSPoint {
        NSPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
    }
    func clearGestureUI() {
        panel?.orderOut(nil)
        previewPanel?.orderOut(nil)
        previewPanel = nil
        ringGestureID = nil
        activeFile = nil
        activeFiles = []
    }
    func prepareGesture(id: Int, origin: CGPoint) {
        guard gesture.accepts(id) else { return }
        clearGestureUI()
        listenerStatus.title = "鼠标监听：手势已接管，Finder 不接收拖放"
        resolveGesture(id: id, origin: origin, mayClick: true)
    }
    func resolveGesture(id: Int, origin: CGPoint, mayClick: Bool) {
        fileLookup.asyncAfter(deadline: .now() + (mayClick ? 0 : 0.12)) { [weak self] in
            let hit = FinderFile.at(origin)
            let selected = FinderFile.selectedFiles()
            let files: [URL]
            if let hit {
                files = selected.contains(where: { $0.standardizedFileURL == hit.standardizedFileURL }) ? selected : [hit]
            } else { files = [] }
            let failure = FinderFile.failure
            DispatchQueue.main.async {
                guard let self, self.gesture.accepts(id) else { return }
                if let file = files.first {
                    self.activeFile = file; self.activeFiles = files
                    self.updateGestureUI()
                } else if selected.count > 1 {
                    self.gesture.cancel()
                    self.notice("未能确认拖动的是已选文件。多选状态已保留，请从菜单栏启动批量转换。")
                } else if mayClick {
                    // Only fall back to a stationary click if AX cannot identify the
                    // target. Never collapse a verified existing multi-selection.
                    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                        let click = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: origin, mouseButton: .left)
                        click?.flags = []
                        click?.setIntegerValueField(.eventSourceUserData, value: Self.selectionTag)
                        click?.setIntegerValueField(.mouseEventClickState, value: 1)
                        click?.post(tap: .cgSessionEventTap)
                    }
                    self.resolveGesture(id: id, origin: origin, mayClick: false)
                } else {
                    self.gesture.cancel(); self.notice(failure)
                }
            }
        }
    }
    func updateGestureUI() {
        guard gesture.ownsMouse, gesture.moved, !gesture.cancelled, let file = activeFile else { return }
        if ringGestureID != gesture.id {
            show(activeFiles, at: Self.screenPoint(gesture.origin))
            guard panel?.contentView is RingView else { gesture.cancel(); return }
            ringGestureID = gesture.id
            panel?.ignoresMouseEvents = true
            let preview = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 160, height: 96), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            preview.isOpaque = false; preview.backgroundColor = .clear
            preview.hasShadow = false; preview.ignoresMouseEvents = true
            preview.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
            preview.hidesOnDeactivate = false
            preview.contentView = FilePreview(file: file, count: activeFiles.count)
            previewPanel = preview
        }
        guard let panel, let ring = panel.contentView as? RingView else { return }
        let mouse = Self.screenPoint(gesture.point)
        ring.update(at: ring.convert(panel.convertPoint(fromScreen: mouse), from: nil))
        previewPanel?.setFrameOrigin(NSPoint(x: mouse.x + 12, y: mouse.y - 94))
        previewPanel?.orderFrontRegardless()
    }
    func finishGesture(_ ending: CapturedGesture.End) {
        // No queued lookup or hover can reopen the wheel once the mouse is up.
        guard ending.id == gesture.id else { return }
        var selected: ([URL], Format)?
        if ending.commit, ringGestureID == ending.id,
           let panel, let ring = panel.contentView as? RingView {
            let point = Self.screenPoint(ending.point)
            let local = ring.convert(panel.convertPoint(fromScreen: point), from: nil)
            if let hit = ring.index(at: local) { selected = (activeFiles, ring.formats[hit]) }
        }
        clearGestureUI()
        if let selected { startConversions(selected.0, selected.1) }
        else { report("已取消 · 未创建文件") }
    }
    func startConversion(_ file: URL, _ format: Format) { startConversions([file], format) }
    func startConversions(_ files: [URL], _ format: Format) {
        guard !state.busy, let file = files.first else { return }
        previewPanel?.orderOut(nil)
        panel?.orderOut(nil)
        if format.ext == "airdrop" {
            AirDropController.shared.send(files) { [weak self] message in self?.report(message) }
            return
        }
        state.busy = true
        state.fraction = files.count > 1 ? 0 : nil
        state.stage = "准备转换…"
        let naming = Preferences.shared.filenameTemplate
        let trimWhitespace = Preferences.shared.trimWhitespace
        let allowExternalApps = Preferences.shared.allowExternalApps
        let current = state
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + (size >= 20_000_000 ? 0 : 0.6)) { [weak self] in
            guard let self, current.busy else { return }
            let popup = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 110), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            popup.isOpaque = false; popup.backgroundColor = .clear; popup.level = .floating
            popup.hidesOnDeactivate = false
            popup.contentView = NSHostingView(rootView: ConversionProgress(state: current, name: files.count > 1 ? "批量处理 \(files.count) 个文件" : file.lastPathComponent))
            popup.center(); popup.orderFrontRegardless(); self.progressPanel = popup
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<String, Error> = Result {
                if format.ext == "extract" {
                    guard files.allSatisfy({ $0.pathExtension.lowercased() == "rar" }) else { throw OfficeEngine.error("解压操作仅支持 RAR。") }
                    var completed = 0
                    for archive in files {
                        let output = try RARPasswordPrompt.extract(archive) { stage in
                            DispatchQueue.main.async { current.stage = archive.lastPathComponent + " · " + stage }
                        }
                        completed += 1
                        let fraction = Double(completed) / Double(files.count)
                        DispatchQueue.main.async { current.fraction = fraction }
                        if files.count == 1 { return "已解压：" + output.lastPathComponent }
                    }
                    return "已解压 \(completed) 个 RAR，保存到各原文件夹"
                }
                if files.count > 1 {
                    let outcome = try BatchConverter.run(files, format, naming: naming, trimWhitespace: trimWhitespace, allowExternalApps: allowExternalApps) { fraction, stage in
                        DispatchQueue.main.async { current.fraction = fraction; current.stage = stage }
                    }
                    if let failure = outcome.failures.first {
                        return "完成 \(outcome.outputs.count)/\(files.count) 个；失败 \(outcome.failures.count) 个。\(failure.input.lastPathComponent)：\(failure.message)"
                    }
                    return outcome.merged ? "已合并 \(files.count) 个文件为一个 PDF，保存到首个文件所在目录" : "已转换 \(files.count) 个文件，保存到各原文件夹"
                }
                let progress: (String) -> Void = { stage in DispatchQueue.main.async { current.stage = stage } }
                _ = try Converter.run(file, format, naming: naming, trimWhitespace: trimWhitespace, allowExternalApps: allowExternalApps, progress: progress)
                return "已保存到原文件夹"
            }
            DispatchQueue.main.async { [weak self] in
                current.busy = false
                self?.progressPanel?.orderOut(nil); self?.progressPanel = nil
                switch result {
                case .success(let message):
                    if message.contains("；失败") { self?.notice(message) } else { self?.report(message) }
                case .failure(RARPasswordError.cancelled): self?.report("已取消解压")
                case .failure(let error): self?.notice("转换失败：\(error.localizedDescription)")
                }
            }
        }
    }
    func show(_ file: URL, at anchor: NSPoint? = nil) { show([file], at: anchor) }
    func show(_ inputs: [URL], at anchor: NSPoint? = nil) {
        guard !state.busy, !inputs.isEmpty else { return }
        panel?.orderOut(nil)
        panel = nil
        let files: [URL]
        do { files = inputs.count > 1 ? try BatchConverter.selection(inputs) : inputs }
        catch { notice(error.localizedDescription); return }
        let file = files[0]
        let supported = BatchConverter.formats(files)
        let formats = WheelOptions.selected(file.pathExtension, preferences: .shared).filter { option in
            option.ext == "airdrop" || supported.contains { $0.ext == option.ext }
        }
        let sourceLabel = file.pathExtension.uppercased() + (files.count > 1 ? " ×\(files.count)" : "")
        guard !formats.isEmpty else { notice("此格式的圆盘为空，请在设置 → 功能中添加目标格式或 AirDrop。"); return }
        report(files.count > 1 ? "已选 \(files.count) 个文件 · 按文件名排序；图片选 PDF 将合并" : "已识别：\(file.lastPathComponent)")
        guard !formats.isEmpty else { return }
        activeFile = file; activeFiles = files; activeFormats = formats
        state = State()
        let floating = panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        floating.isOpaque = false
        floating.backgroundColor = .clear
        floating.hasShadow = false
        floating.level = .popUpMenu
        floating.hidesOnDeactivate = false
        floating.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        floating.ignoresMouseEvents = false
        floating.acceptsMouseMovedEvents = true
        let preferences = Preferences.shared
        let ring = RingView(file: file, formats: formats, original: sourceLabel, glassDensity: preferences.density, clearGlass: preferences.clearGlass, glassColor: preferences.glassColor, textScale: preferences.textScale, centerTextScale: preferences.centerTextScale) { [weak self] droppedFile, format in
            DispatchQueue.main.async { self?.startConversions(files, format) }
        }
        ring.feedbackEnabled = true
        floating.contentView = ring
        let mouse = anchor ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let bounds = screen.visibleFrame
        let size = preferences.diameter
        floating.setFrame(NSRect(x: min(max(mouse.x - size / 2, bounds.minX), bounds.maxX - size),
                                 y: min(max(mouse.y - size / 2, bounds.minY), bounds.maxY - size), width: size, height: size), display: true)
        ring.frame = NSRect(x: 0, y: 0, width: size, height: size)
        ring.bounds = NSRect(x: 0, y: 0, width: 440, height: 440)
        panel = floating
        floating.orderFrontRegardless()
    }
}

if CommandLine.arguments.contains("--license-self-test") {
    do {
        for document in LicenseCatalog.documents {
            let text = try LicenseCatalog.contents(document)
            guard !text.isEmpty else { throw OfficeEngine.error("许可为空：\(document.filename)") }
            print("PASS license: " + document.filename)
        }
        guard let icon = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns"),
              let source = CGImageSourceCreateWithURL(icon as CFURL, nil), CGImageSourceGetCount(source) > 0 else { throw OfficeEngine.error("App 图标缺失") }
        print("PASS bundled app icon"); exit(0)
    } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
}

if let index = CommandLine.arguments.firstIndex(of: "--batch"), CommandLine.arguments.count > index + 3 {
    do {
        guard let format = Format.all.first(where: { $0.ext == CommandLine.arguments[index + 1] }) else { throw OfficeEngine.error("未知输出格式") }
        let files = CommandLine.arguments.dropFirst(index + 2).map { URL(fileURLWithPath: $0) }
        let result = try BatchConverter.run(files, format, naming: "{name}-converted") { _, stage in print(stage) }
        for output in result.outputs { print("OUTPUT=" + output.path) }
        for failure in result.failures { print("FAILED=" + failure.input.lastPathComponent + ": " + failure.message) }
        exit(result.failures.isEmpty ? 0 : 2)
    } catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
}

if let index = CommandLine.arguments.firstIndex(of: "--extract-rar"), CommandLine.arguments.count > index + 1 {
    do {
        let password = CommandLine.arguments.contains("--rar-password-stdin") ? readLine() : nil
        print(try RARExtractor.extract(URL(fileURLWithPath: CommandLine.arguments[index + 1]), password: password) { print($0) }.path); exit(0)
    }
    catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
}

if let index = CommandLine.arguments.firstIndex(of: "--convert"), CommandLine.arguments.count > index + 2 {
    do {
        let source = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        guard let format = Format.all.first(where: { $0.ext == CommandLine.arguments[index + 2] }) else { throw OfficeEngine.error("未知输出格式") }
        let naming = CommandLine.arguments.count > index + 3 ? CommandLine.arguments[index + 3] : "{name}-converted"
        let output = try Converter.run(source, format, naming: naming, allowExternalApps: CommandLine.arguments.contains("--allow-apple-apps")) { print($0) }
        print("OUTPUT=" + output.path)
        exit(0)
    } catch { fputs("ERROR: \(error.localizedDescription)\n", stderr); exit(1) }
}

if let index = CommandLine.arguments.firstIndex(of: "--office-smoke-test"), CommandLine.arguments.count > index + 1 {
    let source = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let result = try Converter.run(source, OfficeEngine.pdf) { print($0) }
    print("ENGINE=installed Apple app (opt-in)")
    print("PDF=" + result.path)
    exit(0)
}

if CommandLine.arguments.contains("--render-settings") {
    if CommandLine.arguments.contains("--functions") { SettingsNavigation.shared.tab = "功能" }
    if CommandLine.arguments.contains("--licenses") { SettingsNavigation.shared.tab = "开源许可" }
    let view = NSHostingView(rootView: PreferencesView(preferences: .shared))
    view.frame = NSRect(x: 0, y: 0, width: 824, height: 733)
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(3) }
    try FileManager.default.createDirectory(atPath: "work", withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: "work/settings-preview.png"))
    exit(0)
}

if CommandLine.arguments.contains("--render-preview") {
    let purple = CommandLine.arguments.contains("--purple")
    let view = RingView(file: URL(fileURLWithPath: "/tmp/sample.jpg"), formats: Format.all.filter { $0.type != .jpeg }, original: "JPG", glassColor: purple ? NSColor(srgbRed: 0.55, green: 0.12, blue: 0.85, alpha: 1) : .white, textScale: purple ? 1.6 : 1) { _, _ in }
    view.frame = NSRect(x: 0, y: 0, width: 440, height: 440)
    view.hovered = 2
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(3) }
    precondition((rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.01)
    try FileManager.default.createDirectory(atPath: "work", withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: "work/orbit-preview.png"))
    print("Rendered work/orbit-preview.png; transparent corner verified. Native glass requires live WindowServer compositing; this is a geometry preview.")
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--write-bridge-test-scripts"), CommandLine.arguments.count > index + 1 {
    let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (app, ext, target, format) in [
        ("com.apple.iWork.Pages", "pages", "docx", "Microsoft Word"),
        ("com.apple.iWork.Numbers", "numbers", "xlsx", "Microsoft Excel"),
        ("com.apple.iWork.Keynote", "key", "pptx", "Microsoft PowerPoint")] {
        let appPath = "/Applications/" + app.components(separatedBy: ".").last! + ".app"
        let script = OfficeEngine.script(app: appPath, input: folder.appendingPathComponent("test input.\(ext)"), output: folder.appendingPathComponent("output.\(target)"), format: format)
        try script.write(to: folder.appendingPathComponent("\(ext)-\(target).applescript"), atomically: true, encoding: .utf8)
    }
    exit(0)
}

if CommandLine.arguments.contains("--input-safety-self-test") {
    for capturing in [false, true] {
        for fault in ["permission", "timeout", "userDisabled"] {
            let owner = Delegate()
            var token = owner.gesture.id
            if capturing { token = owner.gesture.begin(.zero); owner.gesture.move(CGPoint(x: 40, y: 30)) }
            precondition(owner.inputMustPassThrough(systemDisabled: fault != "permission", trusted: fault != "permission"))
            precondition(owner.listenerSuspended && owner.tap == nil && owner.source == nil)
            precondition(!owner.gesture.ownsMouse && !owner.gesture.accepts(token))
            precondition(!owner.gesture.end(.zero).commit)
            for _ in 0..<100 { precondition(owner.inputMustPassThrough(systemDisabled: false, trusted: true)) }
            precondition(owner.listenerSuspended) // Restoring permission does not rearm automatically.
        }
    }
    let owner = Delegate()
    precondition(!owner.inputMustPassThrough(systemDisabled: false, trusted: true))
    let token = owner.gesture.begin(.zero)
    owner.suspendInput(Notification(name: NSWorkspace.willSleepNotification))
    precondition(owner.inputMustPassThrough(systemDisabled: false, trusted: true))
    precondition(!owner.gesture.accepts(token) && !owner.gesture.ownsMouse)
    for first in [InputLifecycle.Pause.sleep, .session] {
        let second: InputLifecycle.Pause = first == .sleep ? .session : .sleep
        var lifecycle = InputLifecycle()
        lifecycle.suspend(first, connected: true)
        lifecycle.suspend(first, connected: false) // Duplicate notifications retain intent.
        lifecycle.suspend(second, connected: false)
        lifecycle.resume(first)
        precondition(!lifecycle.takeResume(trusted: true))
        lifecycle.resume(second)
        precondition(lifecycle.takeResume(trusted: true))
        precondition(!lifecycle.takeResume(trusted: true))
        lifecycle.suspend(first, connected: true)
        precondition(!lifecycle.takeResume(trusted: false))
        lifecycle.resume(first)
        precondition(!lifecycle.takeResume(trusted: true))
        lifecycle.suspend(first, connected: false)
        lifecycle.resume(first)
        precondition(!lifecycle.takeResume(trusted: true))
        lifecycle.suspend(first, connected: true)
        lifecycle.disarm()
        lifecycle.resume(first)
        precondition(!lifecycle.takeResume(trusted: true))
    }
    print("PASS: lifecycle resume waits for both wake/session activation, reconnects once, and never rearms after permission loss or faults")
    print("PASS: idle and active permission loss / timeout / user-disabled faults release ownership, invalidate queued work, pass subsequent input and never automatically rearm; session suspension")
    exit(0)
}

if CommandLine.arguments.contains("--editor-self-test") {
    let domain = "OrbitConvert.EditorTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    let preferences = Preferences(defaults: defaults)
    let navigation = SettingsNavigation()
    let original = WheelOptions.selected("png", preferences: preferences).map(\.ext)
    precondition(WheelOptions.candidates("png").count == 9)
    let view = FunctionSettings(preferences: preferences, navigation: navigation)
    precondition(view.candidateRows.map(\.count) == [5, 4])
    navigation.beginDrag("bmp")
    navigation.preview(CGPoint(x: 170, y: 25), preferences: preferences)
    precondition(navigation.previewIDs?[1] == "bmp")
    precondition(navigation.previewIDs?.count == original.count + 1)
    precondition(WheelOptions.selected("png", preferences: preferences).map(\.ext) == original)
    navigation.preview(CGPoint(x: 170, y: 310), preferences: preferences)
    precondition(navigation.previewIDs?.first != "bmp")
    navigation.clearDrag()
    precondition(navigation.previewIDs == nil && preferences.wheelLayouts.isEmpty)
    navigation.beginDrag("jpg")
    navigation.preview(CGPoint(x: 170, y: 25), preferences: preferences)
    precondition(navigation.previewIDs?.count == original.count)
    let top = original[0]
    let count = original.count
    for destination in 0..<count {
        navigation.beginDrag(top)
        let angle = Double(destination) * 2 * .pi / Double(count) + .pi / 2
        navigation.preview(CGPoint(x: 170 + 110*cos(angle), y: 170 - 110*sin(angle)), preferences: preferences)
        precondition(navigation.previewIDs?.count == original.count)
        let remaining = navigation.previewIDs!.filter { $0 != top }
        let expected = original.filter { $0 != top }
        let anchor = remaining.firstIndex(of: expected[0])!
        precondition(Array(remaining[anchor...] + remaining[..<anchor]) == expected, "Insertion must preserve circular order of all other items")
    }
    precondition(WheelOptions.selected("png", preferences: preferences).map(\.ext) == original)
    preferences.wheelLayouts["png"] = ["jpg", "webp", "heic", "gif"]
    navigation.beginDrag("jpg")
    let gapAngle = 2.5 * 2 * Double.pi / 4 + .pi / 2
    navigation.preview(CGPoint(x: 170 + 110*cos(gapAngle), y: 170 - 110*sin(gapAngle)), preferences: preferences)
    precondition(navigation.previewIDs == ["webp", "heic", "jpg", "gif"], "1234 inserting 1 between 3 and 4 must become 2314")
    navigation.beginDrag("jpg")
    navigation.preview(CGPoint(x: 280, y: 170), preferences: preferences)
    precondition(navigation.previewIDs == ["gif", "webp", "heic", "jpg"], "First clockwise neighbour moves one slot only")
    navigation.preview(CGPoint(x: 175, y: 60), preferences: preferences)
    precondition(navigation.previewIDs == ["jpg", "webp", "heic", "gif"], "Crossing the top seam inside the original slot must not rotate")
    preferences.wheelLayouts["png"] = ["jpg", "webp", "heic", "gif", "bmp", "tiff"]
    navigation.beginDrag("tiff")
    let seamGap = Double.pi / 2 + Double.pi / 6
    navigation.preview(CGPoint(x: 170 + 110*cos(seamGap), y: 170 - 110*sin(seamGap)), preferences: preferences)
    precondition(navigation.previewIDs == ["tiff", "webp", "heic", "gif", "bmp", "jpg"], "123456 inserting 6 between 1/2 must anchor 2 and become 623451")
    for n in 3...12 {
        let ids = (0..<n).map(String.init)
        let step = 2 * Double.pi / Double(n)
        for start in 0..<n {
            for direction in [-1, 1] {
                let next = (start + direction + n) % n
                var expected = ids
                expected.swapAt(start, next)
                let result = WheelReorder.move(ids, id: ids[start], angle: Double(next)*step)
                precondition(result == expected, "Every first neighbour, both directions, must leave all other slots fixed")
                precondition(WheelReorder.move(result, id: ids[start], angle: Double(start)*step) == ids)
                precondition(WheelReorder.move(ids, id: ids[start], angle: (Double(start)+Double(direction)*0.4)*step) == ids)
            }
        }
    }
    preferences.wheelLayouts.removeValue(forKey: "png")
    navigation.source = "pdf"
    precondition(navigation.previewIDs == nil && navigation.draggedID == nil)
    for ext in ["png", "jpg", "jpeg", "webp", "heic", "heif", "gif", "bmp", "tiff", "tif", "svg"] {
        let targets = Converter.formats(for: URL(fileURLWithPath: "/source." + ext)).map(\.ext)
        precondition(targets.contains("docx") && !targets.contains("txt"))
    }
    preferences.hapticMode = 3
    precondition(Preferences(defaults: defaults).hapticMode == 3)
    let a = SectorGeometry.sector(0, count: 7, expansion: 0).boundingBox
    let b = SectorGeometry.sector(0, count: 7, expansion: 0.5).boundingBox
    let c = SectorGeometry.sector(0, count: 7, expansion: 1).boundingBox
    precondition(a.height < b.height && b.height < c.height)
    defaults.removePersistentDomain(forName: domain)
    print("PASS: 5+4 rows, live preview before commit, reorder without duplication, cancellation/source reset, restored image DOCX targets, persisted haptic mode, intermediate hover geometry")
    exit(0)
}

if CommandLine.arguments.contains("--wheel-self-test") {
    let domain = "OrbitConvert.WheelTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: domain)!
    let preferences = Preferences(defaults: defaults)
    for source in WheelOptions.sources {
        let supported = Set(Converter.formats(for: URL(fileURLWithPath: "/test." + source)).map(\.ext))
        let expected = Converter.defaultFormats(for: URL(fileURLWithPath: "/test." + source)).map(\.ext).filter { supported.contains($0) } + ["airdrop"]
        precondition(WheelOptions.selected(source, preferences: preferences).map(\.ext) == expected)
    }
    preferences.wheelLayouts["jpg"] = ["pdf", "png", "pdf", "unsupported", "airdrop"]
    precondition(WheelOptions.selected("jpeg", preferences: preferences).map(\.ext) == ["pdf", "png", "airdrop"])
    WheelOptions.move("airdrop", source: "jpeg", index: 0, preferences: preferences)
    precondition(WheelOptions.selected("jpg", preferences: preferences).map(\.ext) == ["airdrop", "pdf", "png"])
    defaults.set(false, forKey: "airDropEnabled")
    precondition(WheelOptions.selected("jpg", preferences: Preferences(defaults: defaults)).first?.ext == "airdrop")
    precondition(WheelOptions.selected("jpg", preferences: preferences).first?.ext == "airdrop")
    preferences.wheelLayouts["png"] = []
    precondition(WheelOptions.selected("png", preferences: preferences).isEmpty)
    WheelOptions.move("png", source: "png", index: 0, preferences: preferences)
    precondition(WheelOptions.selected("png", preferences: preferences).isEmpty)
    WheelOptions.move("pdf", source: "png", index: 999, preferences: preferences)
    precondition(WheelOptions.selected("png", preferences: preferences).map(\.ext) == ["pdf"])
    let reloaded = Preferences(defaults: defaults)
    precondition(reloaded.wheelLayouts == preferences.wheelLayouts)
    precondition(!Converter.formats(for: URL(fileURLWithPath: "/test.png")).contains { $0.ext == "airdrop" })
    let rasterFormats = ["png", "jpg", "webp", "heic", "gif", "bmp", "tiff"]
    for source in rasterFormats {
        let targets = Set(Converter.formats(for: URL(fileURLWithPath: "/test." + source)).map(\.ext))
        precondition(Set(rasterFormats.filter { $0 != source }).isSubset(of: targets))
    }
    WheelOptions.move("bmp", source: "png", index: 0, preferences: preferences)
    precondition(WheelOptions.selected("png", preferences: preferences).first?.ext == "bmp")
    WheelOptions.setEverywhere("png", included: true, preferences: preferences)
    for source in WheelOptions.sources {
        let supported = WheelOptions.candidates(source).contains { $0.ext == "png" }
        precondition(WheelOptions.selected(source, preferences: preferences).contains { $0.ext == "png" } == supported)
    }
    WheelOptions.setEverywhere("png", included: true, preferences: preferences)
    precondition(WheelOptions.selected("dng", preferences: preferences).filter { $0.ext == "png" }.count == 1)
    WheelOptions.setEverywhere("png", included: false, preferences: preferences)
    precondition(WheelOptions.sources.allSatisfy { source in !WheelOptions.selected(source, preferences: preferences).contains { $0.ext == "png" } })
    WheelOptions.setEverywhere("airdrop", included: false, preferences: preferences)
    precondition(WheelOptions.sources.allSatisfy { source in !WheelOptions.selected(source, preferences: preferences).contains { $0.ext == "airdrop" } })
    precondition(WheelOptions.selected("rar", preferences: preferences).map(\.ext) == ["extract"])
    precondition(WheelOptions.groups.flatMap(\.sources).count == Set(WheelOptions.sources).count)
    for source in RAWDecoder.extensions {
        precondition(Set(Converter.formats(for: URL(fileURLWithPath: "/source." + source)).map(\.ext)) == Set(RAWDecoder.targets))
    }
    precondition(Preferences(defaults: defaults).wheelLayouts == preferences.wheelLayouts)
    let beforeGroup = preferences.wheelLayouts
    WheelOptions.setEverywhere("heic", included: true, preferences: preferences, group: "文档")
    for source in WheelOptions.sources {
        if WheelOptions.group(for: source) == "文档" {
            precondition(WheelOptions.selected(source, preferences: preferences).contains { $0.ext == "heic" })
        } else { precondition(preferences.wheelLayouts[source] == beforeGroup[source]) }
    }
    WheelOptions.setEverywhere("heic", included: false, preferences: preferences, group: "文档")
    for source in WheelOptions.sources {
        if WheelOptions.group(for: source) == "文档" {
            precondition(!WheelOptions.selected(source, preferences: preferences).contains { $0.ext == "heic" })
        } else { precondition(preferences.wheelLayouts[source] == beforeGroup[source]) }
    }
    precondition(WheelOptions.group(for: "jpeg") == "照片")
    precondition(WheelOptions.group(for: "文档") == nil)
    print("PASS category-scoped add/remove preserves other categories and resolves aliases")
    print("PASS RAW target mapping, grouped sources, RAR radial extraction, global add/remove persistence and deduplication")
    for count in 1...8 {
        for index in 0..<count {
            let angle = Double(index) * 2 * .pi / Double(count) + .pi / 2
            let point = CGPoint(x: 220 + 134*cos(angle), y: 220 + 134*sin(angle))
            precondition(SectorGeometry.sector(index, count: count).contains(point))
        }
    }
    defaults.removePersistentDomain(forName: domain)
    print("PASS: all sources, aliases, order, dedup, invalid targets, empty layout, persistence, AirDrop toggle and sector hit geometry")
    exit(0)
}

if CommandLine.arguments.contains("--self-test") {
    for path in ["../escape", "/absolute", "C:\\escape", "a/../../b", "a\\..\\b", "a/./b", "bad\u{0000}name"] {
        precondition((try? RARExtractor.safePath(path)) == nil, path)
    }
    precondition((try? RARExtractor.safePath("中文/文件.txt")) == "中文/文件.txt")
    precondition(!XMLSafety.valid(Data("<!DOCTYPE r [<!ENTITY a 'danger'>]><r>&a;</r>".utf8)))
    precondition(!XMLSafety.valid(Data((String(repeating: "<r>", count: 70) + String(repeating: "</r>", count: 70)).utf8)))
    for ext in ["docx", "pptx", "xlsx", "xls", "pdf"] { precondition(OfficeEngine.route(ext) == nil) }
    print("PASS: unsafe archive paths and XML entities/depth rejected; non-Apple routes cannot invoke Apple apps")
    let matrix = ["pdf": ["jpg", "png", "docx", "txt"],
                  "pptx": ["docx", "pdf", "jpg", "png"],
                  "docx": ["png", "jpg", "txt", "pdf", "webp"],
                  "txt": ["docx"], "xlsx": ["png", "jpg", "pdf"],
                  "key": ["pptx"], "numbers": ["xlsx"], "pages": ["docx"]]
    for (ext, expected) in matrix {
        precondition(Converter.defaultFormats(for: URL(fileURLWithPath: "/test." + ext)).map(\.ext) == expected)
    }
    for ext in ["png", "jpg", "webp", "heic", "bmp", "tiff"] {
        let formats = Converter.defaultFormats(for: URL(fileURLWithPath: "/test." + ext)).map(\.ext)
        precondition(!formats.contains("txt") && !formats.contains("bmp") && !formats.contains("tiff"))
    }

    func straightEdges(_ path: CGPath) -> [(CGPoint, CGPoint)] {
        var previous = CGPoint.zero
        var lines: [(CGPoint, CGPoint)] = []
        path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint: previous = element.pointee.points[0]
            case .addLineToPoint:
                lines.append((previous, element.pointee.points[0])); previous = element.pointee.points[0]
            case .addQuadCurveToPoint: previous = element.pointee.points[1]
            case .addCurveToPoint: previous = element.pointee.points[2]
            case .closeSubpath: break
            @unknown default: break
            }
        }
        return lines.filter { hypot($0.1.x - $0.0.x, $0.1.y - $0.0.y) > 30 }
    }
    var capture = CapturedGesture()
    let first = capture.begin(CGPoint(x: 50, y: 50))
    precondition(capture.ownsMouse && capture.accepts(first))
    capture.move(CGPoint(x: 53, y: 50))
    precondition(!capture.moved)
    capture.move(CGPoint(x: 80, y: 60))
    precondition(capture.moved && capture.ownsMouse)
    let release = capture.end(CGPoint(x: 85, y: 65))
    precondition(release.commit && release.point == CGPoint(x: 85, y: 65))
    precondition(!capture.accepts(first) && !capture.ownsMouse)
    let second = capture.begin(.zero)
    precondition(!capture.accepts(first))
    capture.move(CGPoint(x: 120, y: 0)); capture.cancel()
    precondition(capture.ownsMouse && !capture.accepts(second))
    precondition(!capture.end(.zero).commit)
    _ = capture.begin(.zero)
    precondition(!capture.end(.zero).commit)
    // Every rendered sector centre must hit its own label; transparent gaps and
    // rounded corners must not secretly select a neighbouring format.
    for count in 1...10 {
        struct Probe {
            let count: Int
            func sector(_ index: Int) -> CGPath { SectorGeometry.sector(index, count: count) }
            func index(at point: CGPoint) -> Int? { (0..<count).first { sector($0).contains(point) } }
        }
        let ring = Probe(count: count)
        for index in 0..<count {
            let edge = straightEdges(ring.sector(index))[0]
            let adjacent = straightEdges(ring.sector((index + 1) % count))[1]
            let dx = edge.1.x - edge.0.x, dy = edge.1.y - edge.0.y
            let ax = adjacent.1.x - adjacent.0.x, ay = adjacent.1.y - adjacent.0.y
            precondition(abs(dx * ay - dy * ax) < 0.0001)
            let distance = abs(dx * (adjacent.0.y - edge.0.y) - dy * (adjacent.0.x - edge.0.x)) / hypot(dx, dy)
            precondition(abs(distance - 10) < 0.0001)
            let angle = Double(index) * 2 * Double.pi / Double(count) + .pi / 2
            precondition(ring.index(at: NSPoint(x: 220 + cos(angle) * 134, y: 220 + sin(angle) * 134)) == index)
            let boundary = angle + .pi / Double(count)
            precondition(ring.index(at: NSPoint(x: 220 + cos(boundary) * 134, y: 220 + sin(boundary) * 134)) == nil)
        }
        precondition(ring.index(at: NSPoint(x: 220, y: 220)) == nil)
        precondition(ring.index(at: .zero) == nil)
        for size in [240.0, 300.0, 440.0] {
            let point = NSPoint(x: (size / 2) * 440 / size, y: ((220 + 134) * size / 440) * 440 / size)
            precondition(ring.index(at: point) == 0)
        }
    }
    for count in 1...10 {
        for index in 0..<count {
            let angle = Double(index) * 2 * Double.pi / Double(count) + Double.pi / 2
            precondition(WheelGeometry.index(dx: cos(angle) * 100, dy: sin(angle) * 100, count: count) == index)
        }
        precondition(WheelGeometry.index(dx: 0, dy: 0, count: count) == nil)
        precondition(WheelGeometry.index(dx: 200, dy: 0, count: count) == nil)
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let fixture = folder.appendingPathComponent("source.png")
    let context = CGContext(data: nil, width: 16, height: 12, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(fixture as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
    let before = try Data(contentsOf: fixture)
    var phases: [String] = []
    let legacy = Format.all.filter { ["png", "jpg", "tiff", "bmp", "gif"].contains($0.ext) }
    for format in legacy {
        let output = try Converter.run(fixture, format) { phases.append($0) }
        let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
        let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        precondition(decoded.width == 16 && decoded.height == 12)
        let another = try Converter.run(fixture, format)
        precondition(another != output)
    }
    let after = try Data(contentsOf: fixture)
    precondition(before == after && !phases.isEmpty)
    let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    precondition(files.count == 11) // one source + exactly ten requested conversions
    let pdfURL = folder.appendingPathComponent("two-pages.pdf")
    var pageBox = CGRect(x: 0, y: 0, width: 400, height: 300)
    let pdf = CGContext(pdfURL as CFURL, mediaBox: &pageBox, nil)!
    for _ in 0..<2 {
        pdf.beginPDFPage(nil); pdf.setFillColor(CGColor(srgbRed: 0.8, green: 0.1, blue: 0.2, alpha: 1)); pdf.fill(pageBox); pdf.endPDFPage()
    }
    pdf.closePDF()
    let pages = try Converter.rasterPages(pdfURL, workspace: folder, progress: { _ in })
    precondition(pages.count == 2)
    for i in 0..<pages.count {
        let rendered = try pages.load(i)
        precondition(rendered.width == 800 && rendered.height == 600)
        let pixels = try Converter.bitmap(800, 600)
        pixels.draw(rendered, in: CGRect(x: 0, y: 0, width: 800, height: 600))
        let bytes = pixels.data!.assumingMemoryBound(to: UInt8.self)
        for (x, y) in [(2, 2), (797, 2), (2, 597), (797, 597), (400, 300)] {
            let offset = y * pixels.bytesPerRow + x * 4
            precondition(bytes[offset] > 190 && bytes[offset + 1] < 40, "PDF was centered without scaling")
        }
    }
    let croppedContext = try Converter.bitmap(400, 300, white: true)
    croppedContext.setFillColor(CGColor(gray: 0, alpha: 1))
    croppedContext.fill(CGRect(x: 150, y: 100, width: 100, height: 100))
    let cropped = Converter.trimWhiteBorder(croppedContext.makeImage()!)
    precondition(cropped.width == 116 && cropped.height == 116)
    print("PASS: exact format matrix; two-page PDF 2x scale covers corners; optional whitespace crop")
    print("PASS: capture/release/cancel and stale lookup exclusion; rounded sector/label/gap hit testing; five formats; exactly ten outputs from ten requests; source unchanged")
    exit(0)
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.run()
