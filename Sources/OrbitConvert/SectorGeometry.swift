import CoreGraphics

enum SectorGeometry {
    static let cornerRadius = 15.0
    static func sector(_ index: Int, count: Int, expanded: Bool = false, expansion: Double? = nil, angle: Double? = nil, span: Double? = nil) -> CGPath {
        let center = CGPoint(x: 220, y: 220)
        let step = span ?? (2 * Double.pi / Double(count))
        let start = (angle ?? (Double(index) * step + .pi / 2)) - step / 2
        let end = start + step
        let amount = min(1, max(0, expansion ?? (expanded ? 1 : 0)))
        let outer = WheelGeometry.outer + 4 * amount
        let inner = WheelGeometry.inner - 3 * amount
        let corner = cornerRadius
        // Offset each radial boundary by a fixed normal distance. Neighbours'
        // straight edges are parallel lines, separated by 2*gap at every radius.
        let gap = 5.0
        let os = start + asin(gap / outer), oe = end - asin(gap / outer)
        let ins = start + asin(gap / inner), ine = end - asin(gap / inner)
        let ot = sqrt(outer * outer - gap * gap)
        let it = sqrt(inner * inner - gap * gap)
        let a = corner / outer, b = corner / inner
        func p(_ radius: Double, _ angle: Double) -> CGPoint {
            CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        func edge(_ t: Double, _ angle: Double, _ offset: Double) -> CGPoint {
            CGPoint(x: center.x + t * cos(angle) - offset * sin(angle),
                    y: center.y + t * sin(angle) + offset * cos(angle))
        }
        let path = CGMutablePath()
        path.move(to: p(outer, os + a))
        path.addArc(center: center, radius: outer, startAngle: os + a, endAngle: oe - a, clockwise: false)
        path.addQuadCurve(to: edge(ot - corner, end, -gap), control: p(outer, oe))
        path.addLine(to: edge(it + corner, end, -gap))
        path.addQuadCurve(to: p(inner, ine - b), control: p(inner, ine))
        path.addArc(center: center, radius: inner, startAngle: ine - b, endAngle: ins + b, clockwise: true)
        path.addQuadCurve(to: edge(it + corner, start, gap), control: p(inner, ins))
        path.addLine(to: edge(ot - corner, start, gap))
        path.addQuadCurve(to: p(outer, os + a), control: p(outer, os))
        path.closeSubpath()
        return path
    }
}
