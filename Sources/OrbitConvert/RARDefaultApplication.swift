import AppKit
import UniformTypeIdentifiers

enum RARDefaultApplication {
    static let askedKey = "didAskForRARDefaultApplication"
    static func askIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: askedKey) else { return }
        defaults.set(true, forKey: askedKey)
        let alert = NSAlert()
        alert.messageText = "用 OrbitConvert 默认打开 RAR？"
        alert.informativeText = "设置后，双击 RAR 即可解压；加密文件会询问密码。选择“暂不设置”不会更改当前默认应用。建议先将 OrbitConvert 移到“应用程序”文件夹。"
        alert.addButton(withTitle: "设为默认"); alert.addButton(withTitle: "暂不设置")
        alert.window.level = .statusBar
        alert.window.hidesOnDeactivate = false
        alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        alert.window.orderOut(nil)
        guard response == .alertFirstButtonReturn else { return }
        let type = UTType(filenameExtension: "rar") ?? UTType(importedAs: "com.rarlab.rar-archive")
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
            guard let error else { return }
            DispatchQueue.main.async {
                let failure = NSAlert()
                failure.messageText = "未能设置 RAR 默认打开方式"
                failure.informativeText = error.localizedDescription + "\n可在 Finder 中选中 RAR → 显示简介 → 打开方式，选择 OrbitConvert 并点击“全部更改”。"
                failure.runModal()
            }
        }
    }
}
