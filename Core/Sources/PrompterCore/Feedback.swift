import Foundation

public enum FeedbackTarget: String, CaseIterable, Codable, Sendable {
    case shortVideo, wideVideo, undecided
    public var title: String { switch self { case .shortVideo: "רילס / סטורי / Shorts"; case .wideVideo: "וידאו רחב / מצגת"; case .undecided: "טרם החלטתי" } }
    public var orientation: String { switch self { case .shortVideo: "אנכי"; case .wideVideo: "רוחבי"; case .undecided: "תלוי ביעד הפרסום" } }
}
public struct FeedbackMetrics: Codable, Equatable, Sendable {
    public let brightness, clippedPixels, sharpness: Double
    public let faceCount: Int
    public let faceTouchesEdge: Bool
    public let silenceFraction, clippingFraction: Double
    public let width, height: Int
    public init(brightness: Double, clippedPixels: Double, sharpness: Double, faceCount: Int, faceTouchesEdge: Bool, silenceFraction: Double, clippingFraction: Double, width: Int, height: Int) {
        self.brightness = brightness; self.clippedPixels = clippedPixels; self.sharpness = sharpness; self.faceCount = faceCount; self.faceTouchesEdge = faceTouchesEdge; self.silenceFraction = silenceFraction; self.clippingFraction = clippingFraction; self.width = width; self.height = height
    }
}
public struct LocalFinding: Identifiable, Sendable {
    public let id, title, detail: String
}
public enum FeedbackRules {
    public static func validDuration(_ seconds: Double) -> Bool { seconds.isFinite && seconds >= 6 && seconds <= 8.01 }
    public static func findings(_ m: FeedbackMetrics, target: FeedbackTarget) -> [LocalFinding] {
        var results: [LocalFinding] = []
        func add(_ id: String, _ title: String, _ detail: String) { results.append(.init(id: id, title: title, detail: detail)) }
        add("orientation", "כיוון מומלץ: " + target.orientation, target == .wideVideo ? "ליעד שבחרת מומלץ פריים רחב. האפליקציה מצלמת כרגע לאורך בלבד." : target == .shortVideo ? "לסרטון קצר ברשתות מומלץ פריים אנכי." : "בחר יעד כדי לקבל המלצת כיוון ממוקדת.")
        add("resolution", "מקטע הבדיקה: \(m.width)×\(m.height)", min(m.width, m.height) < 720 ? "הרזולוציה נמוכה יחסית; בדוק את הגדרות הצילום." : "מידות הקובץ הזמני לניתוח. ההקטנה אינה משנה את הגדרות צילום הסרטונים.")
        if m.brightness < 0.22 { add("dark", "התמונה חשוכה יחסית", "נסה אור רך מול המציג. המדידה מבוססת על דגימות מהתמונה.") }
        if m.clippedPixels > 0.15 { add("bright", "אזורים בהירים מאוד", "נסה להתרחק ממקור אור חזק או לשנות זווית. המדד אינו מזהה את מקור האור.") }
        if m.sharpness < 2 { add("soft", "חדות נמוכה משוערת", "נקה את העדשה ובדוק מיקוד. גם רקע חלק משפיע על המדד.") }
        if m.faceCount != 1 { add("face-unknown", "המסגור לא נבדק בביטחון", "לא זוהו פנים יחידות בעקביות בכל הדגימות. זו אינה קביעה שהצילום לא טוב.") }
        else if m.faceTouchesEdge { add("framing", "הפנים קרובות לשולי הפריים", "נסה להתרחק מעט או למרכז את המצלמה, והשאר מקום מעל הראש.") }
        if m.silenceFraction > 0.65 { add("quiet", "רוב דגימות הקול חלשות", "בדוק את המיקרופון ודבר במרחק דומה לזה של הצילום. זה אינו מדד לקצב דיבור.") }
        if m.clippingFraction > 0.01 { add("clipping", "קול חזק מאוד בחלק מהדגימות", "נסה להרחיק מעט את המיקרופון או לדבר בעוצמה מתונה.") }
        return results
    }
}
public struct VideoCapabilityProof: Codable, Sendable {
    public let identity: String
    public let checkedAt: Date
    public let modelVersion: String?
    public init(identity: String, checkedAt: Date, modelVersion: String? = nil) { self.identity = identity; self.checkedAt = checkedAt; self.modelVersion = modelVersion }
    public func valid(identity: String, now: Date = .now) -> Bool {
        self.identity == identity && now >= checkedAt && now.timeIntervalSince(checkedAt) < 7 * 86400
    }
}
public struct FeedbackReport: Codable, Sendable {
    public struct Recommendation: Codable, Sendable, Identifiable {
        public let category, observation, action, limitation: String
        public var id: String { category }
    }
    public let positive: String
    public let recommendations: [Recommendation]
    public static func decode(_ data: Data) throws -> Self {
        let report = try JSONDecoder().decode(Self.self, from: data)
        let allowed: Set<String> = ["lighting", "framing", "angle", "background", "delivery"]
        guard data.count < 30_000, report.positive.count <= 500, report.recommendations.count <= 3,
              Set(report.recommendations.map(\.category)).count == report.recommendations.count,
              report.recommendations.allSatisfy({ allowed.contains($0.category) && [$0.observation, $0.action, $0.limitation].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 700 } }) else { throw VariantError.invalid }
        return report
    }
}
