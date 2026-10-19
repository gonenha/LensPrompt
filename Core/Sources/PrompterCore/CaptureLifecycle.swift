public struct CaptureLifecycle: Sendable {
    public enum Phase: Sendable { case idle, countdown, starting, recording, pausing, paused, resuming, finishing, finished }
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
    @discardableResult public mutating func didStart() -> Bool {
        guard phase == .starting else { return false }
        phase = stopRequested ? .finishing : .recording
        return !stopRequested
    }
    @discardableResult public mutating func requestPause() -> Bool {
        guard phase == .recording else { return false }; phase = .pausing; return true
    }
    @discardableResult public mutating func didPause() -> Bool {
        guard phase == .pausing else { return false }; phase = .paused; return true
    }
    @discardableResult public mutating func requestResume() -> Bool {
        guard phase == .paused else { return false }; phase = .resuming; return true
    }
    @discardableResult public mutating func didResume() -> Bool {
        guard phase == .resuming else { return false }; phase = .recording; return true
    }
    public mutating func cancelPauseTransition() {
        if phase == .pausing { phase = .recording }
        else if phase == .resuming { phase = .paused }
    }
    public mutating func requestStop() {
        if phase == .starting { stopRequested = true }
        switch phase {
        case .recording, .pausing, .paused, .resuming: phase = .finishing
        default: break
        }
    }
    public mutating func didFinish() { phase = .finished }
}
