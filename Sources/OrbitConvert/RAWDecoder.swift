import CoreImage
import Foundation

enum RAWDecoder {
    // Extensions are candidates, not a promise that every camera/compression is supported.
    static let extensions = ["dng", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "raf", "rw2", "orf", "pef", "srw", "raw", "rwl", "3fr", "fff", "iiq", "kdc", "dcr", "mos", "x3f"]
    static let targets = ["jpg", "png", "heic", "tiff", "webp", "bmp", "pdf"]
    static func supports(_ ext: String) -> Bool { extensions.contains(ext.lowercased()) }
    static func decode(_ url: URL) throws -> CGImage {
        guard let filter = CIRAWFilter(imageURL: url), let image = filter.outputImage else {
            throw OfficeEngine.error("macOS 无法解码此 RAW。该相机型号或压缩方式可能尚未被当前系统支持；不会使用内嵌预览图替代原图。")
        }
        let rect = image.extent.integral
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0,
              rect.width * rect.height <= 150_000_000 else {
            throw OfficeEngine.error("RAW 超过 1.5 亿像素的安全处理上限。")
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        for software in [false, true] {
            let context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: software])
            if let rendered = context.createCGImage(image, from: rect, format: .RGBA8, colorSpace: colorSpace) {
                return rendered
            }
        }
        throw OfficeEngine.error("RAW 原始像素解码失败。当前系统可能不支持此相机或无法使用图像渲染服务。")
    }
}
