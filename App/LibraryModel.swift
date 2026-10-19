import Foundation
import Observation
import PrompterCore

@Observable @MainActor
final class LibraryModel {
    let disk: ScriptLibrary
    var scripts: [Script] = []
    var takes: [Take] = []
    var error: String?
    var scriptsLoaded = false
    var takesLoaded = false
    var inboxSuspended = false
    var bridgeNotice: String?
    @ObservationIgnored private let exports = TakeExportStore()
    var takeGroups: [TakeGroup] {
        Dictionary(grouping: takes, by: \.groupID).map { _, members in
            let title = members.first?.scriptID.flatMap { id in scripts.first(where: { $0.id == id })?.title } ?? members.first?.scriptTitle ?? ""
            return TakeGroup(takes: members, title: title.isEmpty ? "ללא כותרת" : title)
        }.sorted { ($0.takes.map(\.createdAt).max() ?? .distantPast) > ($1.takes.map(\.createdAt).max() ?? .distantPast) }
    }
    func takes(for scriptID: UUID) -> [Take] { takes.filter { $0.scriptID == scriptID } }

    @discardableResult func rateTake(_ take: Take, rating: TakeRating) -> Bool {
        do { try disk.setRating(id: take.id, rating: rating); reloadTakes(); return true }
        catch { self.error = "לא ניתן לשמור את הדירוג. " + error.localizedDescription; return false }
    }
    func prepareShare(_ takes: [Take]) async throws -> TakeShareBatch {
        try Task.checkCancellation()
        let batch = try await exports.prepare(takes: takes, libraryRoot: disk.root, exportRoot: URL.cachesDirectory.appendingPathComponent("TakeExports"))
        guard !Task.isCancelled else { await exports.release(batch); throw CancellationError() }
        return batch
    }
    func releaseShare(_ batch: TakeShareBatch) async { await exports.release(batch) }
    private var hasUnsavedChanges = false

    func receiveCodexInbox() {
        guard scriptsLoaded, !inboxSuspended, !hasUnsavedChanges else { return }
        do {
            let result = try disk.receiveCodexTransfers()
            if !result.acknowledged.isEmpty || result.imported > 0 {
                reload()
                bridgeNotice = result.imported > 0 ? "תסריט חדש התקבל מקודקס ונשמר בספרייה." : "התסריט מקודקס כבר התקבל."
            }
            if result.rejected > 0 { bridgeNotice = "לא ניתן לקלוט חלק מהתסריטים מקודקס. קובצי ההעברה נשמרו לבדיקה." }
        } catch { bridgeNotice = "לא ניתן לבדוק כרגע תסריטים מקודקס. ננסה שוב כשהאפליקציה פתוחה." }
    }

    init(disk: ScriptLibrary) { self.disk = disk; reload() }

    func reload() {
        do {
            scripts = try disk.loadScripts()
            if !FileManager.default.fileExists(atPath: disk.root.appendingPathComponent("scripts.json").path) {
                scripts = [.sample]; try disk.saveScripts(scripts)
            }
            scriptsLoaded = true
        } catch { scriptsLoaded = false; self.error = "לא ניתן לטעון תסריטים. הקבצים המקוריים נשמרו ללא שינוי. \(error.localizedDescription)" }
        reloadTakes()
    }

    func reloadTakes() {
        do { takes = scriptsLoaded ? try disk.prepareTakeCatalog(scripts: scripts) : try disk.loadTakes(); takesLoaded = true }
        catch { takesLoaded = false; self.error = "לא ניתן לטעון את רשימת הטייקים. \(error.localizedDescription)" }
    }

    func upsert(_ script: Script) {
        guard scriptsLoaded else { return }
        var script = script; script.updatedAt = .now; script.settings = script.settings.validated()
        if let index = scripts.firstIndex(where: { $0.id == script.id }) { scripts[index] = script }
        else { scripts.append(script) }
        scripts.sort { $0.updatedAt > $1.updatedAt }
        do { try disk.saveScripts(scripts); hasUnsavedChanges = false }
        catch { hasUnsavedChanges = true; self.error = "השמירה נכשלה. המלל עדיין פתוח; נסה שוב לפני סגירת האפליקציה. \(error.localizedDescription)" }
    }

    func deleteScript(_ script: Script) {
        do {
            let remaining = scripts.filter { $0.id != script.id }
            try disk.ensureCodexReceipt(for: script)
            try disk.saveScripts(remaining); scripts = remaining; hasUnsavedChanges = false
        }
        catch { self.error = error.localizedDescription }
    }

    @discardableResult func deleteTake(_ take: Take) -> Bool {
        do {
            try disk.deleteTake(id: take.id)
            reloadTakes()
            return true
        } catch { self.error = "לא ניתן למחוק את הטייק. " + error.localizedDescription; return false }
    }

    func duplicate(_ script: Script) {
        upsert(script.duplicated())
    }

    func importFile(_ url: URL) -> Script? {
        guard scriptsLoaded else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let count = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard count <= 1_000_000 else { throw LibraryError.oversizedText }
            let script = try disk.importText(Data(contentsOf: url), title: url.deletingPathExtension().lastPathComponent)
            scripts = try disk.loadScripts(); return script
        } catch { self.error = error.localizedDescription; return nil }
    }
}
