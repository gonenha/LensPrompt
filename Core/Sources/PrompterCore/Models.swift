import Foundation

public enum Pace: String, Codable, Sendable { case words, duration }
public enum FilmingMode: String, Codable, Sendable { case hand, distance }

public struct PromptSettings: Codable, Equatable, Sendable {
    public var mode: FilmingMode = .hand
    public var pace: Pace = .words
    public var wordsPerMinute: Double = 120
    public var targetSeconds: Double = 60
    public var fontSize: Double = 26
    public var widthFraction: Double = 0.86
    public var backgroundOpacity: Double = 0.75
    public var countdown: Int = 3
    // Optional storage preserves decoding of scripts saved before voice following existed.
    public var voiceFollowEnabled: Bool?
    public var voiceThreshold: Double?
    public var followsVoice: Bool {
        get { voiceFollowEnabled ?? false }
        set { voiceFollowEnabled = newValue }
    }
    public var soundThreshold: Double {
        get { Self.finite(voiceThreshold ?? -40, min: -55, max: -20, fallback: -40) }
        set { voiceThreshold = Self.finite(newValue, min: -55, max: -20, fallback: -40) }
    }
    public init() {}

    public mutating func apply(_ mode: FilmingMode) {
        self.mode = mode
        fontSize = mode == .hand ? 26 : 34
        countdown = mode == .hand ? 3 : 7
        widthFraction = mode == .hand ? 0.86 : 0.94
    }

    public func duration(wordCount: Int) -> Double {
        if pace == .duration { return Self.finite(targetSeconds, min: 10, max: 1800, fallback: 60) }
        let rate = Self.finite(wordsPerMinute, min: 50, max: 220, fallback: 120)
        return max(1, Double(max(1, wordCount)) / rate * 60)
    }

    public func validated() -> Self {
        var value = self
        value.wordsPerMinute = Self.finite(wordsPerMinute, min: 50, max: 220, fallback: 120)
        value.targetSeconds = Self.finite(targetSeconds, min: 10, max: 1800, fallback: 60)
        value.fontSize = Self.finite(fontSize, min: 20, max: 40, fallback: 26)
        value.widthFraction = Self.finite(widthFraction, min: 0.65, max: 0.98, fallback: 0.86)
        value.backgroundOpacity = Self.finite(backgroundOpacity, min: 0.2, max: 0.95, fallback: 0.75)
        value.countdown = [0, 3, 5, 7].contains(countdown) ? countdown : 3
        return value
    }

    private static func finite(_ value: Double, min lower: Double, max upper: Double, fallback: Double) -> Double {
        value.isFinite ? min(upper, max(lower, value)) : fallback
    }
}

public enum PresentationMode: String, Codable, Sendable { case scrolling, talkingPoints }
public enum TalkingStage: String, Codable, CaseIterable, Sendable {
    case opening, pain, solution, offer
    public var title: String {
        switch self {
        case .opening: "הפתיח"
        case .pain: "הכאב"
        case .solution: "הפתרון"
        case .offer: "ההצעה"
        }
    }
}
public struct TalkingPoint: Equatable, Sendable, Identifiable {
    public let stage: TalkingStage
    public let text: String
    public var id: TalkingStage { stage }
}

public struct Script: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var text: String
    public var updatedAt: Date
    public var settings: PromptSettings
    public var isSample: Bool
    public var sourceScriptID: UUID?
    public var scriptStyle: ScriptStyle?
    public var sourceTransferHash: String?
    public var savedPresentationMode: PresentationMode?
    public var talkingPointTexts: [String: String]?
    public var presentationMode: PresentationMode {
        get { savedPresentationMode ?? .scrolling }
        set { savedPresentationMode = newValue }
    }
    public func pointText(for stage: TalkingStage) -> String { talkingPointTexts?[stage.rawValue] ?? "" }
    public mutating func setPointText(_ text: String, for stage: TalkingStage) {
        if talkingPointTexts == nil { talkingPointTexts = [:] }
        talkingPointTexts?[stage.rawValue] = text
    }
    public var activeTalkingPoints: [TalkingPoint] {
        TalkingStage.allCases.compactMap { stage in
            let text = pointText(for: stage).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : TalkingPoint(stage: stage, text: text)
        }
    }
    public var presentationText: String {
        presentationMode == .talkingPoints ? activeTalkingPoints.map(\.text).joined(separator: "\n") : text
    }
    public func duplicated() -> Script {
        var copy = Script(title: title + " — עותק", text: text)
        copy.settings = settings; copy.savedPresentationMode = savedPresentationMode; copy.talkingPointTexts = talkingPointTexts
        return copy
    }
    public init(id: UUID = UUID(), title: String, text: String = "", isSample: Bool = false) {
        self.id = id; self.title = title; self.text = text
        self.updatedAt = .now; self.settings = .init(); self.isSample = isSample
    }
    public var wordCount: Int { Self.wordCount(presentationText) }
    public var canStart: Bool { !presentationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public static func wordCount(_ text: String) -> Int { text.split(whereSeparator: { $0.isWhitespace }).count }
    public static let sample = Script(title: "פשוט להתחיל", text: """
    לפעמים, כל מה שצריך כדי להתחיל, זה רעיון אחד פשוט.

    לא תסריט מושלם. לא ציוד יקר. רק משהו שחשוב לנו להגיד, ומישהו בצד השני שרוצה לשמוע.

    היום אני רוצה לדבר על הצעד הראשון. על הרגע שבו מפסיקים לתכנן, ופשוט מנסים.

    גם אם קצת מתבלבלים. גם אם צריך עוד טייק. זה חלק מהדרך.

    אז הנה האתגר שלי לעצמי: להסתכל לעדשה, לקחת נשימה, ולדבר כמו שאני מדבר עם חבר.

    כי בסוף, מה שעובר דרך המסך, זו לא השלמות. זה אנחנו.
    """, isSample: true)
}

public enum TakeStatus: String, Codable, Sendable { case pending, ready, interrupted, failed }
public enum TakeRating: String, Codable, CaseIterable, Sendable {
    case excellent, good, poor
    public var title: String {
        switch self { case .excellent: "מעולה"; case .good: "טוב"; case .poor: "גרוע" }
    }
}

public struct TakeGroup: Identifiable, Sendable {
    public let id: String
    public let scriptID: UUID?
    public let title: String
    public let takes: [Take]
    public init(takes: [Take], title: String) {
        self.takes = takes.sorted { ($0.takeNumber ?? 0) < ($1.takeNumber ?? 0) }
        id = takes.first?.groupID ?? ""; scriptID = takes.first?.scriptID; self.title = title
    }
}

public struct Take: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let scriptTitle: String
    public let createdAt: Date
    public var duration: Double
    public var status: TakeStatus
    public var scriptID: UUID?
    public var takeNumber: Int?
    public var rating: TakeRating?
    public var storedFileName: String?
    public var groupID: String { scriptID.map { "script-" + $0.uuidString } ?? "legacy-" + scriptTitle }
    public var label: String { "טייק \(takeNumber ?? 1)" }
    public var exportFileName: String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        let clean = scriptTitle.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: " ")
        let suffix = " — " + label + ".mov"
        var prefix = "", byteCount = 0
        for character in clean {
            let count = String(character).utf8.count
            guard byteCount + count <= 255 - suffix.utf8.count else { break }
            prefix.append(character); byteCount += count
        }
        let trimmed = prefix.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return (trimmed.isEmpty ? "ללא כותרת" : trimmed) + suffix
    }
    public var fileName: String { storedFileName ?? id.uuidString + ".mov" }
    public init(scriptTitle: String) {
        id = UUID(); self.scriptTitle = scriptTitle; createdAt = .now; duration = 0; status = .pending
    }
}

public enum LibraryError: LocalizedError {
    case invalidText, oversizedText, missingTake
    public var errorDescription: String? {
        switch self {
        case .invalidText: "לא ניתן לקרוא את הקובץ. יש לשמור אותו כטקסט UTF-8."
        case .oversizedText: "הקובץ גדול מדי. אפשר לייבא טקסט עד 1MB."
        case .missingTake: "הטייק לא נמצא ברשימה."
        }
    }
}
