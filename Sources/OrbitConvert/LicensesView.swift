import AppKit
import SwiftUI

enum LicenseCatalog {
    struct Document: Identifiable {
        let title: String
        let filename: String
        var id: String { filename }
    }
    static let documents: [Document] = [
        Document(title: "UnRAR · 解压许可", filename: "UNRAR_LICENSE.txt"),
        Document(title: "FLAC · BSD", filename: "FLAC_LICENSE.txt"),
        Document(title: "Ogg · BSD", filename: "OGG_LICENSE.txt"),
        Document(title: "LAME · LGPL（源码随包附带）", filename: "LAME_LICENSE.txt"),
        Document(title: "第三方组件与来源", filename: "THIRD_PARTY.md"),
        Document(title: "FileFlipper · MIT", filename: "FILEFLIPPER_LICENSE.txt"),
        Document(title: "WebP / SharpYUV · BSD", filename: "WEBP_LICENSE.txt"),
        Document(title: "WebP · 专利授权", filename: "WEBP_PATENTS.txt")
    ]
    static func contents(_ document: Document, bundle: Bundle = .main) throws -> String {
        guard let resource = bundle.resourceURL?.appendingPathComponent(document.filename),
              FileManager.default.fileExists(atPath: resource.path) else {
            throw OfficeEngine.error("缺少许可文件：\(document.filename)。请重新安装完整 App。")
        }
        return try String(contentsOf: resource, encoding: .utf8)
    }
}

final class LicensesWindowController {
    static let shared = LicensesWindowController()
    private var window: NSWindow?
    private let selection = LicenseSelection()
    func show() {
        if window == nil {
            let view = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 570),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            view.title = "OrbitConvert · 开源许可"
            view.isReleasedWhenClosed = false
            view.contentView = NSHostingView(rootView: LicensesView(selection: selection))
            view.minSize = NSSize(width: 580, height: 400)
            view.center(); window = view
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class LicenseSelection: ObservableObject {
    @Published var selected = LicenseCatalog.documents[0].id
}

struct LicensesView: View {
    @ObservedObject var selection: LicenseSelection
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("开源许可与致谢").font(.title2.bold())
            Text("感谢这些开源项目。以下文本随 App 离线提供；第三方代码保留原作者的权利和许可。").font(.callout).foregroundStyle(.secondary)
            Picker("组件", selection: $selection.selected) {
                ForEach(LicenseCatalog.documents) { item in Text(item.title).tag(item.id) }
            }
            Divider()
            ScrollView {
                let item = LicenseCatalog.documents.first { $0.id == selection.selected }!
                Text(content(item)).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }.background(Color(nsColor: .textBackgroundColor)).cornerRadius(8)
        }.padding(24).frame(minWidth: 530, minHeight: 330)
    }
    private func content(_ document: LicenseCatalog.Document) -> String {
        do { return try LicenseCatalog.contents(document) }
        catch { return error.localizedDescription }
    }
}
