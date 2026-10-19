@preconcurrency import AVFoundation
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

@Test @MainActor func capturePauseFreezesTimerAndPreservesIndependentTextPause() {
    let playback = PlaybackModel()
    playback.start(travel: 100, duration: 10)
    defer { playback.stop() }
    playback.advance(by: 2, at: 2)
    playback.pauseText()
    playback.setCapturePaused(true)
    let elapsed = playback.clock.elapsed
    playback.advance(by: 20, at: 22)
    #expect(playback.clock.elapsed == elapsed)
    #expect(playback.clock.offset == 20)
    playback.setCapturePaused(false)
    playback.advance(by: 1, at: 23)
    #expect(playback.clock.isPaused)
    #expect(playback.clock.elapsed == elapsed + 1)
    #expect(playback.clock.offset == 20)
    playback.pauseText(); playback.advance(by: 1, at: 24)
    #expect(playback.clock.offset == 30)
}

@Test @MainActor func pausedPracticeCanFinishAndCannotMoveTalkingPoint() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = LibraryModel(disk: try ScriptLibrary(root: root))
    var script = Script(title: "Pause")
    script.presentationMode = .talkingPoints
    script.setPointText("first", for: .opening); script.setPointText("next", for: .offer)
    let model = RecordingModel(library: library, camera: CameraModel(), script: script, practice: true)
    defer { model.leave() }
    model.begin(travel: 100)
    try await Task.sleep(for: .milliseconds(100))
    model.toggleRecordingPause()
    #expect(model.lifecycle.phase == .paused)
    let elapsed = model.playback.clock.elapsed
    model.playback.advance(by: 10, at: 10); model.movePoint(by: 1)
    #expect(model.pointIndex == 0); #expect(model.playback.clock.elapsed == elapsed)
    model.toggleRecordingPause(); #expect(model.lifecycle.phase == .recording)
    model.movePoint(by: 1); #expect(model.pointIndex == 1)
    model.toggleRecordingPause(); model.stop()
    #expect(model.finished); #expect(model.lifecycle.phase == .finished)
}

@Test @MainActor func deletingSelectedTakeReloadsLibraryAndReportsMissingTake() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = LibraryModel(disk: try ScriptLibrary(root: root))
    let first = try library.disk.beginTake(scriptTitle: "delete")
    let other = try library.disk.beginTake(scriptTitle: "keep")
    try Data([1]).write(to: library.disk.movieURL(for: first))
    try Data([2]).write(to: library.disk.movieURL(for: other))
    library.reloadTakes()
    #expect(library.deleteTake(first))
    #expect(library.takes.map(\.id) == [other.id])
    #expect(!library.deleteTake(first))
    #expect(library.error != nil)
    #expect(try Data(contentsOf: library.disk.movieURL(for: other)) == Data([2]))
}


@MainActor private func makeReviewFixture(at url: URL) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? MovieError.invalid }
    writer.startSession(atSourceTime: .zero)
    var buffer: CVPixelBuffer?
    guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess, let buffer else { throw MovieError.invalid }
    CVPixelBufferLockBaseAddress(buffer, [])
    if let bytes = CVPixelBufferGetBaseAddress(buffer) { memset(bytes, 100, CVPixelBufferGetDataSize(buffer)) }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    for frame in 0..<30 {
        var waits = 0
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing, waits < 500 else { throw writer.error ?? MovieError.invalid }
            waits += 1; try await Task.sleep(for: .milliseconds(10))
        }
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw writer.error ?? MovieError.invalid }
    }
    input.markAsFinished(); await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? MovieError.invalid }
}

@Test @MainActor func finalizedMovieIsReadyForImmediateReview() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = LibraryModel(disk: try ScriptLibrary(root: root))
    let take = try library.disk.beginTake(scriptTitle: "review")
    let url = library.disk.movieURL(for: take)
    try await makeReviewFixture(at: url)
    let model = RecordingModel(library: library, camera: CameraModel(), script: .sample, practice: false)
    model.take = take
    #expect(model.reviewableTake == nil)
    await model.captureFinished(url: url, captureError: nil, usable: true)
    #expect(model.finished); #expect(model.reviewableTake?.status == .ready)
    #expect((model.reviewableTake?.duration ?? 0) > 0)
    #expect(library.takes.first?.id == take.id)
    #expect(!model.camera.previewAvailable)
    // Seed generated, silent test media ONLY into the simulator app for the UI review test.
    #if targetEnvironment(simulator)
    let simulatorStore = try ScriptLibrary(root: URL.documentsDirectory.appendingPathComponent("LensPrompt"))
    for existing in try simulatorStore.loadTakes() where existing.scriptTitle == "בדיקת סרטון — סימולטור" { try simulatorStore.deleteTake(id: existing.id) }
    let fixture = try simulatorStore.beginTake(scriptTitle: "בדיקת סרטון — סימולטור")
    try FileManager.default.copyItem(at: url, to: simulatorStore.movieURL(for: fixture))
    try simulatorStore.finishTake(id: fixture.id, duration: model.reviewableTake?.duration ?? 1, interrupted: false)
    let groupID = UUID(uuidString: "A580DC69-2F6D-48EB-AFCF-5417C3D0865E")!
    let groupedScript = Script(id: groupID, title: "בדיקת קבוצת טייקים", text: "מלל לבדיקה")
    var scripts = try simulatorStore.loadScripts().filter { $0.id != groupID }
    scripts.append(groupedScript); try simulatorStore.saveScripts(scripts)
    for existing in try simulatorStore.loadTakes() where existing.scriptID == groupID { try simulatorStore.deleteTake(id: existing.id) }
    for _ in 0..<2 {
        let groupedTake = try simulatorStore.beginTake(scriptID: groupID, scriptTitle: groupedScript.title)
        try FileManager.default.copyItem(at: url, to: simulatorStore.movieURL(for: groupedTake))
        try simulatorStore.finishTake(id: groupedTake.id, duration: 1, interrupted: false)
    }
    #endif
}

@Test @MainActor func canceledOrDismissedRetakePreparationCannotStart() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = LibraryModel(disk: try ScriptLibrary(root: root))
    let model = RecordingModel(library: library, camera: CameraModel(), script: .sample, practice: true)
    model.finished = true
    let canceled = Task { @MainActor in await model.prepareRetake() }
    canceled.cancel()
    #expect(await canceled.value == false)
    model.leave()
    let afterDismiss = await model.prepareRetake()
    #expect(!afterDismiss)
    #expect(!model.playback.isRunning)
}

@Test @MainActor func groupedTakesAndRatingsReloadFromDisk() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = LibraryModel(disk: try ScriptLibrary(root: root))
    let script = Script(title: "אותו תסריט")
    let twin = Script(title: script.title)
    library.upsert(script); library.upsert(twin)
    let first = try library.disk.beginTake(scriptID: script.id, scriptTitle: script.title)
    _ = try library.disk.beginTake(scriptID: script.id, scriptTitle: script.title)
    _ = try library.disk.beginTake(scriptID: twin.id, scriptTitle: twin.title)
    library.reloadTakes()
    #expect(library.takeGroups.count == 2)
    #expect(library.takes(for: script.id).count == 2)
    #expect(library.rateTake(first, rating: .good))
    #expect(LibraryModel(disk: library.disk).takes.first(where: { $0.id == first.id })?.rating == .good)
    #expect(library.rateTake(first, rating: .poor))
    #expect(library.takes.first(where: { $0.id == first.id })?.rating == .poor)
    var renamed = script; renamed.title = "שם חדש"; library.upsert(renamed)
    #expect(library.takeGroups.first(where: { $0.scriptID == script.id })?.title == "שם חדש")
}

@Test @MainActor func preparationIsImmediateDeduplicatedAndCancelable() async {
    let state = CapturePreparation()
    var calls = 0
    var presented = 0
    state.begin(operation: { calls += 1; return true }, ready: { presented += 1 })
    #expect(state.busy)
    state.begin(operation: { calls += 1; return true }, ready: { presented += 1 })
    for _ in 0..<10 { await Task.yield() }
    #expect(calls == 1)
    #expect(presented == 1)
    #expect(state.busy)
    state.didPresent()
    #expect(!state.busy)
    state.begin(operation: { try? await Task.sleep(for: .seconds(10)); return true }, ready: { presented += 1 })
    state.cancel()
    for _ in 0..<10 { await Task.yield() }
    #expect(!state.busy)
    #expect(presented == 1)
}

@Test @MainActor func providerContractsKeepCredentialsOutOfURLsAndRejectTruncation() throws {
    let source = Script(title: "מקור", text: "תוכן")
    for provider in AIProvider.allCases {
        let request = try AIContract.request(provider: provider, model: provider.defaultModel, key: "fixture-secret", source: source)
        #expect(request.url?.scheme == "https")
        #expect(request.url?.query == nil)
        #expect(!request.url!.absoluteString.contains("fixture-secret"))
        #expect(!String(decoding: request.httpBody!, as: UTF8.self).contains("fixture-secret"))
        #expect(throws: (any Error).self) { try AIContract.output(provider: provider, data: Data("{}".utf8)) }
    }
}

@Test @MainActor func keychainReplaceDeleteAndNoPlaintextPersistence() throws {
    let store = APIKeyStore(service: "lensprompt.tests." + UUID().uuidString)
    defer { try? store.delete(.openAI) }
    #expect(try store.read(.openAI) == nil)
    try store.save("dummy-one", provider: .openAI)
    #expect(try store.read(.openAI) == "dummy-one")
    try store.save("dummy-two", provider: .openAI)
    #expect(try store.read(.openAI) == "dummy-two")
    #expect(try store.read(.gemini) == nil)
    try store.delete(.openAI)
    #expect(try store.read(.openAI) == nil)
}

@Test @MainActor func providerOutputsAcceptOnlyCompleteText() throws {
    let payload = "{\"dynamic\":{}}"
    func data(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    let cases: [(AIProvider, [String: Any], String, String)] = [
        (.openAI, ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": payload]]]]], "status", "incomplete"),
        (.gemini, ["candidates": [["finishReason": "STOP", "content": ["parts": [["text": payload]]]]]], "", ""),
        (.claude, ["stop_reason": "end_turn", "content": [["type": "text", "text": payload]]], "stop_reason", "max_tokens")
    ]
    for (provider, body, key, bad) in cases {
        #expect(try AIContract.output(provider: provider, data: data(body)) == Data(payload.utf8))
        var truncated = body
        if provider == .gemini { truncated = ["candidates": [["finishReason": "MAX_TOKENS", "content": ["parts": [["text": payload]]]]]] }
        else { truncated[key] = bad }
        #expect(throws: (any Error).self) { try AIContract.output(provider: provider, data: data(truncated)) }
    }
    #expect(throws: (any Error).self) { try AIContract.request(provider: .gemini, model: "bad/key?secret", key: "fixture", source: nil) }
    #expect(throws: (any Error).self) { try AIContract.output(provider: .openAI, data: data(["status": "completed", "output": [["type": "message", "content": [["type": "refusal", "refusal": "no"]]]]])) }
}

@Test @MainActor func variantBatchIsAtomicAndFamiliesUseIDs() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = LibraryModel(disk: try ScriptLibrary(root: root))
    let source = Script(title: "אותו שם", text: "מקור")
    library.upsert(source)
    library.upsert(Script(title: "אותו שם", text: "אחר"))
    var variants = ScriptStyle.allCases.map { style in
        var script = Script(title: source.title, text: "נוסח חדש")
        script.sourceScriptID = source.id; script.scriptStyle = style; return script
    }
    let before = library.scripts
    let file = root.appendingPathComponent("scripts.json")
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
    #expect(!library.saveVariants(variants))
    #expect(library.scripts == before)
    try FileManager.default.removeItem(at: file)
    #expect(library.saveVariants(variants))
    #expect(library.scriptFamilies.first(where: { $0.id == source.id })?.scripts.count == 4)
    #expect(library.scripts.first(where: { $0.id == source.id })?.text == "מקור")
    variants[0].text = "עריכה עצמאית"; library.upsert(variants[0])
    #expect(try library.disk.loadScripts().first(where: { $0.id == variants[0].id })?.text == "עריכה עצמאית")
    #expect(!library.saveVariants(variants))
}

@Test @MainActor func speakingPointsOnlyCanGenerateAndInputIsBounded() throws {
    var source = Script(title: "נקודות בלבד")
    source.presentationMode = .talkingPoints
    source.setPointText("הפתיח שלי", for: .opening)
    #expect(AIContract.canGenerate(source))
    for provider in AIProvider.allCases {
        #expect(try AIContract.request(provider: provider, model: provider.defaultModel, key: "dummy", source: source).httpBody != nil)
    }
    source.setPointText(String(repeating: "א", count: 20_001), for: .pain)
    #expect(!AIContract.canGenerate(source))
}

private final class AITransportFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = request.url!.path == "/quota" ? 429 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"safe\":true}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test @MainActor func transportUsesInjectedSessionAndSanitizesErrors() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AITransportFixture.self]
    let client = AIClient(configuration: config)
    let data = try await client.send(URLRequest(url: URL(string: "https://fixture.invalid/success")!))
    #expect(String(decoding: data, as: UTF8.self) == "{\"safe\":true}")
    do {
        _ = try await client.send(URLRequest(url: URL(string: "https://fixture.invalid/quota")!))
        Issue.record("Expected quota failure")
    } catch let error as AIError {
        guard case .quota = error else { Issue.record("Incorrect error"); return }
    }
    let redirectAllowed = await withCheckedContinuation { continuation in
        let session = URLSession.shared
        let task = session.dataTask(with: URL(string: "https://fixture.invalid")!)
        let response = HTTPURLResponse(url: URL(string: "https://fixture.invalid")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        NoRedirects().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://other.invalid")!)) { continuation.resume(returning: $0 != nil) }
    }
    #expect(!redirectAllowed)
}

@Test @MainActor func canceledPreparationIgnoresLatePermissionCompletion() async {
    let state = CapturePreparation()
    var pending: CheckedContinuation<Bool, Never>?
    var presented = 0
    state.begin(operation: { await withCheckedContinuation { pending = $0 } }, ready: { presented += 1 })
    while pending == nil { await Task.yield() }
    state.cancel()
    state.begin(operation: { true }, ready: { presented += 10 })
    for _ in 0..<10 { await Task.yield() }
    pending?.resume(returning: true)
    for _ in 0..<10 { await Task.yield() }
    #expect(presented == 10)
    #expect(state.busy)
    state.didPresent()
    #expect(!state.busy)
}
