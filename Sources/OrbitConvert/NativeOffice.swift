import AppKit
import ImageIO

/// Native OOXML conversion. No automation of Office/iWork and no office runtime.
enum NativeOffice {
    static func pdf(_ input: URL, in workspace: URL, progress: (String) -> Void) throws -> URL {
        let output = workspace.appendingPathComponent("native-document.pdf")
        progress("本地排版文档…")
        switch input.pathExtension.lowercased() {
        case "docx": try documentPDF(input, to: output)
        case "pptx": _ = try PresentationConverter.toPDF(input, to: output)
        case "xlsx": _ = try SpreadsheetConverter.toPDF(input, to: output)
        case "xls": throw OfficeEngine.error("暂不支持旧版 XLS 二进制格式；请先另存为 XLSX。不会启动外部应用。")
        default: throw OfficeEngine.error("不支持此文档格式。")
        }
        return output
    }

    private static func documentPDF(_ input: URL, to output: URL) throws {
        // Validate bounded package/XML before handing it to the system text importer.
        let package = try ZipArchive(url: input)
        for name in package.paths where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
            guard let data = package.data(at: name), XMLSafety.valid(data) else { throw OfficeEngine.error("DOCX XML 无效或过于复杂。") }
            // No external resources are fetched by this converter.
            if name.hasSuffix(".rels"), let root = OfficePackage.xml(package, name),
               root.children("Relationship").contains(where: { $0.attr("TargetMode") == "External" && !($0.attr("Type") ?? "").hasSuffix("/hyperlink") }) {
                throw OfficeEngine.error("DOCX 含外部链接资源；请先把图片等资源嵌入文档。")
            }
        }
        guard let root = OfficePackage.xml(package, "word/document.xml") else { throw OfficeEngine.error("DOCX 缺少正文。") }
        let section = root.child("body")?.child("sectPr")
        func points(_ element: XMLElement?, _ key: String, _ fallback: CGFloat) -> CGFloat {
            guard let v = element?.attr(key).flatMap(Double.init), v.isFinite, v >= 0 else { return fallback }
            return CGFloat(v) / 20
        }
        let paper = CGSize(width: points(section?.child("pgSz"), "w", 595), height: points(section?.child("pgSz"), "h", 842))
        let margins = section?.child("pgMar")
        let left = points(margins, "left", 48), right = points(margins, "right", 48)
        let top = points(margins, "top", 48), bottom = points(margins, "bottom", 48)
        let content = CGSize(width: paper.width - left - right, height: paper.height - top - bottom)
        guard paper.width <= 14400, paper.height <= 14400, content.width > 20, content.height > 20 else { throw OfficeEngine.error("DOCX 页面尺寸或页边距无效。") }
        // Cocoa's DOCX importer drops DrawingML pictures. Substitute temporary text
        // markers before importing, then replace those markers with real attachments.
        // This retains Cocoa's text/table formatting without silently losing pictures.
        let relationships = OfficePackage.relationships(package, for: "word/document.xml")
        var attachments: [(String, NSTextAttachment)] = []
        for drawing in root.descendants("drawing") {
            guard let id = drawing.descendant("blip")?.attr("embed"), let path = relationships[id]?.target,
                  let bytes = package.data(at: path), let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Double,
                  let height = properties[kCGImagePropertyPixelHeight] as? Double,
                  width > 0, height > 0, width * height <= 40_000_000,
                  let image = NSImage(data: bytes), let parent = drawing.parent as? XMLElement else {
                throw OfficeEngine.error("DOCX 含无法读取的内嵌图片（或链接图片）。")
            }
            let extent = drawing.descendant("extent")
            var w = (extent?.attr("cx").flatMap(Double.init) ?? (width * 12700)) / 12700
            var h = (extent?.attr("cy").flatMap(Double.init) ?? (height * 12700)) / 12700
            guard w.isFinite, h.isFinite, w > 0, h > 0 else { throw OfficeEngine.error("DOCX 图片尺寸无效。") }
            let scale = min(1, Double(content.width) / w, Double(content.height - 20) / h)
            w *= scale; h *= scale; image.size = NSSize(width: w, height: h)
            let attachment = NSTextAttachment()
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
            let marker = "ORBITIMAGE" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            parent.replaceChild(at: drawing.index, with: XMLElement(name: "w:t", stringValue: marker))
            attachments.append((marker, attachment))
        }
        let importURL = output.deletingLastPathComponent().appendingPathComponent("import.docx")
        if !attachments.isEmpty {
            let document = Data(root.xmlString.utf8)
            try ZipArchive.write(package.paths.sorted().compactMap { name in
                package.data(at: name).map { (name, name == "word/document.xml" ? document : $0) }
            }, to: importURL)
        }
        let data = try Data(contentsOf: attachments.isEmpty ? input : importURL)
        let importText = { try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil) }
        let text = try Thread.isMainThread ? importText() : DispatchQueue.main.sync(execute: importText)
        guard text.length <= 2_000_000 else { throw OfficeEngine.error("DOCX 文字超过安全上限。") }
        let storage = NSTextStorage(attributedString: text.length > 0 ? text : NSAttributedString(string: " "))
        for (marker, attachment) in attachments {
            let range = (storage.string as NSString).range(of: marker)
            guard range.location != NSNotFound else { throw OfficeEngine.error("DOCX 图片定位失败，未保存不完整结果。") }
            storage.replaceCharacters(in: range, with: NSAttributedString(attachment: attachment))
        }
        let layout = NSLayoutManager()
        layout.usesFontLeading = true; storage.addLayoutManager(layout)
        var box = CGRect(origin: .zero, size: paper)
        guard let context = CGContext(output as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        defer { context.closePDF() }
        var end = 0, pages = 0
        repeat {
            pages += 1
            guard pages <= 1000 else { throw OfficeEngine.error("DOCX 超过 1000 页安全上限。") }
            let container = NSTextContainer(containerSize: content)
            container.lineFragmentPadding = 0; layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            let range = layout.glyphRange(for: container)
            guard range.length > 0 else { throw OfficeEngine.error("DOCX 存在无法放入页面的内容。") }
            context.beginPage(mediaBox: &box)
            context.translateBy(x: 0, y: paper.height); context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            layout.drawBackground(forGlyphRange: range, at: CGPoint(x: left, y: top))
            layout.drawGlyphs(forGlyphRange: range, at: CGPoint(x: left, y: top))
            NSGraphicsContext.restoreGraphicsState(); context.endPage()
            end = NSMaxRange(range)
        } while end < layout.numberOfGlyphs
    }
}

// Small compatibility surface for the MIT-licensed native slide/sheet renderers.
enum ConversionError {
    static func unreadable(_ url: URL) -> NSError { OfficeEngine.error("无法读取 \(url.lastPathComponent)，文件可能损坏、加密或不受支持。") }
    static func writeFailed(_ url: URL) -> NSError { OfficeEngine.error("无法写入 \(url.lastPathComponent)。") }
    static func message(_ text: String) -> NSError { OfficeEngine.error(text) }
}
func L(_ text: String, _ arguments: CVarArg...) -> String { String(format: text, arguments: arguments) }
