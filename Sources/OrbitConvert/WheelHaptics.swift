import AppKit

enum WheelHaptics {
    private static var lastTime: TimeInterval = -1
    private static var generation = 0
    static func play(_ mode: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        guard mode > 0, now - lastTime >= 0.075 else { return }
        lastTime = now; generation += 1
        let token = generation
        NSHapticFeedbackManager.defaultPerformer.perform(mode == 1 ? .alignment : .generic, performanceTime: .now)
        if mode == 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.065) {
                guard generation == token, Preferences.shared.hapticMode == 3 else { return }
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        }
    }
}
