import Foundation

/// Call from one owner (the app's main actor); writes are atomic and decoding failures propagate.
public struct ScriptLibrary: Sendable {
    public let root: URL
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for folder in ["Takes", "Inbox", "Receipts"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }
    private func read<T: Decodable>(_ name: String, as: T.Type, missing: T) throws -> T {
        let url = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return missing }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    private func write<T: Encodable>(_ value: T, to name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: root.appendingPathComponent(name), options: .atomic)
    }
    public func loadScripts() throws -> [Script] {
        try read("scripts.json", as: [Script].self, missing: []).map { script in
            var script = script; script.settings = script.settings.validated(); return script
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    public func saveScripts(_ scripts: [Script]) throws { try write(scripts, to: "scripts.json") }
    @discardableResult public func importText(_ data: Data, title: String) throws -> Script {
        guard data.count <= 1_000_000 else { throw LibraryError.oversizedText }
        guard var text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw LibraryError.invalidText }
        if text.hasPrefix("\u{feff}") { text.removeFirst() }
        let script = Script(title: title, text: text)
        var scripts = try loadScripts(); scripts.insert(script, at: 0)
        try saveScripts(scripts)
        return script
    }
    public func loadTakes() throws -> [Take] { try read("takes.json", as: [Take].self, missing: []).sorted { $0.createdAt > $1.createdAt } }
    public func movieURL(for take: Take) -> URL { root.appendingPathComponent("Takes").appendingPathComponent(take.fileName) }
    public func beginTake(scriptTitle: String) throws -> Take {
        var takes = try loadTakes(); let take = Take(scriptTitle: scriptTitle)
        takes.insert(take, at: 0); try write(takes, to: "takes.json"); return take
    }
    public func finishTake(id: UUID, duration: Double, interrupted: Bool) throws {
        try updateTake(id: id) { take in
            take.duration = duration.isFinite ? max(0, duration) : 0
            take.status = interrupted ? .interrupted : .ready
        }
    }
    public func failTake(id: UUID) throws { try updateTake(id: id) { $0.status = .failed } }
    private func updateTake(id: UUID, change: (inout Take) -> Void) throws {
        var takes = try loadTakes()
        guard let index = takes.firstIndex(where: { $0.id == id }) else { throw LibraryError.missingTake }
        change(&takes[index]); try write(takes, to: "takes.json")
    }
    public func deleteTake(id: UUID) throws {
        var takes = try loadTakes()
        guard let take = takes.first(where: { $0.id == id }) else { throw LibraryError.missingTake }
        let url = movieURL(for: take)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        takes.removeAll { $0.id == id }; try write(takes, to: "takes.json")
    }
}
