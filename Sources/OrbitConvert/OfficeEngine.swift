import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import Darwin

/// Lightweight bridge to the user's installed iWork apps. No Office runtime is
/// bundled or silently downloaded. Operate only on an app-owned temporary copy.
enum OfficeEngine {
    static let pdf = Format(name: "PDF", ext: "pdf", type: .pdf)
    static func error(_ message: String) -> NSError {
        NSError(domain: "OrbitConvert.OfficeEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    static func route(_ ext: String) -> (id: String, name: String)? {
        switch ext {
        case "pages": return ("com.apple.iWork.Pages", "Pages")
        case "key": return ("com.apple.iWork.Keynote", "Keynote")
        case "numbers": return ("com.apple.iWork.Numbers", "Numbers")
        default: return nil
        }
    }
    static func script(app: String, input: URL, output: URL, format: String) -> String {
        func quote(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
        }
        return """
        with timeout of 120 seconds
            tell application \(quote(app))
                set workingDocument to missing value
                try
                    set workingDocument to open (POSIX file \(quote(input.path)))
                    if class of workingDocument is list then set workingDocument to item 1 of workingDocument
                    export workingDocument to (POSIX file \(quote(output.path))) as \(format)
                    close workingDocument saving no
                on error errorText number errorNumber
                    if workingDocument is not missing value then
                        try
                            close workingDocument saving no
                        end try
                    end if
                    error errorText number errorNumber
                end try
            end tell
        end timeout
        """
    }
    static func convert(_ input: URL, to ext: String, in workspace: URL, allowExternalApps: Bool, progress: (String) -> Void) throws -> URL {
        guard let route = route(input.pathExtension.lowercased()) else { throw error("不支持此文档类型。") }
        guard allowExternalApps else {
            throw error("此转换需要电脑上的 \(route.name)。请在设置中开启“允许已安装的 Apple 应用辅助转换”；转换可能短暂显示文档窗口。")
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: route.id) else {
            throw error("请先安装 \(route.name)。小体积版不包含外部文档引擎。")
        }
        let exportFormat: String
        switch (route.name, ext) {
        case (_, "pdf"): exportFormat = "PDF"
        case ("Pages", "docx"): exportFormat = "Microsoft Word"
        case ("Keynote", "pptx"): exportFormat = "Microsoft PowerPoint"
        case ("Numbers", "xlsx"): exportFormat = "Microsoft Excel"
        default: throw error("不支持此文档输出格式。")
        }
        let fm = FileManager.default
        let work = workspace.appendingPathComponent("AppleExport-" + UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let copy = work.appendingPathComponent("OrbitInput").appendingPathExtension(input.pathExtension)
        try fm.copyItem(at: input, to: copy)
        let result = work.appendingPathComponent("export").appendingPathExtension(ext)
        let scriptURL = work.appendingPathComponent("export.applescript")
        try script(app: appURL.path, input: copy, output: result, format: exportFormat).write(to: scriptURL, atomically: true, encoding: .utf8)
        let logURL = work.appendingPathComponent("export.log")
        fm.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [scriptURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log; process.standardError = log
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        progress("通过 \(route.name) 导出…首次使用请允许自动化权限")
        try process.run()
        if done.wait(timeout: .now() + 135) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 3) == .timedOut, process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            throw error("\(route.name) 转换超时。原文件未改变；若有临时文档窗口，可关闭而不保存。")
        }
        guard process.terminationStatus == 0, fm.fileExists(atPath: result.path) else {
            let detail = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            if detail.contains("-1743") { throw error("请在系统设置 → 隐私与安全性 → 自动化中允许 OrbitConvert 控制 \(route.name)。") }
            throw error("\(route.name) 导出失败：\(String(detail.suffix(500)))")
        }
        if ext == "pdf" {
            guard let pdf = CGPDFDocument(result as CFURL), pdf.numberOfPages > 0 else { throw error("没有生成有效 PDF。") }
        }
        return result
    }
}
