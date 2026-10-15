import AppKit
import ImageIO
import UniformTypeIdentifiers

// Original geometric artwork: seven rings in a hexagonal cluster.
// No SF Symbols artwork is exported or embedded in the app icon.
let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setAllowsAntialiasing(true)
let vertices = (0..<6).map { i -> CGPoint in
    let a = CGFloat(i) * .pi / 3 + .pi / 2
    return CGPoint(x: 512 + 456 * cos(a), y: 512 + 456 * sin(a))
}
// Round the six corners with quadratic curves, retaining a hexagonal silhouette.
let shape = CGMutablePath()
func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x-a.x)*t, y: a.y + (b.y-a.y)*t)
}
for i in 0..<6 {
    let v = vertices[i]
    let incoming = mix(v, vertices[(i+5)%6], 0.09)
    let outgoing = mix(v, vertices[(i+1)%6], 0.09)
    if i == 0 { shape.move(to: incoming) } else { shape.addLine(to: incoming) }
    shape.addQuadCurve(to: outgoing, control: v)
}
shape.closeSubpath()
ctx.addPath(shape)
ctx.setFillColor(CGColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1))
ctx.fillPath()
ctx.setStrokeColor(CGColor(red: 0.97, green: 0.98, blue: 1, alpha: 1))
ctx.setLineWidth(42)
var centers = [CGPoint(x: 512, y: 512)]
for i in 0..<6 {
    let a = CGFloat(i) * .pi / 3 + .pi / 2
    centers.append(CGPoint(x: 512 + 208*cos(a), y: 512 + 208*sin(a)))
}
for c in centers { ctx.strokeEllipse(in: CGRect(x: c.x-78, y: c.y-78, width: 156, height: 156)) }
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(output) else { fatalError("PNG export failed") }
