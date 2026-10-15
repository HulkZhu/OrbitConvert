import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreText
import PDFKit
import Vision
import Darwin

/// All intermediates stay in a private temporary directory. Only completed
/// results are published, without overwriting source files or previous outputs.
enum Converter {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic", "heif", "tif", "tiff", "bmp", "gif"]
    static func formats(for input: URL) -> [Format] {
        if input.pathExtension.lowercased() == "rar" { return [WheelOptions.extract] }
        if RAWDecoder.supports(input.pathExtension) { return RAWDecoder.targets.compactMap { id in Format.all.first { $0.ext == id } } }
        if let targets = MediaConverter.targets(BatchConverter.kind(input)) { return targets.compactMap { id in Format.all.first { $0.ext == id } } }
        let defaults = defaultFormats(for: input)
        let source = BatchConverter.kind(input)
        let images = imageExtensions.contains(source) || source == "svg"
        let documents = ["txt", "pdf", "docx", "pptx", "xlsx", "pages", "numbers", "key"].contains(source)
        guard images || documents else { return [] }
        var targets = Set(["png", "jpg", "webp", "heic", "gif", "bmp", "tiff", "pdf"])
        if documents { targets.formUnion(["txt", "docx"]) }
        if images { targets.insert("docx") } // Restore existing OCR-to-DOCX, not a new image-to-TXT route.
        if source == "key" { targets.insert("pptx") }
        if source == "numbers" { targets.insert("xlsx") }
        targets.remove(source)
        let preferred = defaults.filter { targets.contains($0.ext) }
        return preferred + Format.all.filter { candidate in
            targets.contains(candidate.ext) && !preferred.contains { $0.ext == candidate.ext }
        }
    }
    static func defaultFormats(for input: URL) -> [Format] {
        if input.pathExtension.lowercased() == "rar" { return [WheelOptions.extract] }
        if RAWDecoder.supports(input.pathExtension) { return ["jpg", "png", "heic", "tiff", "webp"].compactMap { id in Format.all.first { $0.ext == id } } }
        if let targets = MediaConverter.targets(BatchConverter.kind(input)) { return targets.compactMap { id in Format.all.first { $0.ext == id } } }
        var ext = input.pathExtension.lowercased()
        if ext == "jpeg" { ext = "jpg" }; if ext == "heif" { ext = "heic" }; if ext == "tif" { ext = "tiff" }
        let outputs: [String]
        switch ext {
        case "pdf": outputs = ["jpg", "png", "docx", "txt"]
        case "pptx": outputs = ["docx", "pdf", "jpg", "png"]
        case "docx": outputs = ["png", "jpg", "txt", "pdf", "webp"]
        case "txt": outputs = ["docx"]
        case "xlsx": outputs = ["png", "jpg", "pdf"]
        case "key": outputs = ["pptx"]
        case "numbers": outputs = ["xlsx"]
        case "pages": outputs = ["docx"]
        case "bmp", "tiff": outputs = ["png", "jpg", "webp", "heic", "gif"]
        case "svg": outputs = ["png", "jpg", "webp"]
        default:
            guard imageExtensions.contains(ext) else { return [] }
            outputs = ["png", "jpg", "webp", "heic", "gif", "pdf", "docx"].filter { $0 != ext }
        }
        return outputs.compactMap { ext in Format.all.first { $0.ext == ext } }
    }

    static func outputStem(_ input: URL, format: Format, naming: String) -> String {
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.dateFormat = "yyyy-MM-dd"
        let template = naming.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{name}-converted" : naming
        var name = template.replacingOccurrences(of: "{format}", with: format.ext)
            .replacingOccurrences(of: "{date}", with: date.string(from: Date()))
            .replacingOccurrences(of: "{name}", with: input.deletingPathExtension().lastPathComponent)
        name = name.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator: "-")
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        // Leave space for extension/collision suffix on filesystems with 255-byte names.
        while name.utf8.count > 180 { name.removeLast() }
        return name.isEmpty ? "converted" : name
    }

    static func run(_ input: URL, _ format: Format, naming: String = "{name}-converted", trimWhitespace: Bool = false, allowExternalApps: Bool = false, progress: (String) -> Void = { _ in }) throws -> URL {
        guard formats(for: input).contains(where: { $0.ext == format.ext }) || (BatchConverter.kind(input) == format.ext && imageExtensions.contains(format.ext)) else {
            throw OfficeEngine.error("此转换不受支持。")
        }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("OrbitConvert-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        progress("读取文件…")
        let sourceExt = input.pathExtension.lowercased()
        let outputExtension = format.ext == "alac" ? "m4a" : format.ext
        let result = work.appendingPathComponent("result").appendingPathExtension(outputExtension)
        var product = result
        var isFolder = false
        if MediaConverter.targets(BatchConverter.kind(input)) != nil {
            try MediaConverter.run(input, target: format.ext, output: result, progress: progress)
        } else if ["key", "numbers", "pages"].contains(sourceExt) {
            let native = sourceExt == "key" ? "pptx" : sourceExt == "numbers" ? "xlsx" : "docx"
            if format.ext == native || format.ext == "pdf" {
                product = try OfficeEngine.convert(input, to: format.ext, in: work, allowExternalApps: allowExternalApps, progress: progress)
            } else {
                let intermediate = try OfficeEngine.convert(input, to: native, in: work, allowExternalApps: allowExternalApps, progress: progress)
                product = try run(intermediate, format, trimWhitespace: trimWhitespace, progress: progress)
                isFolder = (try product.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
            }
        } else if format.ext == "txt" || format.ext == "docx" {
            let content = try text(input, workspace: work, progress: progress)
            if format.ext == "txt" { try content.write(to: result, atomically: false, encoding: .utf8) }
            else { progress("生成可编辑 DOCX…"); try writeDOCX(content, to: result, workspace: work) }
        } else if format.ext == "pdf" {
            if ["docx", "pptx", "xlsx", "xls"].contains(sourceExt) {
                product = try NativeOffice.pdf(input, in: work, progress: progress)
            } else if sourceExt == "txt" {
                try textPDF(readText(input), to: result)
            } else {
                let pages = try rasterPages(input, workspace: work, allowExternalApps: allowExternalApps, progress: progress)
                try writeImagePDF(pages, to: result, progress: progress)
            }
        } else {
            let pages = try rasterPages(input, workspace: work, progress: progress)
            if pages.count > 1 {
                isFolder = true; product = work.appendingPathComponent("pages", isDirectory: true)
                try fm.createDirectory(at: product, withIntermediateDirectories: true)
            }
            for i in 0..<pages.count {
                try autoreleasepool {
                    progress("转换 \(format.name) · 第 \(i + 1)/\(pages.count) 页…")
                    let target = isFolder ? product.appendingPathComponent(String(format: "page-%03d", i + 1)).appendingPathExtension(format.ext) : result
                    let image = try pages.load(i)
                    let renderedDocument = ["pdf", "docx", "pptx", "xlsx", "xls"].contains(sourceExt)
                    try encode(trimWhitespace && renderedDocument ? trimWhiteBorder(image) : image, as: format, to: target)
                }
            }
        }
        progress("保存结果…")
        let stem = outputStem(input, format: format, naming: naming)
        for index in 1...10000 {
            let suffix = index == 1 ? "" : "-\(index)"
            var target = input.deletingLastPathComponent().appendingPathComponent(stem + suffix, isDirectory: isFolder)
            if !isFolder { target.appendPathExtension(outputExtension) }
            do {
                if isFolder { try fm.moveItem(at: product, to: target) }
                else { try Data(contentsOf: product, options: .mappedIfSafe).write(to: target, options: .withoutOverwriting) }
                return target
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { continue }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    struct Pages { let count: Int; let load: (Int) throws -> CGImage }
    static func rasterPages(_ input: URL, workspace: URL, allowExternalApps: Bool = false, progress: (String) -> Void) throws -> Pages {
        var input = input
        let ext = input.pathExtension.lowercased()
        if RAWDecoder.supports(ext) {
            return Pages(count: 1) { _ in try RAWDecoder.decode(input) }
        }
        if ext == "svg" {
            guard let vector = NSImage(contentsOf: input), vector.size.width.isFinite, vector.size.height.isFinite,
                  vector.size.width > 0, vector.size.height > 0, vector.size.width * vector.size.height <= 40_000_000,
                  let image = vector.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw OfficeEngine.error("SVG 无法读取或画布过大。") }
            return Pages(count: 1) { _ in image }
        }
        if ["docx", "pptx", "xlsx", "xls"].contains(ext) { input = try NativeOffice.pdf(input, in: workspace, progress: progress) }
        if ext == "txt" {
            let pdf = workspace.appendingPathComponent("text.pdf")
            try textPDF(readText(input), to: pdf); input = pdf
        }
        if input.pathExtension.lowercased() == "pdf" {
            guard let pdf = CGPDFDocument(input as CFURL), pdf.isUnlocked, pdf.numberOfPages > 0 else { throw OfficeEngine.error("PDF 无法读取或需要密码。") }
            return Pages(count: pdf.numberOfPages) { index in
                guard let page = pdf.page(at: index + 1) else { throw CocoaError(.fileReadCorruptFile) }
                var box = page.getBoxRect(.cropBox)
                if page.rotationAngle % 180 != 0 { box = CGRect(x: 0, y: 0, width: box.height, height: box.width) }
                guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
                let scale = min(2, 6000 / max(box.width, box.height))
                let width = max(1, Int(ceil(box.width * scale))), height = max(1, Int(ceil(box.height * scale)))
                let ctx = try bitmap(width, height, white: true)
                // CGPDFPageGetDrawingTransform fits down but does not upscale.
                // Scale the context explicitly, then fit in page-point units.
                ctx.scaleBy(x: scale, y: scale)
                ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: box.width, height: box.height), rotate: 0, preserveAspectRatio: true))
                ctx.drawPDFPage(page)
                guard let image = ctx.makeImage() else { throw CocoaError(.fileReadCorruptFile) }; return image
            }
        }
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), CGImageSourceGetCount(source) > 0 else { throw OfficeEngine.error("无法读取图片内容。") }
        return Pages(count: CGImageSourceGetCount(source)) { index in
            let info = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = info?[kCGImagePropertyPixelWidth] as? Int ?? 0, height = info?[kCGImagePropertyPixelHeight] as? Int ?? 0
            guard width > 0, height > 0, Double(width) * Double(height) <= 40_000_000 else { throw OfficeEngine.error("图片超过 4000 万像素的安全处理上限。") }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
            // HEIC may return a lazy image even when the OS decoder is unavailable.
            // Reject missing pixels rather than writing a blank page into a merged PDF.
            if ["heic", "heif"].contains(input.pathExtension.lowercased()), image.dataProvider?.data == nil {
                throw OfficeEngine.error("系统未能解码 HEIC 像素。请在本机桌面运行新版后重试；该文件未转换，也不会生成空白 PDF 页。")
            }
            return image
        }
    }

    static func bitmap(_ width: Int, _ height: Int, white: Bool = false) throws -> CGContext {
        guard width > 0, height > 0, Double(width) * Double(height) <= 150_000_000,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { throw OfficeEngine.error("图片过大或内存不足。") }
        if white { ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
        return ctx
    }

    static func trimWhiteBorder(_ image: CGImage) -> CGImage {
        guard let ctx = try? bitmap(image.width, image.height, white: true) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let bytes = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return image }
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = y * ctx.bytesPerRow + x * 4
                // Keep pale artwork; only genuinely white/near-white borders are removed.
                if bytes[i] < 250 || bytes[i + 1] < 250 || bytes[i + 2] < 250 {
                    minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return image } // Preserve empty pages.
        let padding = 8
        minX = max(0, minX - padding); minY = max(0, minY - padding)
        maxX = min(image.width - 1, maxX + padding); maxY = min(image.height - 1, maxY + padding)
        // Crop the normalized bitmap, whose row ordering matches the measured pixels.
        return ctx.makeImage()?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) ?? image
    }

    static func encode(_ original: CGImage, as format: Format, to url: URL) throws {
        if format.ext == "webp" { try WebP.encode(original).write(to: url); return }
        var image = original
        if ["jpg", "heic", "bmp"].contains(format.ext) {
            let ctx = try bitmap(image.width, image.height, white: true)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); image = ctx.makeImage()!
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil) else { throw OfficeEngine.error("系统不支持输出 \(format.name)") }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw OfficeEngine.error("\(format.name) 编码失败。") }
    }

    static func readText(_ input: URL) throws -> String {
        let data = try Data(contentsOf: input)
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]), let text = String(data: data, encoding: .utf16) { return text }
        guard let text = String(data: data, encoding: .utf8) else { throw OfficeEngine.error("TXT 请使用 UTF-8 或带 BOM 的 UTF-16 编码。") }
        return text.replacingOccurrences(of: "\u{feff}", with: "")
    }

    static func text(_ input: URL, workspace: URL, progress: (String) -> Void) throws -> String {
        if input.pathExtension.lowercased() == "txt" { return try readText(input) }
        if ["docx", "pptx"].contains(input.pathExtension.lowercased()) {
            progress("提取可编辑文字…")
            return try DocumentText.read(input)
        }
        if input.pathExtension.lowercased() == "xlsx" {
            progress("读取工作表文字与缓存值…")
            return try SpreadsheetConverter.read(input).map { sheet in
                sheet.name + "\n" + sheet.rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            }.joined(separator: "\n\u{000c}\n")
        }
        if input.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(url: input), !pdf.isLocked, pdf.pageCount > 0 else { throw OfficeEngine.error("文档无法读取或需要密码。") }
            var content: [String] = []
            for index in 0..<pdf.pageCount {
                progress("提取文字层 · 第 \(index + 1)/\(pdf.pageCount) 页…")
                let text = pdf.page(at: index)?.string ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let pages = try rasterPages(input, workspace: workspace, progress: progress)
                    content.append(try recognize(pages.load(index)))
                } else { content.append(text) }
            }
            guard content.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw OfficeEngine.error("没有识别到可编辑文字。") }
            return content.joined(separator: "\n\u{000c}\n")
        }
        let pages = try rasterPages(input, workspace: workspace, progress: progress)
        var content: [String] = []
        for index in 0..<pages.count {
            progress("识别文字 · 第 \(index + 1)/\(pages.count) 页…")
            content.append(try autoreleasepool { try recognize(pages.load(index)) })
        }
        guard content.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw OfficeEngine.error("没有识别到可编辑文字。") }
        return content.joined(separator: "\n\u{000c}\n")
    }

    static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image)
        do { try handler.perform([request]) }
        catch { request.usesCPUOnly = true; try handler.perform([request]) }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func writeImagePDF(_ pages: Pages, to url: URL, progress: (String) -> Void) throws {
        guard let ctx = CGContext(url as CFURL, mediaBox: nil, nil) else { throw CocoaError(.fileWriteUnknown) }
        defer { ctx.closePDF() }
        for i in 0..<pages.count {
            try autoreleasepool {
                progress("生成 PDF · 第 \(i + 1)/\(pages.count) 页…")
                let image = try pages.load(i)
                var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                let media = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
                ctx.beginPDFPage([kCGPDFContextMediaBox as String: media] as CFDictionary)
                ctx.draw(image, in: box); ctx.endPDFPage()
            }
        }
    }

    static func textPDF(_ text: String, to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        defer { ctx.closePDF() }
        for section in text.components(separatedBy: "\u{000c}") {
            let font = CTFontCreateWithName("PingFang SC" as CFString, 12, nil)
            let attr = NSAttributedString(string: section.isEmpty ? " " : section, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let setter = CTFramesetterCreateWithAttributedString(attr)
            var position = 0
            while position < attr.length {
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: position, length: 0), CGPath(rect: box.insetBy(dx: 48, dy: 48), transform: nil), nil)
                let range = CTFrameGetVisibleStringRange(frame)
                guard range.length > 0 else { throw OfficeEngine.error("文本分页失败。") }
                ctx.beginPDFPage(nil); CTFrameDraw(frame, ctx); ctx.endPDFPage(); position += range.length
            }
        }
    }

    static func writeDOCX(_ text: String, to url: URL, workspace: URL) throws {
        func escape(_ text: String) -> String {
            String(text.unicodeScalars.filter { $0.value == 9 || $0.value >= 32 }).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let folder = workspace.appendingPathComponent("docx-package")
        let fm = FileManager.default
        try fm.createDirectory(at: folder.appendingPathComponent("word"), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        let sections = text.components(separatedBy: "\u{000c}").map { page in
            page.components(separatedBy: .newlines).map { "<w:p><w:r><w:rPr><w:rFonts w:ascii=\"Arial\" w:eastAsia=\"PingFang SC\"/><w:sz w:val=\"24\"/></w:rPr><w:t xml:space=\"preserve\">\(escape($0))</w:t></w:r></w:p>" }.joined()
        }.joined(separator: "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>")
        let document = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\(sections)<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"960\" w:right=\"960\" w:bottom=\"960\" w:left=\"960\"/></w:sectPr></w:body></w:document>"
        try document.write(to: folder.appendingPathComponent("word/document.xml"), atomically: false, encoding: .utf8)
        try "<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>".write(to: folder.appendingPathComponent("[Content_Types].xml"), atomically: false, encoding: .utf8)
        try "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>".write(to: folder.appendingPathComponent("_rels/.rels"), atomically: false, encoding: .utf8)
        let names = ["[Content_Types].xml", "_rels/.rels", "word/document.xml"]
        try ZipArchive.write(try names.map { ($0, try Data(contentsOf: folder.appendingPathComponent($0))) }, to: url)
    }
}

enum WebP {
    static func encode(_ image: CGImage) throws -> Data {
        guard image.width <= 16383, image.height <= 16383 else { throw OfficeEngine.error("WebP 单边最多支持 16383 像素。") }
        guard let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("libwebp.7.dylib"), let library = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else { throw OfficeEngine.error("包内 WebP 编码器缺失。") }
        defer { dlclose(library) }
        typealias Encode = @convention(c) (UnsafePointer<UInt8>, Int32, Int32, Int32, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>) -> Int
        typealias Free = @convention(c) (UnsafeMutableRawPointer?) -> Void
        guard let encodeSymbol = dlsym(library, "WebPEncodeLosslessRGBA"), let freeSymbol = dlsym(library, "WebPFree") else { throw OfficeEngine.error("WebP 编码器不兼容。") }
        let encode = unsafeBitCast(encodeSymbol, to: Encode.self), free = unsafeBitCast(freeSymbol, to: Free.self)
        let ctx = try Converter.bitmap(image.width, image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
        // Quartz stores premultiplied alpha; WebP expects straight RGBA.
        for offset in stride(from: 0, to: image.width * image.height * 4, by: 4) {
            let alpha = Int(pixels[offset + 3])
            if alpha > 0 && alpha < 255 { for c in 0..<3 { pixels[offset + c] = UInt8(min(255, (Int(pixels[offset + c]) * 255 + alpha / 2) / alpha)) } }
        }
        var output: UnsafeMutablePointer<UInt8>?
        let count = encode(pixels, Int32(image.width), Int32(image.height), Int32(ctx.bytesPerRow), &output)
        guard count > 0, let bytes = output else { throw OfficeEngine.error("WebP 编码失败。") }
        defer { free(bytes) }
        return Data(bytes: bytes, count: count)
    }
}
