import Foundation
import CryptoKit

public enum CodexTransfer {
    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private struct Payload: Decodable {
        let version: Int
        let id: UUID
        let title: String
        let text: String
        let points: [String: String]
        let mode: PresentationMode
    }
    public static func decode(_ data: Data, id: UUID, checksum: String) throws -> Script {
        guard data.count <= 1_000_000, digest(data) == checksum else { throw TransferFailure.invalid }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.version == 1, payload.id == id,
              valid(payload.title, limit: 1_000), valid(payload.text, limit: 800_000),
              Set(payload.points.keys) == Set(TalkingStage.allCases.map(\.rawValue)),
              payload.points.values.allSatisfy({ valid($0, limit: 50_000) }) else { throw TransferFailure.invalid }
        var script = Script(id: id, title: payload.title.trimmingCharacters(in: .whitespacesAndNewlines), text: payload.text)
        script.presentationMode = payload.mode; script.talkingPointTexts = payload.points
        script.sourceTransferHash = checksum
        return script
    }
    private static func valid(_ text: String, limit: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !text.contains("\0") && text.utf8.count <= limit
    }
}

public struct TransferReceipt: Codable, Sendable {
    public let version: Int
    public let id: UUID
    public let sha256: String
    public let status: String
}
public struct InboxResult: Sendable {
    public var imported = 0
    public var acknowledged: [UUID] = []
    public var rejected = 0
}
private enum TransferFailure: Error { case invalid, conflict }

extension ScriptLibrary {
    /// Before deleting an imported script, persist its acknowledgment so a pending replay cannot recreate it.
    public func ensureCodexReceipt(for script: Script) throws {
        guard let checksum = script.sourceTransferHash else { return }
        guard checksum.count == 64, checksum.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw TransferFailure.invalid }
        let url = root.appendingPathComponent("Receipts/" + script.id.uuidString.lowercased() + ".json")
        if FileManager.default.fileExists(atPath: url.path) {
            let receipt = try JSONDecoder().decode(TransferReceipt.self, from: Data(contentsOf: url))
            guard receipt.version == 1, receipt.id == script.id, receipt.sha256 == checksum, receipt.status == "imported" else { throw TransferFailure.conflict }
        } else {
            let receipt = TransferReceipt(version: 1, id: script.id, sha256: checksum, status: "imported")
            try JSONEncoder().encode(receipt).write(to: url, options: .atomic)
        }
    }

    /// The ready marker is copied only after the entire payload. Receipts survive edits and deletion.
    public func receiveCodexTransfers() throws -> InboxResult {
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        let receipts = root.appendingPathComponent("Receipts", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
        var result = InboxResult()
        for marker in files.filter({ $0.pathExtension == "ready" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let name = marker.deletingPathExtension().lastPathComponent
                guard let id = UUID(uuidString: name), name == id.uuidString.lowercased(),
                      (try marker.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= 128 else { throw TransferFailure.invalid }
                let checksum = try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                guard checksum.count == 64, checksum.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw TransferFailure.invalid }
                let payloadURL = inbox.appendingPathComponent(name + ".json")
                guard (try payloadURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= 1_000_000 else { throw TransferFailure.invalid }
                let data = try Data(contentsOf: payloadURL)
                let script = try CodexTransfer.decode(data, id: id, checksum: checksum)
                let receiptURL = receipts.appendingPathComponent(name + ".json")
                if FileManager.default.fileExists(atPath: receiptURL.path) {
                    let receipt = try JSONDecoder().decode(TransferReceipt.self, from: Data(contentsOf: receiptURL))
                    guard receipt.version == 1, receipt.id == id, receipt.sha256 == checksum, receipt.status == "imported" else { throw TransferFailure.conflict }
                } else {
                    var scripts = try loadScripts()
                    if let existing = scripts.first(where: { $0.id == id }) {
                        // Recovery after saving the script but before writing its receipt. Preserve local edits.
                        guard existing.sourceTransferHash == checksum else { throw TransferFailure.conflict }
                    } else {
                        scripts.insert(script, at: 0)
                        try saveScripts(scripts)
                        result.imported += 1
                    }
                    try ensureCodexReceipt(for: script)
                }
                result.acknowledged.append(id)
                // If cleanup fails, the durable receipt makes the next attempt harmless.
                do {
                    try FileManager.default.removeItem(at: marker)
                    try? FileManager.default.removeItem(at: payloadURL)
                } catch { /* Keep payload if its marker could not be removed. */ }
            } catch { result.rejected += 1 }
        }
        return result
    }
}
