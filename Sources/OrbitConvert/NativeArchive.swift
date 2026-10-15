import Foundation
import Darwin

/// In-process system libarchive. No command-line tool, helper application, or download.
/// Symbols are checked at runtime so an older OS fails cleanly instead of crashing.
final class NativeArchive {
    typealias H = OpaquePointer
    private let library: UnsafeMutableRawPointer
    let create: @convention(c) () -> H?
    let free: @convention(c) (H) -> Int32
    let zip: @convention(c) (H) -> Int32
    let rar: @convention(c) (H) -> Int32
    let rar5: @convention(c) (H) -> Int32
    let open: @convention(c) (H, UnsafePointer<CChar>, Int) -> Int32
    let next: @convention(c) (H, UnsafeMutablePointer<H?>) -> Int32
    let read: @convention(c) (H, UnsafeMutableRawPointer, Int) -> Int
    let path: @convention(c) (H) -> UnsafePointer<CChar>?
    let size: @convention(c) (H) -> Int64
    let filetype: @convention(c) (H) -> UInt32
    let symlink: @convention(c) (H) -> UnsafePointer<CChar>?
    let hardlink: @convention(c) (H) -> UnsafePointer<CChar>?
    let encrypted: @convention(c) (H) -> Int32
    let errorString: @convention(c) (H) -> UnsafePointer<CChar>?

    init() throws {
        guard let lib = dlopen("/usr/lib/libarchive.2.dylib", RTLD_NOW | RTLD_LOCAL) else { throw OfficeEngine.error("此系统缺少本地归档解码库。") }
        func symbol<T>(_ name: String, _ type: T.Type) throws -> T {
            guard let p = dlsym(lib, name) else { throw OfficeEngine.error("系统归档库不支持：\(name)") }
            return unsafeBitCast(p, to: type)
        }
        do {
            create = try symbol("archive_read_new", (@convention(c) () -> H?).self)
            free = try symbol("archive_read_free", (@convention(c) (H) -> Int32).self)
            zip = try symbol("archive_read_support_format_zip", (@convention(c) (H) -> Int32).self)
            rar = try symbol("archive_read_support_format_rar", (@convention(c) (H) -> Int32).self)
            rar5 = try symbol("archive_read_support_format_rar5", (@convention(c) (H) -> Int32).self)
            open = try symbol("archive_read_open_filename", (@convention(c) (H, UnsafePointer<CChar>, Int) -> Int32).self)
            next = try symbol("archive_read_next_header", (@convention(c) (H, UnsafeMutablePointer<H?>) -> Int32).self)
            read = try symbol("archive_read_data", (@convention(c) (H, UnsafeMutableRawPointer, Int) -> Int).self)
            path = try symbol("archive_entry_pathname_utf8", (@convention(c) (H) -> UnsafePointer<CChar>?).self)
            size = try symbol("archive_entry_size", (@convention(c) (H) -> Int64).self)
            filetype = try symbol("archive_entry_filetype", (@convention(c) (H) -> UInt32).self)
            symlink = try symbol("archive_entry_symlink", (@convention(c) (H) -> UnsafePointer<CChar>?).self)
            hardlink = try symbol("archive_entry_hardlink", (@convention(c) (H) -> UnsafePointer<CChar>?).self)
            encrypted = try symbol("archive_entry_is_encrypted", (@convention(c) (H) -> Int32).self)
            errorString = try symbol("archive_error_string", (@convention(c) (H) -> UnsafePointer<CChar>?).self)
        } catch { dlclose(lib); throw error }
        library = lib
    }
    deinit { dlclose(library) }

    struct Entry { let name: String; let directory: Bool; let declaredSize: Int64 }
    /// Streams bounded content. finish is called only after successful decompression/checksum.
    func walk(_ url: URL, rarOnly: Bool, limit: Int64,
              begin: (Entry) throws -> Void, chunk: (Data) throws -> Void, finish: () throws -> Void) throws {
        guard let archive = create() else { throw OfficeEngine.error("无法创建归档读取器。") }
        defer { _ = free(archive) }
        if rarOnly { _ = rar(archive); _ = rar5(archive) } else { _ = zip(archive) }
        func failure() -> NSError {
            let detail = errorString(archive).map { String(cString: $0) } ?? "未知错误"
            if rarOnly && detail.lowercased().contains("encrypt") {
                return OfficeEngine.error("此 RAR 已加密，当前系统解压库不支持密码解压：" + detail)
            }
            return OfficeEngine.error("归档无法读取（可能损坏、加密或分卷不完整）：" + detail)
        }
        guard open(archive, url.path, 65536) == 0 else { throw failure() }
        var count = 0, total: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 65536)
        let deadline = Date().addingTimeInterval(180)
        while true {
            var entry: H?
            let status = next(archive, &entry)
            if status == 1 { break }
            guard status == 0, let entry else { throw failure() }
            count += 1
            guard count <= 10000, Date() < deadline else { throw OfficeEngine.error("归档条目过多或处理超时。") }
            guard encrypted(entry) == 0 else { throw OfficeEngine.error("此 RAR 已加密，当前系统解压库不支持。请先使用支持密码的解压工具打开；不是压缩包损坏。") }
            guard let p = path(entry), let name = String(validatingUTF8: p) else { throw OfficeEngine.error("归档文件名编码无效。") }
            let kind = filetype(entry)
            guard symlink(entry) == nil, hardlink(entry) == nil, kind == 0o100000 || kind == 0o040000 else { throw OfficeEngine.error("为安全起见，不解压符号链接、硬链接或特殊文件。") }
            let declared = size(entry)
            guard declared >= 0, declared <= min(limit, 512_000_000), total <= limit - declared else { throw OfficeEngine.error("归档展开后超过安全大小限制。") }
            try begin(Entry(name: name, directory: kind == 0o040000, declaredSize: declared))
            // RAR5 directories have no payload. Asking libarchive to decode
            // one raises "Can't decompress an entry marked as a directory".
            if kind == 0o040000 {
                guard declared == 0 else { throw OfficeEngine.error("目录条目包含异常数据。") }
                try finish()
                continue
            }
            var actual: Int64 = 0
            while true {
                let n = buffer.withUnsafeMutableBytes { read(archive, $0.baseAddress!, $0.count) }
                guard n >= 0 else { throw failure() }
                if n == 0 { break }
                actual += Int64(n); total += Int64(n)
                guard actual <= min(limit, 512_000_000), total <= limit, Date() < deadline else { throw OfficeEngine.error("归档展开后过大或处理超时。") }
                try chunk(Data(buffer.prefix(n)))
            }
            guard actual == declared else { throw OfficeEngine.error("归档内容长度与记录不符。") }
            try finish()
        }
        guard count > 0 else { throw OfficeEngine.error("归档为空。") }
    }
}

/// Bounded in-memory OOXML package; never writes archive paths to disk.
struct ZipArchive {
    private var entries: [String: Data] = [:]
    init(url: URL) throws {
        let reader = try NativeArchive()
        var name = "", data = Data(), directory = false
        try reader.walk(url, rarOnly: false, limit: 128_000_000, begin: { entry in
            name = try RARExtractor.safePath(entry.name); directory = entry.directory; data = Data()
            guard entries[name] == nil, entry.declaredSize <= 32_000_000 else { throw OfficeEngine.error("Office 包含重复条目或单个资源超过 32 MB。") }
        }, chunk: { data.append($0) }, finish: {
            if !directory { entries[name] = data }
        })
    }
    var paths: [String] { Array(entries.keys) }
    func contains(_ path: String) -> Bool { entries[path] != nil }
    func data(at path: String) -> Data? { entries[path] }

    /// Small stored ZIP writer for generated DOCX. No zip subprocess.
    static func write(_ members: [(String, Data)], to url: URL) throws {
        var output = Data(), central = Data()
        func u16(_ n: Int, _ d: inout Data) { var v = UInt16(n).littleEndian; withUnsafeBytes(of: &v) { d.append(contentsOf: $0) } }
        func u32(_ n: UInt32, _ d: inout Data) { var v = n.littleEndian; withUnsafeBytes(of: &v) { d.append(contentsOf: $0) } }
        for (name, data) in members {
            let bytes = Data(name.utf8)
            guard bytes.count <= 65535, data.count <= 32_000_000 else { throw OfficeEngine.error("DOCX 内容过大。") }
            var crc: UInt32 = 0xffffffff
            for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0) } }
            crc ^= 0xffffffff
            let offset = UInt32(output.count), size = UInt32(data.count)
            u32(0x04034b50, &output); u16(20, &output); u16(0x800, &output); u16(0, &output)
            u16(0, &output); u16(0, &output); u32(crc, &output); u32(size, &output); u32(size, &output)
            u16(bytes.count, &output); u16(0, &output); output.append(bytes); output.append(data)
            u32(0x02014b50, &central); u16(20, &central); u16(20, &central); u16(0x800, &central); u16(0, &central)
            u16(0, &central); u16(0, &central); u32(crc, &central); u32(size, &central); u32(size, &central)
            u16(bytes.count, &central); u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central)
            u32(0, &central); u32(offset, &central); central.append(bytes)
        }
        let offset = UInt32(output.count); output.append(central)
        u32(0x06054b50, &output); u16(0, &output); u16(0, &output); u16(members.count, &output); u16(members.count, &output)
        u32(UInt32(central.count), &output); u32(offset, &output); u16(0, &output)
        try output.write(to: url, options: .withoutOverwriting)
    }
}

enum RARExtractor {
    static func safePath(_ name: String) throws -> String {
        let path = name.replacingOccurrences(of: "\\", with: "/")
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !path.hasPrefix("/"), !parts.isEmpty, parts.count <= 32, path.utf8.count <= 2048,
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              parts.allSatisfy({ $0 != ".." && $0 != "." && !$0.contains(":") && $0.utf8.count <= 255 }) else {
            throw OfficeEngine.error("归档包含不安全的文件路径，已停止解压。")
        }
        return parts.joined(separator: "/")
    }

    static func extract(_ input: URL, password: String? = nil, progress: (String) -> Void = { _ in }) throws -> URL {
        let fm = FileManager.default, parent = input.deletingLastPathComponent()
        // Preserve downloaded-file quarantine; extraction must not bypass Gatekeeper.
        let quarantineSize = getxattr(input.path, "com.apple.quarantine", nil, 0, 0, 0)
        var quarantine = Data(count: max(0, min(quarantineSize, 65536)))
        if quarantineSize > 0 {
            guard quarantineSize <= 65536,
                  quarantine.withUnsafeMutableBytes({ getxattr(input.path, "com.apple.quarantine", $0.baseAddress, $0.count, 0, 0) }) == quarantineSize else {
                throw OfficeEngine.error("无法保留压缩包的下载安全标记。")
            }
        }
        let stage = parent.appendingPathComponent(".OrbitExtract-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }
        var handle: FileHandle?, seen = Set<String>()
        defer { try? handle?.close() }
        try UnRARReader.walk(input, password: password, begin: { entry in
            let path = try safePath(entry.name)
            guard seen.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw OfficeEngine.error("归档包含重名文件，已停止解压。") }
            let target = stage.appendingPathComponent(path, isDirectory: entry.directory)
            progress("解压：\(target.lastPathComponent)")
            if entry.directory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } else {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let fd = Darwin.open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
                guard fd >= 0 else { throw OfficeEngine.error("无法安全创建解压文件。") }
                handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            }
            if !quarantine.isEmpty {
                guard quarantine.withUnsafeBytes({ setxattr(target.path, "com.apple.quarantine", $0.baseAddress, $0.count, 0, 0) }) == 0 else {
                    throw OfficeEngine.error("无法保留解压文件的下载安全标记。")
                }
            }
        }, chunk: { data in
            guard let handle else { throw OfficeEngine.error("目录包含异常数据。") }
            try handle.write(contentsOf: data)
        }, finish: { try handle?.close(); handle = nil })
        var stem = input.deletingPathExtension().lastPathComponent
        let topLevel = try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        let single = topLevel.count == 1 ? topLevel[0] : nil
        let product = single ?? stage
        let isDirectory = try product.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        if let single { stem = single.lastPathComponent }
        while stem.utf8.count > 180 { stem.removeLast() }
        for index in 1...10000 {
            let base = single == nil ? stem + "-extracted" : stem
            let name: String
            if index == 1 { name = base }
            else if !isDirectory, let single, !single.pathExtension.isEmpty {
                name = single.deletingPathExtension().lastPathComponent + "-\(index)." + single.pathExtension
            } else { name = base + "-\(index)" }
            let target = parent.appendingPathComponent(name, isDirectory: isDirectory)
            if renamex_np(product.path, target.path, UInt32(RENAME_EXCL)) == 0 { return target }
            guard errno == EEXIST else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}

enum XMLSafety {
    private final class Check: NSObject, XMLParserDelegate {
        var depth = 0, nodes = 0, okay = true
        func parser(_ parser: XMLParser, didStartElement: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            depth += 1; nodes += 1
            if depth > 64 || nodes > 500000 { okay = false; parser.abortParsing() }
        }
        func parser(_ parser: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) { depth -= 1 }
        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName: String, value: String?) { okay = false; parser.abortParsing() }
        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName: String, publicID: String?, systemID: String?) { okay = false; parser.abortParsing() }
    }
    static func valid(_ data: Data) -> Bool {
        guard data.count <= 16_000_000 else { return false }
        let parser = XMLParser(data: data), check = Check()
        parser.shouldResolveExternalEntities = false; parser.delegate = check
        return parser.parse() && check.okay
    }
}
