import Testing
import PrompterCore
import SwiftUI
@testable import LensPrompt

@MainActor private func textView(in view: UIView) -> UITextView? {
    if let text = view as? UITextView { return text }
    return view.subviews.lazy.compactMap { textView(in: $0) }.first
}

@Test @MainActor func hebrewPromptFitsInsideBothHorizontalEdges() throws {
    let layout = PromptLayout(text: "עברית ארוכה עם English ומספרים 123 שממלאת שורה שלמה", width: 268, fontSize: 26)
    let host = UIHostingController(rootView: PromptOverlay(layout: layout, offset: 0, width: 300, opacity: 0.75).environment(\.layoutDirection, .rightToLeft))
    host.view.frame = CGRect(x: 0, y: 0, width: 300, height: 250)
    let window = UIWindow(frame: host.view.frame)
    window.rootViewController = host; window.makeKeyAndVisible()
    defer { window.isHidden = true }
    host.view.setNeedsLayout(); host.view.layoutIfNeeded()
    let text = try #require(textView(in: host.view))
    let frame = text.convert(text.bounds, to: host.view)
    #expect(frame.minX >= 16)
    #expect(frame.maxX <= 284)
}

@Test @MainActor func unchangedLongScriptReusesMeasuredLayout() {
    let cache = PromptLayoutCache()
    let text = String(repeating: "מלל ארוך לקריאה English 123 ", count: 500)
    let first = cache.layout(text: text, width: 300, fontSize: 26)
    let nextFrame = cache.layout(text: text, width: 300, fontSize: 26)
    #expect(first === nextFrame)
    let changedWidth = cache.layout(text: text, width: 180, fontSize: 26)
    #expect(changedWidth !== first)
    #expect(changedWidth.height > first.height)
}

@Test @MainActor func voiceCueStopsOnSilenceAndManualPauseButTimerContinues() {
    let playback = PlaybackModel()
    playback.start(travel: 100, duration: 10, text: "אחד שני שלישי רביעי", followsVoice: true)
    defer { playback.stop() }
    playback.advance(by: 1, at: 1)
    #expect(playback.clock.offset == 0)
    #expect(playback.clock.elapsed == 1)
    playback.receiveAudio(level: -20, at: 2)
    playback.advance(by: 1, at: 2)
    #expect(playback.clock.offset == 10)
    playback.pauseText()
    playback.receiveAudio(level: -20, at: 3)
    playback.advance(by: 1, at: 3)
    #expect(playback.clock.offset == 10)
    #expect(playback.clock.elapsed == 3)
    playback.pauseText()
    playback.advance(by: 1, at: 4)
    #expect(playback.clock.offset == 10)
    playback.selectWord(2)
    #expect(playback.currentWord == 2)
    #expect(playback.clock.elapsed == 4)
    playback.resetText()
    #expect(playback.currentWord == 0)
    #expect(playback.clock.elapsed == 4)
}

@Test @MainActor func fixedModeKeepsMovingWithoutAudio() {
    let playback = PlaybackModel()
    playback.start(travel: 100, duration: 10)
    defer { playback.stop() }
    playback.advance(by: 2, at: 2)
    #expect(playback.clock.offset == 20)
    #expect(playback.currentWord == nil)
}

@Test @MainActor func rtlMixedWordHitTestingMatchesMeasuredGlyphs() throws {
    let layout = PromptLayout(text: "שלום English 123\nעוד שורה", width: 268, fontSize: 26)
    #expect(layout.wordRects.count == 5)
    let english = try #require(layout.wordRects[1].first)
    #expect(layout.wordIndex(at: CGPoint(x: english.midX, y: english.midY)) == 1)
    #expect(layout.wordIndex(at: CGPoint(x: 0, y: layout.height + 20)) == nil)
    #expect(layout.wordLineY[3] > layout.wordLineY[0])
}

@Test @MainActor func highlightAndTapCoordinatesMatchRenderedMixedText() throws {
    let layout = PromptLayout(text: "שלום English 123\nעוד שורה", width: 268, fontSize: 26)
    let host = UIHostingController(rootView: PromptOverlay(layout: layout, offset: 0, width: 300, opacity: 0.75, currentWord: 1))
    host.view.frame = CGRect(x: 0, y: 0, width: 300, height: 250)
    let window = UIWindow(frame: host.view.frame)
    window.rootViewController = host; window.makeKeyAndVisible()
    defer { window.isHidden = true }
    host.view.layoutIfNeeded()
    let text = try #require(textView(in: host.view))
    #expect(text.textStorage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? UIColor == UIColor(LensTheme.accent))
    #expect(text.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == UIColor(LensTheme.text))
    text.layoutManager.ensureLayout(for: text.textContainer)
    let glyph = text.layoutManager.glyphRange(forCharacterRange: NSRange(location: 5, length: 7), actualCharacterRange: nil)
    let rect = text.layoutManager.boundingRect(forGlyphRange: glyph, in: text.textContainer)
    #expect(layout.wordIndex(at: CGPoint(x: rect.midX, y: rect.midY)) == 1)
}

@Test @MainActor func manualPointsIgnoreVoiceAndNeverAdvanceWithTime() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = LibraryModel(disk: try ScriptLibrary(root: root))
    var script = Script(title: "טבעי", text: "מלל לקריאה")
    script.presentationMode = .talkingPoints
    script.setPointText("פתיח", for: .opening)
    script.setPointText("פתרון", for: .solution)
    script.setPointText("הצעה", for: .offer)
    script.settings.followsVoice = true
    let model = RecordingModel(library: library, camera: CameraModel(), script: script, practice: true)
    defer { model.leave() }
    model.begin(travel: 100)
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.playback.isRunning)
    #expect(!model.playback.followsVoice)
    #expect(model.currentPoint?.stage == .opening)
    model.playback.advance(by: 10, at: 10)
    #expect(model.currentPoint?.stage == .opening)
    #expect(model.playback.clock.offset == 0)
    let elapsed = model.playback.clock.elapsed
    model.movePoint(by: -1)
    #expect(model.pointIndex == 0)
    model.movePoint(by: 1)
    #expect(model.currentPoint?.stage == .solution)
    model.movePoint(by: 1); model.movePoint(by: 1)
    #expect(model.currentPoint?.stage == .offer)
    #expect(!model.finished)
    #expect(model.playback.clock.elapsed == elapsed)
    model.movePoint(by: -1)
    #expect(model.currentPoint?.stage == .solution)
    let retake = RecordingModel(library: library, camera: CameraModel(), script: script, practice: true)
    #expect(retake.pointIndex == 0)
}

@Test @MainActor func codexInboxWaitsDuringTakeAndUpdatesLibraryAfterwards() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = LibraryModel(disk: try ScriptLibrary(root: root))
    let id = UUID()
    let data = try JSONSerialization.data(withJSONObject: ["version": 1, "id": id.uuidString, "title": "הגיע מקודקס", "text": "תסריט לקריאה",
        "points": ["opening": "פתיח", "pain": "כאב", "solution": "פתרון", "offer": "הצעה"], "mode": "scrolling"])
    let stem = id.uuidString.lowercased()
    try data.write(to: root.appendingPathComponent("Inbox/" + stem + ".json"))
    try Data(CodexTransfer.digest(data).utf8).write(to: root.appendingPathComponent("Inbox/" + stem + ".ready"))
    let model = RecordingModel(library: library, camera: CameraModel(), script: Script.sample, practice: true)
    model.begin(travel: 100)
    defer { model.leave() }
    #expect(library.inboxSuspended)
    library.receiveCodexInbox()
    #expect(!library.scripts.contains(where: { $0.id == id }))
    model.stop()
    #expect(!library.inboxSuspended)
    library.receiveCodexInbox()
    #expect(library.scripts.first?.title == "הגיע מקודקס")
    #expect(library.scripts.first?.activeTalkingPoints.count == 4)
    #expect(library.bridgeNotice != nil)
}

@MainActor private func enqueueTestDraft(_ library: LibraryModel, title: String = "תסריט נכנס") throws -> UUID {
    let id = UUID(), stem: String
    stem = id.uuidString.lowercased()
    let data = try JSONSerialization.data(withJSONObject: ["version": 1, "id": stem, "title": title, "text": "טקסט לקריאה",
        "points": ["opening": "פתיח", "pain": "כאב", "solution": "פתרון", "offer": "הצעה"], "mode": "scrolling"])
    try data.write(to: library.disk.root.appendingPathComponent("Inbox/" + stem + ".json"))
    try Data(CodexTransfer.digest(data).utf8).write(to: library.disk.root.appendingPathComponent("Inbox/" + stem + ".ready"))
    return id
}

@Test @MainActor func receiptFailureCannotResurrectAnImportedScriptAfterDeletion() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = LibraryModel(disk: try ScriptLibrary(root: root))
    let id = try enqueueTestDraft(library)
    let blocked = root.appendingPathComponent("Receipts")
    try FileManager.default.removeItem(at: blocked) // Receipt cannot be written, but scripts.json remains writable.
    library.receiveCodexInbox()
    let script = try #require(library.scripts.first(where: { $0.id == id }))
    library.deleteScript(script)
    #expect(library.scripts.contains(where: { $0.id == id })) // Unsafe deletion must fail visibly until its receipt is durable.
    #expect(library.error != nil)
    try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
    library.deleteScript(script)
    #expect(!library.scripts.contains(where: { $0.id == id }))
    library.receiveCodexInbox()
    #expect(!library.scripts.contains(where: { $0.id == id }))
}

@Test @MainActor func successfulLibrarySaveUnblocksInboxAfterEarlierWriteFailure() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = LibraryModel(disk: try ScriptLibrary(root: root))
    let sample = try #require(library.scripts.first)
    let manifest = root.appendingPathComponent("scripts.json")
    try FileManager.default.removeItem(at: manifest)
    try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
    let unsaved = Script(title: "עריכה שממתינה לשמירה", text: "טקסט מקומי")
    library.upsert(unsaved)
    #expect(library.error != nil)
    try FileManager.default.removeItem(at: manifest)
    library.deleteScript(sample) // Saves all remaining in-memory edits successfully.
    let incoming = try enqueueTestDraft(library)
    library.receiveCodexInbox()
    #expect(library.scripts.contains(where: { $0.id == incoming }))
    #expect(library.scripts.contains(where: { $0.id == unsaved.id }))
}
