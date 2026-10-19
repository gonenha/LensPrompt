import Foundation
import Testing
import AVFoundation
import SwiftUI
import PrompterCore
@testable import LensPrompt

@Test func feedbackSyntheticMediaHasAudioVideoAndLocalMetrics() async throws {
    let media = FeedbackMedia()
    let folder = try await media.makeFolder()
    defer { Task { await media.remove(folder) } }
    let fixture = try await media.synthetic(in: folder)
    let clip = try await media.prepare(fixture.url, in: folder)
    #expect(FeedbackRules.validDuration(clip.duration))
    #expect(clip.byteCount <= 8_000_000)
    #expect(clip.metrics.width > 0)
    #expect(clip.metrics.silenceFraction < 1)
}

@Test @MainActor func videoContractRejectsUnsupportedModelsAndNeverSendsImagesInstead() throws {
    #expect(FeedbackAI.supported(provider: .gemini, model: "gemini-4-argon"))
    #expect(!FeedbackAI.supported(provider: .openAI, model: "gpt-6-luna"))
    #expect(!FeedbackAI.supported(provider: .gemini, model: "unknown"))
    let request = try FeedbackAI.request(model: "gemini-4-argon", key: "dummy-secret", video: Data([1,2,3]), prompt: "fixture", schema: ["type": "object"])
    let body = String(decoding: request.httpBody!, as: UTF8.self)
    let object = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
    let contents = try #require(object["contents"] as? [[String: Any]])
    let parts = try #require(contents.first?["parts"] as? [[String: Any]])
    #expect((parts.first?["inlineData"] as? [String: Any])?["mimeType"] as? String == "video/mp4")
    #expect(!body.contains("image/jpeg"))
    #expect(!body.contains("dummy-secret"))
    #expect(request.url?.query == nil)
    #expect(!FeedbackAI.metadataValid(Data("{}".utf8), model: "gemini-4-argon"))
    #expect(FeedbackAI.metadataValid(Data("{\"name\":\"models/gemini-4-argon\",\"version\":\"4.0\",\"supportedGenerationMethods\":[\"generateContent\"]}".utf8), model: "gemini-4-argon"))
}

private final class VideoProofFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let object: [String: Any]
        if request.httpMethod == "GET" {
            object = ["name": "models/gemini-4-argon", "version": "4.0", "supportedGenerationMethods": ["generateContent"]]
        } else {
            let answer = "{\"firstColor\":\"red\",\"secondColor\":\"blue\",\"firstBeeps\":1,\"secondBeeps\":2}"
            object = ["candidates": [["finishReason": "STOP", "content": ["parts": [["text": answer]]]]]]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: object))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class NoVideoRequests: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Issue.record("A request ran before current capability proof and consent")
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
    override func stopLoading() {}
}

@Test @MainActor func syntheticProofRequiresBothTemporalAndAudibleEvidence() async throws {
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [VideoProofFixture.self]
    let client = AIClient(configuration: config)
    let settings = FeedbackConfiguration(provider: .gemini, model: "gemini-4-argon")
    let url = URL(fileURLWithPath: "/unused-synthetic-fixture.mp4")
    let correct = SyntheticVideo(url: url, firstColor: "red", secondColor: "blue", firstBeeps: 1, secondBeeps: 2)
    let proof = try await FeedbackAI.verify(settings, key: "dummy", fixture: correct, video: Data([1]), client: client)
    #expect(proof.valid(identity: settings.identity(key: "dummy")))
    #expect(proof.modelVersion == "4.0")
    let wrongSound = SyntheticVideo(url: url, firstColor: "red", secondColor: "blue", firstBeeps: 2, secondBeeps: 1)
    do { _ = try await FeedbackAI.verify(settings, key: "dummy", fixture: wrongSound, video: Data([1]), client: client); Issue.record("Wrong audio evidence accepted") }
    catch { #expect(error is FeedbackFailure) }
}

@Test @MainActor func feedbackRequiresConsentAndUnchangedCredentialsWithoutNetwork() async throws {
    let suite = "feedback.tests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = APIKeyStore(service: suite)
    defer { try? store.delete(.gemini) }
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [NoVideoRequests.self]
    let model = FeedbackModel(script: .sample, defaults: defaults, keyStore: store, client: AIClient(configuration: config))
    model.requestAnalysis()
    #expect(!model.showingApproval)
    let metrics = FeedbackMetrics(brightness: 0.5, clippedPixels: 0, sharpness: 5, faceCount: 0, faceTouchesEdge: false, silenceFraction: 0, clippingFraction: 0, width: 720, height: 1280)
    model.clip = FeedbackClip(url: URL(fileURLWithPath: "/unused-review.mp4"), duration: 8, byteCount: 1, metrics: metrics)
    model.phase = .review
    model.analyze() // No approval identity: must do nothing.
    #expect(model.phase == .review)
    try store.save("dummy-key", provider: .gemini)
    model.requestAnalysis()
    #expect(!model.showingApproval) // No capability proof.
    let settings = FeedbackConfiguration.current(defaults: defaults)
    let proof = VideoCapabilityProof(identity: settings.identity(key: "dummy-key"), checkedAt: .now, modelVersion: "4.0")
    defaults.set(try JSONEncoder().encode(proof), forKey: "feedback.proof")
    model.requestAnalysis()
    #expect(model.showingApproval)
    try store.save("changed-dummy-key", provider: .gemini)
    model.analyze()
    for _ in 0..<50 { await Task.yield() }
    #expect(model.phase == .review)
    #expect(model.report == nil)
    #expect(model.error == FeedbackFailure.changed.localizedDescription)
    await model.close()
}

@Test func recordingFailurePreservesSystemDiagnosticAndSuccessFlag() async throws {
    let stream = AsyncStream<CaptureEvent>.makeStream()
    let delegate = MovieDelegate(stream.continuation)
    let url = URL(fileURLWithPath: "/unused-practice.mov")
    let failure = NSError(domain: AVFoundationErrorDomain, code: -11803,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot Record", AVErrorRecordingSuccessfullyFinishedKey: false])
    delegate.fileOutput(AVCaptureMovieFileOutput(), didFinishRecordingTo: url, from: [], error: failure)
    var events = stream.stream.makeAsyncIterator()
    guard case let .finished(received, message, usable) = await events.next() else {
        Issue.record("Missing recording completion"); return
    }
    #expect(received == url)
    #expect(!usable)
    #expect(message?.contains("-11803") == true)
    #expect(message?.contains(AVFoundationErrorDomain) == true)
    #expect(message?.contains("Cannot Record") == true)
}

@Test func movieRecordingOutputStartsWithTheCaptureSession() {
    if #available(iOS 26.0, *) {
        let output = CameraHardware.makeMovieOutput()
        #expect(!output.isDeferredStartEnabled)
    }
}

@Test @MainActor func feedbackKeepsTheSamePreviewAttachedUntilMovieFinishes() async throws {
    let model = FeedbackModel(script: .sample)
    let controller = UIHostingController(rootView: FeedbackView(model: model))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    func previews(in layer: CALayer) -> [AVCaptureVideoPreviewLayer] {
        (layer as? AVCaptureVideoPreviewLayer).map { [$0] } ?? (layer.sublayers ?? []).flatMap { previews(in: $0) }
    }
    try await Task.sleep(for: .milliseconds(150))
    controller.view.layoutIfNeeded()
    let original = try #require(previews(in: controller.view.layer).first)
    #expect(original.session === model.camera.session)
    for phase in [FeedbackModel.Phase.preparing, .recording, .finishing, .processing, .review, .intro] {
        model.phase = phase
        try await Task.sleep(for: .milliseconds(100))
        controller.view.layoutIfNeeded()
        let current = previews(in: controller.view.layer)
        #expect(current.count == 1)
        #expect(current.first === original)
        #expect(original.session === model.camera.session)
    }
    await model.close()
}

@Test func detailedEightSecondVideoFitsTheUploadBudgetWithoutTruncation() async throws {
    let media = FeedbackMedia()
    let folder = try await media.makeFolder()
    defer { Task { await media.remove(folder) } }
    let audioFixture = try await media.synthetic(in: folder)
    let source = folder.appendingPathComponent("detailed.mov")
    let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1280, AVVideoHeightKey: 720, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 25_000_000]])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720])
    writer.add(input)
    #expect(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    var buffers: [CVPixelBuffer] = []
    var random: UInt32 = 42
    for _ in 0..<4 {
        var optional: CVPixelBuffer?
        #expect(CVPixelBufferCreate(kCFAllocatorDefault, 1280, 720, kCVPixelFormatType_32BGRA, nil, &optional) == kCVReturnSuccess)
        let buffer = try #require(optional)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt32.self)
        let row = CVPixelBufferGetBytesPerRow(buffer) / 4
        for y in 0..<720 { for x in 0..<1280 {
            random = random &* 1664525 &+ 1013904223
            base[y * row + x] = 0xff000000 | (random & 0xffffff)
        } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        buffers.append(buffer)
    }
    for frame in 0..<240 {
        var waits = 0
        while !input.isReadyForMoreMediaData {
            try #require(writer.status == .writing && waits < 1000)
            waits += 1; try await Task.sleep(for: .milliseconds(5))
        }
        try #require(adaptor.append(buffers[frame % 4], withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
    }
    input.markAsFinished(); await writer.finishWriting()
    try #require(writer.status == .completed)
    let video = AVURLAsset(url: source), audio = AVURLAsset(url: audioFixture.url)
    let composition = AVMutableComposition()
    let videoSource = try #require(try await video.loadTracks(withMediaType: .video).first)
    let audioSource = try #require(try await audio.loadTracks(withMediaType: .audio).first)
    let videoTrack = try #require(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
    let audioTrack = try #require(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
    let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 8, preferredTimescale: 600))
    try videoTrack.insertTimeRange(range, of: videoSource, at: .zero)
    try audioTrack.insertTimeRange(range, of: audioSource, at: .zero)
    let combined = folder.appendingPathComponent("detailed-audio.mov")
    let exporter = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
    exporter.outputURL = combined; exporter.outputFileType = .mov
    await withCheckedContinuation { continuation in exporter.exportAsynchronously { continuation.resume() } }
    try #require(exporter.status == .completed)
    let clip = try await media.prepare(combined, in: folder)
    #expect(clip.byteCount > 0 && clip.byteCount <= 8_000_000)
    #expect(clip.duration >= 7.9 && clip.duration <= 8.01)
    #expect(clip.metrics.silenceFraction < 1)
}
