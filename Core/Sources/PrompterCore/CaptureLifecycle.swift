public struct CaptureLifecycle: Sendable {
    public enum Phase: Sendable { case idle, countdown, starting, recording, finishing, finished }
    public private(set) var phase: Phase = .idle
    private var stopRequested = false
    public init() {}
    public mutating func beginCountdown() { phase = .countdown; stopRequested = false }
    public mutating func cancel() {
        if phase == .countdown { phase = .idle }
        else { requestStop() }
    }
    @discardableResult public mutating func requestStart() -> Bool {
        guard phase == .countdown else { return false }
        phase = .starting; return true
    }
    /// Returns whether playback may start. A late start after interruption must stop immediately.
    public mutating func didStart() -> Bool {
        guard phase == .starting else { return false }
        phase = stopRequested ? .finishing : .recording
        return !stopRequested
    }
    public mutating func requestStop() {
        if phase == .starting { stopRequested = true }
        if phase == .recording { phase = .finishing }
    }
    public mutating func didFinish() { phase = .finished }
}
