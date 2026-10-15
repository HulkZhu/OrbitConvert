import AppKit

final class AirDropController: NSObject, NSSharingServiceDelegate {
    static let shared = AirDropController()
    private var service: NSSharingService?
    private var report: ((String) -> Void)?
    func send(_ files: [URL], report: @escaping (String) -> Void) {
        guard service == nil else { report("请先完成或关闭当前 AirDrop 分享窗口"); return }
        guard !files.isEmpty, files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }),
              let sharing = NSSharingService(named: .sendViaAirDrop), sharing.canPerform(withItems: files) else {
            report("当前文件或系统无法使用 AirDrop，请检查设备支持和系统设置。")
            return
        }
        self.report = report
        service = sharing
        sharing.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        report("请选择 AirDrop 接收人；尚未发送文件")
        sharing.perform(withItems: files)
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        report?("AirDrop 分享完成")
        service = nil; report = nil
    }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        report?("AirDrop 未完成：" + error.localizedDescription)
        service = nil; report = nil
    }
}
