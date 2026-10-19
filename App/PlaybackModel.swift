import SwiftUI
import QuartzCore
import PrompterCore

@MainActor private final class DisplayTarget: NSObject {
    weak var owner: PlaybackModel?
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}

@Observable @MainActor
final class PlaybackModel {
    var clock = ScrollClock(travel: 1, duration: 1)
    var isRunning = false
    var followsVoice = false
    var soundActive = false
    private var cue = WordCue(text: "")
    private var gate = SoundGate()
    var currentWord: Int? { followsVoice ? cue.index(at: clock.offset / clock.travel) : nil }

    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private let target = DisplayTarget()
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?

    func start(travel: Double, duration: Double, text: String = "", followsVoice: Bool = false, threshold: Double = -40) {
        stop(); clock = ScrollClock(travel: travel, duration: duration)
        self.followsVoice = followsVoice; cue = WordCue(text: text)
        gate = SoundGate(threshold: threshold); soundActive = false
        isRunning = true; target.owner = self
        let link = CADisplayLink(target: target, selector: #selector(DisplayTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common); displayLink = link
        lastTimestamp = CACurrentMediaTime()
    }
    func tick(_ link: CADisplayLink) {
        guard isRunning, let previous = lastTimestamp else { return }
        advance(by: max(0, link.timestamp - previous), at: link.timestamp); lastTimestamp = link.timestamp
    }
    func receiveAudio(level: Double, at time: Double) { gate.receive(level: level, at: time) }
    func advance(by delta: Double, at time: Double) {
        soundActive = followsVoice && gate.isOpen(at: time)
        clock.advance(by: delta, moveText: !followsVoice || soundActive)
    }
    func selectWord(_ index: Int) {
        guard followsVoice, cue.ranges.indices.contains(index) else { return }
        clock.seek(to: cue.position(for: index))
    }
    func pauseText() { clock.isPaused.toggle() }
    func resetText() { clock.resetText() }
    func setDuration(_ duration: Double) { clock.setDuration(duration) }
    func stop() { isRunning = false; displayLink?.invalidate(); displayLink = nil; lastTimestamp = nil }
}

@MainActor final class PromptLayoutCache {
    private var text: String?
    private var width: CGFloat = 0
    private var fontSize: CGFloat = 0
    private var cached: PromptLayout?

    func layout(text: String, width: CGFloat, fontSize: CGFloat) -> PromptLayout {
        if self.text == text, self.width == width, self.fontSize == fontSize, let cached { return cached }
        let result = PromptLayout(text: text, width: width, fontSize: fontSize)
        self.text = text; self.width = width; self.fontSize = fontSize; cached = result
        return result
    }
}

@MainActor final class PromptLayout {
    let attributed: NSAttributedString
    let height: CGFloat
    let lastLineY: CGFloat
    let lineHeight: CGFloat
    let wordRects: [[CGRect]]
    let wordLineY: [CGFloat]
    let wordRanges: [NSRange]
    func wordIndex(at point: CGPoint) -> Int? {
        wordRects.firstIndex { $0.contains { $0.contains(point) } }
    }


    init(text: String, width: CGFloat, fontSize: CGFloat) {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right; paragraph.baseWritingDirection = .rightToLeft
        paragraph.lineSpacing = fontSize * 0.35
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph, .foregroundColor: UIColor.white])
        let storage = NSTextStorage(attributedString: attributed)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container); storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        var lastY: CGFloat = 0
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { rect, _, _, _, _ in lastY = rect.minY }
        let ranges = WordCue(text: text).ranges
        self.wordRanges = ranges
        self.wordRects = ranges.map { range in
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rects: [CGRect] = []
            manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in rects.append(rect) }
            return rects
        }
        self.wordLineY = ranges.map { range in
            let glyph = manager.glyphIndexForCharacter(at: range.location)
            return manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        }
        self.attributed = attributed
        self.height = ceil(manager.usedRect(for: container).height)
        self.lineHeight = font.lineHeight + paragraph.lineSpacing
        // End with the last line at the cue, still readable, including one-line scripts.
        self.lastLineY = max(1, lastY)
    }
}
