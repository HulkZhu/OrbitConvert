import AVFoundation
import AudioToolbox
import Darwin

enum MediaConverter {
    static let videos = ["mov", "mp4", "m4v"]
    static let audio = ["wav", "mp3", "flac", "m4a", "alac", "aiff"]
    static func targets(_ source: String) -> [String]? {
        if videos.contains(source) { return videos.filter { $0 != source } }
        if audio.contains(source) { return audio.filter { $0 != source || source == "m4a" } }
        return nil
    }
    static func run(_ input: URL, target: String, output: URL, progress: (String) -> Void) throws {
        if videos.contains(input.pathExtension.lowercased()) {
            let asset = AVURLAsset(url: input)
            guard !asset.tracks(withMediaType: .video).isEmpty,
                  let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                throw OfficeEngine.error("系统无法读取该视频编码。")
            }
            let type: AVFileType = target == "mov" ? .mov : target == "m4v" ? .m4v : .mp4
            guard export.supportedFileTypes.contains(type) else { throw OfficeEngine.error("此视频无法导出到所选容器。") }
            export.outputURL = output; export.outputFileType = type
            let done = DispatchSemaphore(value: 0)
            export.exportAsynchronously { done.signal() }
            while done.wait(timeout: .now() + 0.2) == .timedOut {
                progress("视频转换 \(Int(export.progress * 100))%")
            }
            guard export.status == .completed else { throw export.error ?? OfficeEngine.error("视频转换未完成。") }
            return
        }
        let source = try AVAudioFile(forReading: input, commonFormat: .pcmFormatFloat32, interleaved: false)
        let pcm = source.processingFormat
        var processed: Int64 = 0
        let length = max(1, source.length)
        guard pcm.channelCount > 0, pcm.channelCount <= 2 else { throw OfficeEngine.error("当前音频转换支持单声道和双声道。") }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: 8192) else { throw OfficeEngine.error("无法创建音频缓冲区。") }
        if target == "flac" {
            let encoder = try FLACEncoder(rate: pcm.sampleRate, channels: pcm.channelCount, output: output)
            while processed < length {
                try source.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try encoder.write(buffer)
                processed += Int64(buffer.frameLength)
                progress("音频转换 \(min(100, Int(Double(processed)/Double(length)*100)))%")
            }
            try encoder.finish(); return
        }
        if target == "mp3" {
            let encoder = try MP3Encoder(rate: pcm.sampleRate, channels: Int(pcm.channelCount), output: output)
            while processed < length {
                try source.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try encoder.write(buffer)
                processed += Int64(buffer.frameLength)
                progress("音频转换 \(min(100, Int(Double(processed)/Double(length)*100)))%")
            }
            try encoder.finish(); return
        }
        let codec: AudioFormatID = target == "flac" ? kAudioFormatFLAC : target == "alac" ? kAudioFormatAppleLossless : target == "m4a" ? kAudioFormatMPEG4AAC : kAudioFormatLinearPCM
        var settings: [String: Any] = [AVFormatIDKey: codec, AVSampleRateKey: pcm.sampleRate, AVNumberOfChannelsKey: pcm.channelCount]
        if codec == kAudioFormatLinearPCM {
            settings[AVLinearPCMBitDepthKey] = 24; settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = target == "aiff"
        } else if codec == kAudioFormatMPEG4AAC { settings[AVEncoderBitRateKey] = 192000 }
        else { settings[AVEncoderBitDepthHintKey] = 24 }
        let destination = try AVAudioFile(forWriting: output, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        while processed < length {
            try source.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try destination.write(from: buffer)
            processed += Int64(buffer.frameLength)
            progress("音频转换 \(min(100, Int(Double(processed)/Double(length)*100)))%")
        }
    }
}

private final class MP3Encoder {
    typealias H = OpaquePointer
    private let library: UnsafeMutableRawPointer
    private let handle: H
    private let file: FileHandle
    private let encode: @convention(c) (H, UnsafePointer<Float>, UnsafePointer<Float>, Int32, UnsafeMutablePointer<UInt8>, Int32) -> Int32
    private let flush: @convention(c) (H, UnsafeMutablePointer<UInt8>, Int32) -> Int32
    private let close: @convention(c) (H) -> Int32
    init(rate: Double, channels: Int, output: URL) throws {
        guard let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("libmp3lame.0.dylib"), let lib = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) else { throw OfficeEngine.error("包内 MP3 编码库缺失。") }
        func symbol<T>(_ name: String, _ type: T.Type) throws -> T {
            guard let p = dlsym(lib, name) else { throw OfficeEngine.error("MP3 编码库不兼容。") }
            return unsafeBitCast(p, to: type)
        }
        do {
            let create = try symbol("lame_init", (@convention(c) () -> H?).self)
            guard let h = create() else { throw OfficeEngine.error("MP3 编码器初始化失败。") }
            handle = h
            close = try symbol("lame_close", (@convention(c) (H) -> Int32).self)
            encode = try symbol("lame_encode_buffer_ieee_float", (@convention(c) (H, UnsafePointer<Float>, UnsafePointer<Float>, Int32, UnsafeMutablePointer<UInt8>, Int32) -> Int32).self)
            flush = try symbol("lame_encode_flush", (@convention(c) (H, UnsafeMutablePointer<UInt8>, Int32) -> Int32).self)
            for (name, value) in [("lame_set_in_samplerate", Int32(rate)), ("lame_set_num_channels", Int32(channels)), ("lame_set_brate", 192), ("lame_set_quality", 2)] {
                let set = try symbol(name, (@convention(c) (H, Int32) -> Int32).self)
                guard set(h, value) >= 0 else { throw OfficeEngine.error("MP3 音频参数不受支持。") }
            }
            let initialize = try symbol("lame_init_params", (@convention(c) (H) -> Int32).self)
            guard initialize(h) >= 0 else { throw OfficeEngine.error("MP3 编码参数无效。") }
            guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            file = try FileHandle(forWritingTo: output)
        } catch { dlclose(lib); throw error }
        library = lib
    }
    deinit { _ = close(handle); try? file.close(); dlclose(library) }
    func write(_ buffer: AVAudioPCMBuffer) throws {
        guard let channels = buffer.floatChannelData else { throw OfficeEngine.error("音频缓冲区格式错误。") }
        var bytes = [UInt8](repeating: 0, count: Int(buffer.frameLength)*2 + 7200)
        let count = encode(handle, channels[0], channels[buffer.format.channelCount == 1 ? 0 : 1], Int32(buffer.frameLength), &bytes, Int32(bytes.count))
        guard count >= 0 else { throw OfficeEngine.error("MP3 编码失败：\(count)") }
        try file.write(contentsOf: Data(bytes.prefix(Int(count))))
    }
    func finish() throws {
        var bytes = [UInt8](repeating: 0, count: 7200)
        let count = flush(handle, &bytes, 7200)
        guard count >= 0 else { throw OfficeEngine.error("MP3 编码收尾失败。") }
        try file.write(contentsOf: Data(bytes.prefix(Int(count)))); try file.close()
    }
}
