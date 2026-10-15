import Foundation
import ImageIO

// Package the already resized PNG assets into the standard ICNS container.
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Usage: PackIcon iconset output.icns") }
let entries = [
    ("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")
]
func length(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}
var body = Data()
for (type, file) in entries {
    let png = try Data(contentsOf: URL(fileURLWithPath: args[1]).appendingPathComponent(file))
    body.append(Data(type.utf8))
    body.append(length(png.count + 8))
    body.append(png)
}
var icon = Data("icns".utf8)
icon.append(length(body.count + 8))
icon.append(body)
let output = URL(fileURLWithPath: args[2])
try icon.write(to: output, options: .atomic)
guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
      CGImageSourceGetCount(source) >= entries.count else { fatalError("Invalid ICNS image count") }
for index in 0..<CGImageSourceGetCount(source) {
    guard CGImageSourceCreateImageAtIndex(source, index, nil) != nil else {
        fatalError("Invalid ICNS image at index \(index)")
    }
}
print("Validated ICNS representations: \(CGImageSourceGetCount(source))")
