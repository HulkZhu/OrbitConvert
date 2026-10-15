import CoreGraphics

enum SectorMorph {
    static func samples(_ path: CGPath) -> [CGPoint] {
        var points: [CGPoint] = [], current = CGPoint.zero, start = CGPoint.zero
        func mix(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint { CGPoint(x: a.x+(b.x-a.x)*t, y: a.y+(b.y-a.y)*t) }
        path.applyWithBlock { item in
            let e = item.pointee
            switch e.type {
            case .moveToPoint: current = e.points[0]; start = current; points.append(current)
            case .addLineToPoint: current = e.points[0]; points.append(current)
            case .addQuadCurveToPoint:
                let a = current, b = e.points[0], c = e.points[1]
                for i in 1...12 { let t = Double(i)/12; points.append(mix(mix(a,b,t),mix(b,c,t),t)) }; current = c
            case .addCurveToPoint:
                let a = current, b = e.points[0], c = e.points[1], d = e.points[2]
                for i in 1...16 { let t = Double(i)/16; points.append(mix(mix(mix(a,b,t),mix(b,c,t),t),mix(mix(b,c,t),mix(c,d,t),t),t)) }; current = d
            case .closeSubpath: points.append(start); current = start
            @unknown default: break
            }
        }
        guard points.count > 1 else { return Array(repeating: .zero, count: 64) }
        var lengths = [0.0]
        for i in 1..<points.count { lengths.append(lengths.last! + hypot(points[i].x-points[i-1].x, points[i].y-points[i-1].y)) }
        return (0..<64).map { index in
            let distance = lengths.last! * Double(index)/64
            let end = (1..<lengths.count).first { lengths[$0] >= distance } ?? lengths.count-1
            return mix(points[end-1], points[end], (distance-lengths[end-1])/max(0.0001,lengths[end]-lengths[end-1]))
        }
    }
    static func path(from card: CGRect, to sector: CGPath, progress: Double) -> CGPath {
        Plan(card: card, sector: sector).path(to: sector, progress: progress)
    }
    struct Plan {
        let card: CGRect
        let matched: [CGPoint]
        init(card: CGRect, sector: CGPath) {
        self.card = card
        let a = samples(CGPath(roundedRect: card, cornerWidth: 15, cornerHeight: 15, transform: nil))
        let b = samples(sector)
        var best = a, score = Double.greatestFiniteMagnitude
        // Match contour orientation and start point to avoid twisting the polygon.
        func signedArea(_ points: [CGPoint]) -> Double {
            points.indices.reduce(0) { sum, i in
                let next = points[(i+1) % points.count]
                return sum + points[i].x * next.y - next.x * points[i].y
            }
        }
        // Opposite winding interpolates through a folded/degenerate polygon.
        // Match winding first; optimize only the contour's start point.
        let direction = signedArea(a) * signedArea(b) >= 0 ? 1 : -1
        do {
            for offset in 0..<64 {
                let candidate = (0..<64).map { a[(offset + direction * $0 + 128) % 64] }
                let cost = zip(candidate,b).reduce(0.0) { $0 + pow($1.0.x-$1.1.x,2) + pow($1.0.y-$1.1.y,2) }
                if cost < score { score = cost; best = candidate }
            }
        }
        matched = best
        }
        func path(to sector: CGPath, progress: Double) -> CGPath {
        if progress >= 1 { return sector }
        if progress <= 0 { return CGPath(roundedRect: card, cornerWidth: 15, cornerHeight: 15, transform: nil) }
        let best = matched, b = SectorMorph.samples(sector)
        let path = CGMutablePath()
        for i in 0..<64 {
            let point = CGPoint(x: best[i].x+(b[i].x-best[i].x)*progress, y: best[i].y+(b[i].y-best[i].y)*progress)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath(); return path
        }
    }
}
