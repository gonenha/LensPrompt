import Foundation

/// Whitespace tokens preserve exact UTF-16 positions for UIKit, including emoji and mixed RTL text.
public struct WordCue: Sendable {
    public let ranges: [NSRange]
    private let starts: [Double]
    public init(text: String) {
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        ranges = tokens.map { NSRange($0.startIndex..<$0.endIndex, in: text) }
        let weights = tokens.map { 0.65 + 0.07 * Double(min(12, $0.count)) }
        let total = weights.reduce(0, +)
        var sum = 0.0
        starts = weights.map { weight in defer { sum += weight }; return sum / max(1, total) }
    }
    public func index(at position: Double) -> Int? {
        guard !starts.isEmpty else { return nil }
        let position = position.isFinite ? min(1, max(0, position)) : 0
        var low = 0, high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= position + 1e-12 { low = mid + 1 } else { high = mid }
        }
        return max(0, low - 1)
    }
    public func position(for index: Int) -> Double {
        guard !starts.isEmpty else { return 0 }
        return starts[min(starts.count - 1, max(0, index))]
    }
}

/// An energy gate, not speech recognition: loud background noise can also open it.
public struct SoundGate: Sendable {
    public var threshold: Double
    private var lastSample: Double?
    private var lastLoud: Double?
    public init(threshold: Double = -40) { self.threshold = threshold }
    public mutating func receive(level: Double, at time: Double) {
        guard time.isFinite else { return }
        lastSample = time
        if level.isFinite && level >= threshold { lastLoud = time }
    }
    public func isOpen(at time: Double) -> Bool {
        guard time.isFinite, let lastSample, let lastLoud else { return false }
        return time >= lastSample && time - lastSample <= 0.35 && time >= lastLoud && time - lastLoud <= 0.18
    }
}
