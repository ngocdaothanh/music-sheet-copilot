import Foundation

/// Protocol for abstracting time and timer creation
/// This allows tests to control time progression without waiting for real time
protocol TimeProvider {
    /// Get the current time
    func now() -> Date

    /// Schedule a repeating or one-shot timer
    /// - Parameters:
    ///   - interval: Time interval between timer fires
    ///   - repeats: Whether the timer should repeat
    ///   - block: Closure to execute when timer fires
    /// - Returns: A timer that can be invalidated
    func scheduleTimer(interval: TimeInterval, repeats: Bool, block: @escaping () -> Void) -> TimerProtocol
}

/// Protocol for timer objects that can be invalidated
protocol TimerProtocol {
    func invalidate()
}

// MARK: - Production Implementation

/// Production implementation using system time and real timers
class SystemTimeProvider: TimeProvider {
    func now() -> Date {
        return Date()
    }

    func scheduleTimer(interval: TimeInterval, repeats: Bool, block: @escaping () -> Void) -> TimerProtocol {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
            block()
        }
        return SystemTimer(timer: timer)
    }
}

/// Wrapper around Foundation.Timer to conform to TimerProtocol
private class SystemTimer: TimerProtocol {
    private let timer: Timer

    init(timer: Timer) {
        self.timer = timer
    }

    func invalidate() {
        timer.invalidate()
    }
}
