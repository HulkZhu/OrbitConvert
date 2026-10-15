import AVFoundation
import Darwin

final class FLACEncoder {
    typealias H = OpaquePointer
    let lib: UnsafeMutableRawPointer
    let encoder: H
    let process: @convention(c) (H, UnsafePointer<Int32>, UInt32) -> Int32
    let finishEncoder: @convention(c) (H) -> Int32
    let delete: @convention(c) (H) -> Void
    init(rate: Double, channels: UInt32, output: URL) throws {
        guard let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("libFLAC.14.dylib"), let library = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else { throw OfficeEngine.error("包内 FLAC 编码库缺失。") }
        func symbol<T>(_ name: String, _ type: T.Type) throws -> T {
            guard let p = dlsym(library, "FLAC__stream_encoder_"+name) else { throw OfficeEngine.error("FLAC 编码库不兼容。") }
            return unsafeBitCast(p, to: type)
        }
        do {
            let create = try symbol("new", (@convention(c) () -> H?).self)
            guard let h = create() else { throw OfficeEngine.error("FLAC 初始化失败。") }
            encoder = h
            delete = try symbol("delete", (@convention(c) (H) -> Void).self)
            process = try symbol("process_interleaved", (@convention(c) (H, UnsafePointer<Int32>, UInt32) -> Int32).self)
            finishEncoder = try symbol("finish", (@convention(c) (H) -> Int32).self)
            for (key, value) in [("set_channels", channels), ("set_sample_rate", UInt32(rate)), ("set_bits_per_sample", 24), ("set_compression_level", 5)] {
                let set = try symbol(key, (@convention(c) (H, UInt32) -> Int32).self)
                guard set(h, value) != 0 else { throw OfficeEngine.error("FLAC 参数不受支持。") }
            }
            let initialize = try symbol("init_file", (@convention(c) (H, UnsafePointer<CChar>, UnsafeRawPointer?, UnsafeRawPointer?) -> Int32).self)
            guard initialize(h, output.path, nil, nil) == 0 else { throw OfficeEngine.error("FLAC 输出文件初始化失败。") }
        } catch { dlclose(library); throw error }
        lib = library
    }
    deinit { delete(encoder); dlclose(lib) }
    func write(_ buffer: AVAudioPCMBuffer) throws {
        guard let channels = buffer.floatChannelData else { throw OfficeEngine.error("无效音频缓冲区。") }
        let count = Int(buffer.format.channelCount)
        var samples = [Int32](repeating: 0, count: Int(buffer.frameLength)*count)
        for frame in 0..<Int(buffer.frameLength) {
            for channel in 0..<count {
                let value = channels[channel][frame]
                samples[frame*count+channel] = value.isFinite ? Int32(max(-8388608, min(8388607, Double(value)*8388608))) : 0
            }
        }
        guard process(encoder, samples, buffer.frameLength) != 0 else { throw OfficeEngine.error("FLAC 编码失败。") }
    }
    func finish() throws { guard finishEncoder(encoder) != 0 else { throw OfficeEngine.error("FLAC 编码收尾失败。") } }
}
