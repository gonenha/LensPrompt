import Foundation

public struct ScrollClock: Sendable {
    public private(set) var elapsed: Double = 0
    public private(set) var offset: Double = 0
    public private(set) var travel: Double
    public private(set) var duration: Double
    public var isPaused = false
    public var reachedEnd: Bool { offset >= travel }
    public init(travel: Double, duration: Double) {
        self.travel = travel.isFinite ? max(1, travel) : 1
        self.duration = duration.isFinite ? max(0.01, duration) : 1
    }
    public mutating func advance(by delta: Double, moveText: Bool = true) {
        guard delta.isFinite, delta >= 0 else { return }
        elapsed += delta
        if !isPaused && moveText { offset = min(travel, offset + travel / duration * delta) }
    }
    public mutating func setDuration(_ duration: Double) {
        guard duration.isFinite, duration > 0 else { return }
        self.duration = duration
    }
    public mutating func seek(to fraction: Double) {
        guard fraction.isFinite else { return }
        offset = min(1, max(0, fraction)) * travel
    }
    public mutating func resetText() { offset = 0; isPaused = false }
}
