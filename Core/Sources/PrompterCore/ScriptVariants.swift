import Foundation

public enum ScriptStyle: String, Codable, CaseIterable, Sendable {
    case dynamic, empathetic, concise
    public var title: String {
        switch self {
        case .dynamic: "דינמי וקצבי"
        case .empathetic: "סיפורי אמפתי"
        case .concise: "מקוצר וממוקד"
        }
    }
}

public enum ScriptVariants {
    public static func decode(_ data: Data, source: Script) throws -> [Script] {
        guard data.count <= 200_000 else { throw VariantError.invalid }
        let fields = try JSONDecoder().decode([String: [String: String]].self, from: data)
        guard Set(fields.keys) == Set(ScriptStyle.allCases.map(\.rawValue)) else { throw VariantError.invalid }
        return try ScriptStyle.allCases.map { style in
            guard let item = fields[style.rawValue], Set(item.keys) == Set(["text"] + TalkingStage.allCases.map(\.rawValue)),
                  item.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 30_000 }) else { throw VariantError.invalid }
            var script = Script(title: source.title + " — " + style.title, text: item["text"]!)
            script.settings = source.settings
            script.savedPresentationMode = source.savedPresentationMode
            script.sourceScriptID = source.sourceScriptID ?? source.id
            script.scriptStyle = style
            for stage in TalkingStage.allCases { script.setPointText(item[stage.rawValue]!, for: stage) }
            return script
        }
    }
    public static var schema: [String: Any] {
        let keys = ["text"] + TalkingStage.allCases.map(\.rawValue)
        let item: [String: Any] = ["type": "object", "properties": Dictionary(uniqueKeysWithValues: keys.map { ($0, ["type": "string"]) }), "required": keys, "additionalProperties": false]
        return ["type": "object", "properties": Dictionary(uniqueKeysWithValues: ScriptStyle.allCases.map { ($0.rawValue, item) }), "required": ScriptStyle.allCases.map(\.rawValue), "additionalProperties": false]
    }
}
public enum VariantError: LocalizedError {
    case invalid
    public var errorDescription: String? { "לא התקבלו שלוש גרסאות מלאות. המקור נשמר; אפשר לנסות שוב." }
}
