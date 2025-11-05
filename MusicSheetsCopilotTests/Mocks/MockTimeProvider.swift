import Foundation
@testable import MusicSheetsCopilot

/// Mock time provider for testing - allows manual time control
class MockTimeProvider: TimeProvider {
    var currentTime: Date
    private var scheduledTimers: [MockTimer] = []
    
    init(startTime: Date = Date()) {
        self.currentTime = startTime
    }
    
    func now() -> Date {
        return currentTime
    }
    
    func advance(by interval: TimeInterval) {
        currentTime = currentTime.addingTimeInterval(interval)
        
        // Fire all timers that should have triggered
        for timer in scheduledTimers where timer.isValid {
            timer.checkAndFire(at: currentTime)
        }
    }
    
    func scheduleTimer(interval: TimeInterval, repeats: Bool, block: @escaping () -> Void) -> TimerProtocol {
        let timer = MockTimer(
            interval: interval,
            repeats: repeats,
            block: block,
            startTime: currentTime
        )
        scheduledTimers.append(timer)
        return timer
    }
    
    /// Clean up invalidated timers
    func cleanupInvalidatedTimers() {
        scheduledTimers.removeAll { !$0.isValid }
    }
}

/// Mock timer that fires when mock time advances past its trigger time
class MockTimer: TimerProtocol {
    private let interval: TimeInterval
    private let repeats: Bool
    private let block: () -> Void
    private var nextFireTime: Date
    private(set) var isValid = true
    
    init(interval: TimeInterval, repeats: Bool, block: @escaping () -> Void, startTime: Date) {
        self.interval = interval
        self.repeats = repeats
        self.block = block
        self.nextFireTime = startTime.addingTimeInterval(interval)
    }
    
    func checkAndFire(at currentTime: Date) {
        guard isValid else { return }
        
        // Fire multiple times if we've advanced past multiple intervals
        while isValid && currentTime >= nextFireTime {
            block()
            
            if repeats {
                nextFireTime = nextFireTime.addingTimeInterval(interval)
            } else {
                isValid = false
            }
        }
    }
    
    func invalidate() {
        isValid = false
    }
}
