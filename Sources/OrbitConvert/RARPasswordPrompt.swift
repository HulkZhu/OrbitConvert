import AppKit

enum RARPasswordPrompt {
    // Called by the background conversion worker, never the event-tap callback.
    static func extract(_ input: URL, progress: (String) -> Void) throws -> URL {
        var password: String?
        defer { password = nil }
        while true {
            do { return try RARExtractor.extract(input, password: password, progress: progress) }
            catch let error as RARPasswordError {
                if case .cancelled = error { throw error }
                progress("等待输入解压密码…")
                var answer: String?
                DispatchQueue.main.sync {
                    let alert = NSAlert()
                    alert.messageText = "输入 RAR 解压密码"
                    alert.informativeText = input.lastPathComponent + (password == nil ? "\n密码不会保存。" : "\n密码错误，或加密数据已损坏，请重试。")
                    alert.addButton(withTitle: "解压"); alert.addButton(withTitle: "取消")
                    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
                    field.placeholderString = "密码"
                    alert.accessoryView = field
                    let window = alert.window
                    window.initialFirstResponder = field
                    // A menu-bar app may be inactive or on another Space. Keep only
                    // this password prompt above ordinary windows and our progress panel.
                    window.level = .statusBar
                    window.hidesOnDeactivate = false
                    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                    defer { window.orderOut(nil) }
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty {
                        answer = field.stringValue
                    }
                    field.stringValue = ""
                }
                guard let answer else { throw RARPasswordError.cancelled }
                password = answer
            }
        }
    }
}
