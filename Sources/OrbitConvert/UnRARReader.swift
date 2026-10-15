import Foundation
import Darwin

enum RARPasswordError: LocalizedError {
    case required, incorrect, cancelled
    var errorDescription: String? {
        switch self {
        case .required: return "此 RAR 需要密码。"
        case .incorrect: return "密码错误，或加密数据已损坏。"
        case .cancelled: return "已取消解压。"
        }
    }
}

enum UnRARReader {
    private final class Stream {
        let begin: (NativeArchive.Entry) throws -> Void
        let chunk: (Foundation.Data) throws -> Void
        let finish: () throws -> Void
        var error: Error?
        var count = 0
        var total: Int64 = 0, actual: Int64 = 0, declared: Int64 = 0
        let deadline = Date().addingTimeInterval(180)
        init(begin: @escaping (NativeArchive.Entry) throws -> Void, chunk: @escaping (Foundation.Data) throws -> Void, finish: @escaping () throws -> Void) {
            self.begin = begin; self.chunk = chunk; self.finish = finish
        }
        func perform(_ work: () throws -> Void) -> Int32 {
            do {
                guard Date() < deadline else { throw OfficeEngine.error("解压超时。") }
                try work(); return 1
            } catch { self.error = error; return 0 }
        }
    }
    typealias Begin = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, Int32, Int64) -> Int32
    typealias Chunk = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32) -> Int32
    typealias Finish = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias Walk = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>?, Begin, Chunk, Finish, UnsafeMutableRawPointer) -> Int32
    static func walk(_ url: URL, password: String?, begin: (NativeArchive.Entry) throws -> Void,
                     chunk: (Foundation.Data) throws -> Void, finish: () throws -> Void) throws {
        guard let path = Bundle.main.privateFrameworksURL?.appendingPathComponent("libOrbitUnRAR.dylib"),
              let library = dlopen(path.path, RTLD_NOW | RTLD_LOCAL) else { throw OfficeEngine.error("包内 UnRAR 引擎缺失，请重新安装完整 App。") }
        defer { dlclose(library) }
        guard let symbol = dlsym(library, "orbit_unrar_walk") else { throw OfficeEngine.error("UnRAR 引擎不兼容。") }
        let walk = unsafeBitCast(symbol, to: Walk.self)
        try withoutActuallyEscaping(begin) { begin in
        try withoutActuallyEscaping(chunk) { chunk in
        try withoutActuallyEscaping(finish) { finish in
            let stream = Stream(begin: begin, chunk: chunk, finish: finish)
            let context = Unmanaged.passUnretained(stream).toOpaque()
            let onBegin: Begin = { raw, name, directory, size in
                let state = Unmanaged<Stream>.fromOpaque(raw!).takeUnretainedValue()
                return state.perform {
                    state.count += 1; state.actual = 0; state.declared = size
                    guard state.count <= 10000, size >= 0, size <= 512_000_000, state.total <= 2_000_000_000-size,
                          directory == 0 || size == 0, let name, let string = String(validatingUTF8: name) else { throw OfficeEngine.error("归档条目过多、过大或文件名无效。") }
                    try state.begin(NativeArchive.Entry(name: string, directory: directory != 0, declaredSize: size))
                }
            }
            let onChunk: Chunk = { raw, bytes, count in
                let state = Unmanaged<Stream>.fromOpaque(raw!).takeUnretainedValue()
                return state.perform {
                    guard count >= 0, let bytes else { throw OfficeEngine.error("无效的归档数据。") }
                    state.actual += Int64(count); state.total += Int64(count)
                    guard state.actual <= state.declared, state.total <= 2_000_000_000 else { throw OfficeEngine.error("归档展开后超过安全大小限制。") }
                    try state.chunk(Foundation.Data(bytes: bytes, count: Int(count)))
                }
            }
            let onFinish: Finish = { raw in
                let state = Unmanaged<Stream>.fromOpaque(raw!).takeUnretainedValue()
                return state.perform {
                    guard state.actual == state.declared else { throw OfficeEngine.error("归档内容长度与记录不符。") }
                    try state.finish()
                }
            }
            let result = url.path.withCString { input in
                if let password { return password.withCString { walk(input, $0, onBegin, onChunk, onFinish, context) } }
                return walk(input, nil, onBegin, onChunk, onFinish, context)
            }
            if let error = stream.error { throw error }
            switch result {
            case 0: guard stream.count > 0 else { throw OfficeEngine.error("归档为空。") }
            case 22: throw RARPasswordError.required
            case 24: throw RARPasswordError.incorrect
            case 102: throw OfficeEngine.error("暂不支持分卷 RAR，请先使用支持分卷的工具。")
            case 103: throw OfficeEngine.error("为安全起见，不解压链接、重定向或特殊文件。")
            case 25, 104: throw OfficeEngine.error("归档超过安全内存或大小限制。")
            default: throw OfficeEngine.error("UnRAR 解压失败（代码 \(result)），文件可能损坏或不完整。")
            }
        } } }
    }
}
