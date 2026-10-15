import Foundation
import CoreGraphics

enum BatchConverter {
    struct Failure { let input: URL; let message: String }
    struct Outcome { var outputs: [URL] = []; var failures: [Failure] = []; var merged = false }

    static func kind(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpeg": return "jpg"
        case "heif": return "heic"
        case "tif": return "tiff"
        case "aif": return "aiff"
        default: return url.pathExtension.lowercased()
        }
    }
    /// Stable natural filename order, independent of Finder's selection order.
    static func selection(_ inputs: [URL]) throws -> [URL] {
        guard !inputs.isEmpty, inputs.count <= 500 else { throw OfficeEngine.error("请选择 1–500 个同类型文件。") }
        let files = Array(Set(inputs.map { $0.standardizedFileURL })).sorted {
            let order = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
        guard Set(files.map(kind)).count == 1 else { throw OfficeEngine.error("批量转换请只选择同一种类型的文件，例如全部 HEIC 或全部 PNG。") }
        for file in files {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw OfficeEngine.error("请选择文件，不要选择文件夹或文档包。") }
        }
        return files
    }
    static func formats(_ files: [URL]) -> [Format] {
        guard let first = files.first else { return [] }
        return Converter.formats(for: first).filter { format in
            files.allSatisfy { Converter.formats(for: $0).contains { $0.ext == format.ext } }
        }
    }

    static func run(_ inputs: [URL], _ format: Format, naming: String, trimWhitespace: Bool = false,
                    allowExternalApps: Bool = false, progress: (Double, String) -> Void = { _, _ in }) throws -> Outcome {
        let files = try selection(inputs)
        guard formats(files).contains(where: { $0.ext == format.ext }) else { throw OfficeEngine.error("这组文件不支持所选输出格式。") }
        if files.count > 1, format.ext == "pdf", Converter.imageExtensions.contains(files[0].pathExtension.lowercased()) || RAWDecoder.supports(files[0].pathExtension) {
            return Outcome(outputs: [try mergeImages(files, naming: naming, progress: progress)], merged: true)
        }
        var result = Outcome()
        for (index, file) in files.enumerated() {
            do {
                let url = try Converter.run(file, format, naming: naming, trimWhitespace: trimWhitespace, allowExternalApps: allowExternalApps) {
                    progress(Double(index) / Double(files.count), "第 \(index + 1)/\(files.count) 个 · \(file.lastPathComponent) · \($0)")
                }
                result.outputs.append(url)
            } catch { result.failures.append(Failure(input: file, message: error.localizedDescription)) }
            progress(Double(index + 1) / Double(files.count), "已处理 \(index + 1)/\(files.count) 个文件")
        }
        return result
    }

    private static func mergeImages(_ files: [URL], naming: String, progress: (Double, String) -> Void) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("OrbitMerge-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: work) }
        let product = work.appendingPathComponent("merged.pdf")
        guard let context = CGContext(product as CFURL, mediaBox: nil, nil) else { throw CocoaError(.fileWriteUnknown) }
        var closed = false
        defer { if !closed { context.closePDF() } }
        var pageCount = 0
        for (index, file) in files.enumerated() {
            try autoreleasepool {
                let pages = try Converter.rasterPages(file, workspace: work) { _ in }
                guard pageCount + pages.count <= 2000 else { throw OfficeEngine.error("合并 PDF 最多支持 2000 页。") }
                for page in 0..<pages.count {
                    try autoreleasepool {
                        progress((Double(index) + Double(page) / Double(pages.count)) / Double(files.count), "合并 \(index + 1)/\(files.count) · \(file.lastPathComponent) · 第 \(page + 1) 页")
                        let image = try pages.load(page)
                        var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                        let media = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
                        context.beginPDFPage([kCGPDFContextMediaBox as String: media] as CFDictionary)
                        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
                        context.draw(image, in: box); context.endPDFPage()
                        pageCount += 1
                    }
                }
            }
        }
        context.closePDF(); closed = true
        let format = Format.all.first { $0.ext == "pdf" }!
        let stem = Converter.outputStem(files[0], format: format, naming: naming) + "-merged"
        for index in 1...10000 {
            let target = files[0].deletingLastPathComponent().appendingPathComponent(stem + (index == 1 ? "" : "-\(index)")).appendingPathExtension("pdf")
            do {
                try Data(contentsOf: product, options: .mappedIfSafe).write(to: target, options: .withoutOverwriting)
                progress(1, "已合并 \(files.count) 张图片，共 \(pageCount) 页")
                return target
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { continue }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
