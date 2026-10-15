import Foundation

// No native dragging session is started. Once captured, every physical mouse
// event through release is swallowed after ordinary user cancellation. A safety
// abort (permission loss, disabled tap, session suspension) always releases input.
struct CapturedGesture {
    struct End {
        let id: Int
        let point: CGPoint
        let commit: Bool
    }
    private(set) var id = 0
    private(set) var ownsMouse = false
    private(set) var moved = false
    private(set) var cancelled = false
    private(set) var origin = CGPoint.zero
    private(set) var point = CGPoint.zero
    mutating func begin(_ p: CGPoint) -> Int {
        id += 1; ownsMouse = true; moved = false; cancelled = false
        origin = p; point = p
        return id
    }
    mutating func move(_ p: CGPoint) {
        point = p
        if hypot(p.x - origin.x, p.y - origin.y) >= 7 { moved = true }
    }
    mutating func cancel() { cancelled = true }
    // Permission loss / disabled tap: invalidate pending work AND release ownership.
    mutating func abort() {
        id += 1; ownsMouse = false; moved = false; cancelled = true
    }
    mutating func end(_ p: CGPoint) -> End {
        let result = End(id: id, point: p, commit: moved && !cancelled)
        ownsMouse = false; point = p
        return result
    }
    func accepts(_ token: Int) -> Bool { ownsMouse && !cancelled && id == token }
}
