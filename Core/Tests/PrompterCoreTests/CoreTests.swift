import Foundation
import Testing
@testable import PrompterCore

@Test func durationAndMixedText() {
    var settings = PromptSettings()
    settings.wordsPerMinute = 100
    #expect(settings.duration(wordCount: 150) == 90)
    #expect(Script.wordCount("שלום English 123\n\nעולם") == 4)
    settings.targetSeconds = 30
    settings.pace = .duration
    #expect(settings.duration(wordCount: 500) == 30)
    settings.targetSeconds = 0
    #expect(settings.duration(wordCount: 500) == 10)
    settings.wordsPerMinute = 0
    settings.pace = .words
    #expect(settings.duration(wordCount: 50) == 60)
}

@Test func pauseDoesNotStopElapsedAndEndDoesNotStopClock() {
    var clock = ScrollClock(travel: 100, duration: 10)
    clock.advance(by: 2)
    #expect(clock.offset == 20)
    clock.isPaused = true
    clock.advance(by: 3)
    #expect(clock.offset == 20)
    #expect(clock.elapsed == 5)
    clock.isPaused = false
    clock.advance(by: 20)
    #expect(clock.offset == 100)
    #expect(clock.elapsed == 25)
    #expect(clock.reachedEnd)
}

@Test func speedChangesPreservePositionAndResetPreservesTakeTimer() {
    var clock = ScrollClock(travel: 100, duration: 10)
    clock.advance(by: 2)
    clock.setDuration(5)
    #expect(clock.offset == 20)
    clock.advance(by: 1)
    #expect(clock.offset == 40)
    clock.resetText()
    #expect(clock.offset == 0)
    #expect(clock.elapsed == 3)
    clock.advance(by: -.infinity)
    #expect(clock.elapsed == 3)
}

@Test func persistentScriptsAndInvalidImport() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ScriptLibrary(root: root)
    let imported = try store.importText(Data("עברית English 123".utf8), title: "מהמקבוק")
    #expect(imported.text == "עברית English 123")
    #expect(throws: (any Error).self) { try store.importText(Data([0xff, 0xfe, 0xff]), title: "invalid") }
    #expect(try store.loadScripts().count == 1)
    #expect(try ScriptLibrary(root: root).loadScripts().first?.title == "מהמקבוק")
}

@Test func corruptManifestIsNotOverwritten() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ScriptLibrary(root: root)
    let bad = Data("not JSON".utf8)
    try bad.write(to: root.appendingPathComponent("scripts.json"))
    #expect(throws: (any Error).self) { try store.loadScripts() }
    #expect(try Data(contentsOf: root.appendingPathComponent("scripts.json")) == bad)
}

@Test func pendingTakeRemainsDiscoverableAfterRelaunch() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ScriptLibrary(root: root)
    let take = try store.beginTake(scriptTitle: "טייק")
    try Data([1, 2, 3]).write(to: store.movieURL(for: take))
    let reopened = try ScriptLibrary(root: root)
    #expect(try reopened.loadTakes().first?.status == .pending)
    #expect(FileManager.default.fileExists(atPath: reopened.movieURL(for: take).path))
    try reopened.finishTake(id: take.id, duration: 4, interrupted: true)
    #expect(try reopened.loadTakes().first?.status == .interrupted)
}

@Test func canceledCountdownCannotStartRecording() {
    var lifecycle = CaptureLifecycle()
    lifecycle.beginCountdown()
    lifecycle.cancel()
    let started = lifecycle.requestStart()
    #expect(!started)
    #expect(lifecycle.phase == .idle)
}

@Test func interruptionWhileStartingStopsOnDelegateStart() {
    var lifecycle = CaptureLifecycle()
    lifecycle.beginCountdown()
    let requested = lifecycle.requestStart()
    #expect(requested)
    lifecycle.requestStop()
    let playbackAllowed = lifecycle.didStart()
    #expect(!playbackAllowed)
    #expect(lifecycle.phase == .finishing)
    lifecycle.didFinish()
    #expect(lifecycle.phase == .finished)
}

@Test func normalTakeStartsOnlyAfterDelegateAndFinishesOnce() {
    var lifecycle = CaptureLifecycle()
    lifecycle.beginCountdown()
    let requested = lifecycle.requestStart()
    #expect(requested)
    #expect(lifecycle.phase == .starting)
    let playbackAllowed = lifecycle.didStart()
    #expect(playbackAllowed)
    #expect(lifecycle.phase == .recording)
    lifecycle.requestStop()
    #expect(lifecycle.phase == .finishing)
    lifecycle.didFinish()
    #expect(lifecycle.phase == .finished)
}

@Test func cueWeightsAndUnicodeRanges() {
    let cue = WordCue(text: "  א   ארוכהמאוד\nEnglish 👋🏽 123")
    #expect(cue.ranges.count == 5)
    #expect(cue.ranges[0] == NSRange(location: 2, length: 1))
    #expect(cue.index(at: 0) == 0)
    #expect(cue.index(at: 1) == 4)
    #expect(cue.position(for: 2) - cue.position(for: 1) > cue.position(for: 1))
    #expect(cue.index(at: cue.position(for: 3)) == 3)
    #expect(WordCue(text: " \n ").index(at: 0) == nil)
}

@Test func soundGateRequiresFreshSoundAndReleasesAfterShortPause() {
    var gate = SoundGate(threshold: -40)
    #expect(!gate.isOpen(at: 0))
    gate.receive(level: -20, at: 1)
    #expect(gate.isOpen(at: 1.1))
    gate.receive(level: -60, at: 1.1)
    #expect(gate.isOpen(at: 1.15))
    #expect(!gate.isOpen(at: 1.3))
    gate.receive(level: -20, at: 2)
    #expect(!gate.isOpen(at: 2.4))
    gate.receive(level: .nan, at: 3)
    #expect(!gate.isOpen(at: 3))
}

@Test func oldSettingsDecodeWithVoiceFollowDisabled() throws {
    let data = Data("""
    {"mode":"hand","pace":"words","wordsPerMinute":120,"targetSeconds":60,"fontSize":26,"widthFraction":0.86,"backgroundOpacity":0.75,"countdown":3}
    """.utf8)
    var settings = try JSONDecoder().decode(PromptSettings.self, from: data)
    #expect(!settings.followsVoice)
    settings.followsVoice = true
    settings.soundThreshold = -35
    let restored = try JSONDecoder().decode(PromptSettings.self, from: JSONEncoder().encode(settings))
    #expect(restored.followsVoice)
    #expect(restored.soundThreshold == -35)
}

@Test func tappedWordSurvivesPixelRoundTrip() {
    let cue = WordCue(text: "אחד שני שלישי רביעי")
    let pixelOffset = cue.position(for: 3) * 190.5
    #expect(cue.index(at: pixelOffset / 190.5) == 3)
}

@Test func talkingPointsSkipEmptyStagesAndSwitchWithoutLosingText() {
    var script = Script(title: "טבעי", text: "טקסט מלא נשמר")
    script.presentationMode = .talkingPoints
    #expect(!script.canStart)
    script.setPointText("  פתיח טבעי  ", for: .opening)
    script.setPointText(" \n ", for: .pain)
    script.setPointText("הפתרון שלי", for: .solution)
    script.setPointText("הצעה לסיום", for: .offer)
    #expect(script.canStart)
    #expect(script.activeTalkingPoints.map(\.stage) == [.opening, .solution, .offer])
    #expect(script.activeTalkingPoints.first?.text == "פתיח טבעי")
    script.presentationMode = .scrolling
    #expect(script.presentationText == "טקסט מלא נשמר")
    script.presentationMode = .talkingPoints
    #expect(script.pointText(for: .solution) == "הפתרון שלי")
}

@Test func talkingPointStorageAndDuplicatePreserveBothForms() throws {
    var script = Script(title: "מקור", text: "מלל לקריאה")
    script.presentationMode = .talkingPoints
    script.setPointText("פתיח English 123", for: .opening)
    script.settings.followsVoice = true
    let restored = try JSONDecoder().decode(Script.self, from: JSONEncoder().encode(script))
    #expect(restored.presentationMode == .talkingPoints)
    #expect(restored.pointText(for: .opening) == "פתיח English 123")
    let copy = restored.duplicated()
    #expect(copy.id != script.id)
    #expect(copy.text == "מלל לקריאה")
    #expect(copy.activeTalkingPoints == script.activeTalkingPoints)
    #expect(copy.presentationMode == .talkingPoints)
    #expect(copy.settings.followsVoice)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(script)) as? [String: Any])
    json.removeValue(forKey: "savedPresentationMode"); json.removeValue(forKey: "talkingPointTexts")
    let legacy = try JSONDecoder().decode(Script.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(legacy.presentationMode == .scrolling)
    #expect(legacy.text == "מלל לקריאה")
}


private func bridgePayload(_ id: UUID = UUID(), title: String = "מקודקס") throws -> (UUID, Data) {
    let data = try JSONSerialization.data(withJSONObject: ["version": 1, "id": id.uuidString, "title": title,
        "text": "תסריט מלא לקריאה", "points": ["opening": "פתיח", "pain": "כאב", "solution": "פתרון", "offer": "הצעה"], "mode": "scrolling"], options: [.sortedKeys])
    return (id, data)
}
private func stageBridge(_ data: Data, id: UUID, store: ScriptLibrary, ready: Bool = true) throws {
    let name = id.uuidString.lowercased()
    try data.write(to: store.root.appendingPathComponent("Inbox/" + name + ".json"), options: .atomic)
    if ready {
        try Data(CodexTransfer.digest(data).utf8).write(to: store.root.appendingPathComponent("Inbox/" + name + ".ready"), options: .atomic)
    }
}

@Test func inboxImportsOnlyReadyAndPreservesEditsOnReplay() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ScriptLibrary(root: root)
    let (id, data) = try bridgePayload()
    try stageBridge(data, id: id, store: store, ready: false)
    #expect(try store.receiveCodexTransfers().acknowledged.isEmpty)
    #expect(try store.loadScripts().isEmpty)
    try stageBridge(data, id: id, store: store)
    #expect(try store.receiveCodexTransfers().imported == 1)
    var scripts = try store.loadScripts()
    #expect(scripts.first?.title == "מקודקס")
    #expect(scripts.first?.activeTalkingPoints.count == 4)
    scripts[0].text = "עריכה באייפון"
    try store.saveScripts(scripts)
    try stageBridge(data, id: id, store: store)
    #expect(try store.receiveCodexTransfers().imported == 0)
    #expect(try store.loadScripts().first?.text == "עריכה באייפון")
    try store.saveScripts([])
    try stageBridge(data, id: id, store: store)
    #expect(try store.receiveCodexTransfers().acknowledged == [id])
    #expect(try store.loadScripts().isEmpty)
}

@Test func inboxRecoversMissingReceiptWithoutDuplicateAndRejectsChangedID() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ScriptLibrary(root: root)
    let (id, data) = try bridgePayload()
    try stageBridge(data, id: id, store: store)
    _ = try store.receiveCodexTransfers()
    try FileManager.default.removeItem(at: root.appendingPathComponent("Receipts/" + id.uuidString.lowercased() + ".json"))
    try stageBridge(data, id: id, store: store)
    #expect(try store.receiveCodexTransfers().acknowledged == [id])
    #expect(try store.loadScripts().count == 1)
    let (_, changed) = try bridgePayload(id, title: "שינוי לא מאושר")
    try stageBridge(changed, id: id, store: store)
    #expect(try store.receiveCodexTransfers().rejected == 1)
    #expect(try store.loadScripts().first?.title == "מקודקס")
}

@Test func invalidInboxSiblingDoesNotBlockValidOrOverwriteCorruptLibrary() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ScriptLibrary(root: root)
    let (id, data) = try bridgePayload()
    let badID = UUID()
    try stageBridge(data, id: badID, store: store)
    try stageBridge(data, id: id, store: store)
    let result = try store.receiveCodexTransfers()
    #expect(result.imported == 1)
    #expect(result.rejected == 1)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Inbox/" + badID.uuidString.lowercased() + ".json").path))
    let broken = Data("broken manifest".utf8)
    try broken.write(to: root.appendingPathComponent("scripts.json"))
    let (newID, newData) = try bridgePayload()
    try stageBridge(newData, id: newID, store: store)
    _ = try store.receiveCodexTransfers()
    #expect(try Data(contentsOf: root.appendingPathComponent("scripts.json")) == broken)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Receipts/" + newID.uuidString.lowercased() + ".json").path))
}

@Test func transferRejectsChecksumMismatchEmptyFieldsAndUnsupportedVersion() throws {
    let (id, data) = try bridgePayload()
    #expect(throws: (any Error).self) { try CodexTransfer.decode(data, id: id, checksum: String(repeating: "0", count: 64)) }
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json["version"] = 2
    let unsupported = try JSONSerialization.data(withJSONObject: json)
    #expect(throws: (any Error).self) { try CodexTransfer.decode(unsupported, id: id, checksum: CodexTransfer.digest(unsupported)) }
    json["version"] = 1; json["title"] = "  "
    let empty = try JSONSerialization.data(withJSONObject: json)
    #expect(throws: (any Error).self) { try CodexTransfer.decode(empty, id: id, checksum: CodexTransfer.digest(empty)) }
}
