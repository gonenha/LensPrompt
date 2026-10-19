import SwiftUI
import AVFoundation
import PrompterCore

@Observable @MainActor final class FeedbackModel {
    enum Phase { case intro, preparing, recording, finishing, processing, review, analyzing, result }
    let script: Script
    let camera = CameraModel()
    let playback = PlaybackModel()
    var phase: Phase = .intro
    var target: FeedbackTarget = .shortVideo
    var clip: FeedbackClip?
    var report: FeedbackReport?
    var elapsed = 0.0
    var pointIndex = 0
    var error: String?
    var approvalIdentity: String?
    var showingApproval = false
    private let media = FeedbackMedia()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keyStore: APIKeyStore
    @ObservationIgnored private let client: AIClient
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var rawURL: URL?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var discarded = false
    @ObservationIgnored private var left = false
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    var busy: Bool { [.preparing, .finishing, .processing, .analyzing].contains(phase) }
    var writing: Bool { phase == .recording || phase == .finishing }
    var findings: [LocalFinding] { clip.map { FeedbackRules.findings($0.metrics, target: target) } ?? [] }
    var currentPoint: TalkingPoint? { script.activeTalkingPoints.indices.contains(pointIndex) ? script.activeTalkingPoints[pointIndex] : nil }
    init(script: Script, defaults: UserDefaults = .standard, keyStore: APIKeyStore = APIKeyStore(), client: AIClient = AIClient()) {
        self.script = script; self.defaults = defaults; self.keyStore = keyStore; self.client = client
        camera.onStarted = { [weak self] in self?.started() }
        camera.onFinished = { [weak self] url, message, usable in
            guard let self else { return }
            Task { await self.finished(url: url, usable: usable, captureError: message) }
        }
    }
    func start(travel: Double) {
        guard phase == .intro, !left else { return }
        camera.onStarted = { [weak self] in self?.started() }
        // Keep the owner alive until its movie delegate finishes, including forced dismissal.
        camera.onFinished = { [self] url, message, usable in Task { await finished(url: url, usable: usable, captureError: message) } }
        phase = .preparing; discarded = false; elapsed = 0; pointIndex = 0
        let id = UUID(); generation = id
        work = Task {
            do {
                let folder = try await media.makeFolder()
                guard !Task.isCancelled, generation == id, !left else { await media.remove(folder); return }
                self.folder = folder
                let url = folder.appendingPathComponent("practice.mov"); rawURL = url
                guard await camera.prepareRecording() else {
                    try Task.checkCancellation()
                    throw CameraFailure.permission
                }
                try Task.checkCancellation()
                guard !left, generation == id else { throw CancellationError() }
                // Mark writing before awaiting the hardware: cancellation may race didStart.
                phase = .recording
                UIApplication.shared.isIdleTimerDisabled = true
                try await camera.startMovie(at: url)
                guard !Task.isCancelled, !discarded, !left else { await camera.stopMovie(); return }
                playback.start(travel: travel, duration: script.settings.duration(wordCount: script.wordCount), text: script.text, followsVoice: false)
                if script.presentationMode == .talkingPoints { playback.clock.isPaused = true }
            } catch {
                guard generation == id else { return }
                await cleanup()
                if !Task.isCancelled, !left { self.error = camera.error ?? error.localizedDescription; phase = .intro }
            }
        }
    }
    private func started() {
        guard phase == .recording, !discarded, !left else { Task { await camera.stopMovie() }; return }
        let began = ProcessInfo.processInfo.systemUptime
        clock = Task {
            while !Task.isCancelled, phase == .recording {
                elapsed = ProcessInfo.processInfo.systemUptime - began
                if elapsed >= 8 { stop(); return }
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
        }
    }
    func stop(discard: Bool = false) {
        guard writing else { if discard { cancelPending() }; return }
        discarded = discarded || discard
        phase = .finishing; clock?.cancel(); playback.stop()
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish practice clip") { [weak self] in
                Task { @MainActor in self?.endBackground() }
            }
        }
        Task { await camera.stopMovie() }
    }

    private func finished(url: URL, usable: Bool, captureError: String?) async {
        guard url == rawURL else { return }
        camera.onFinished = nil; camera.onStarted = nil
        clock?.cancel(); playback.stop()
        await camera.suspendPreview()
        UIApplication.shared.isIdleTimerDisabled = false
        endBackground()
        guard !discarded, !left, usable, let folder else {
            await cleanup()
            if !left { phase = .intro; if !usable && !discarded { error = "לא ניתן להתחיל או להשלים את הקלטת התרגול.\n" + (captureError ?? "המצלמה לא יצרה מקטע תקין.") } }
            return
        }
        phase = .processing
        let id = generation
        work = Task {
            do {
                let result = try await media.prepare(url, in: folder)
                try Task.checkCancellation()
                guard !left, generation == id else { return }
                clip = result; phase = .review
            } catch {
                guard generation == id else { return }
                if !Task.isCancelled, !left { self.error = error.localizedDescription }
                await cleanup()
                if !left, !Task.isCancelled { phase = .intro }
            }
        }
    }
    func movePoint(_ delta: Int) {
        guard phase == .recording, !script.activeTalkingPoints.isEmpty else { return }
        pointIndex = min(script.activeTalkingPoints.count - 1, max(0, pointIndex + delta))
    }
    func delete() {
        guard !writing else { stop(discard: true); return }
        cancelPending()
    }
    func requestAnalysis() {
        guard phase == .review, clip != nil else { return }
        do {
            let config = FeedbackConfiguration.current(defaults: defaults)
            guard FeedbackAI.supported(provider: config.provider, model: config.model) else { throw FeedbackFailure.unsupported }
            guard let key = try keyStore.read(config.provider) else { throw AIError.missingKey }
            guard config.proof(key: key, defaults: defaults) != nil else { throw FeedbackFailure.unverified }
            approvalIdentity = config.identity(key: key); showingApproval = true
        } catch { self.error = error.localizedDescription }
    }
    func analyze() {
        guard phase == .review, let clip, let approved = approvalIdentity else { return }
        showingApproval = false; approvalIdentity = nil; phase = .analyzing
        let id = generation
        work = Task {
            do {
                let config = FeedbackConfiguration.current(defaults: defaults)
                guard let key = try keyStore.read(config.provider), config.identity(key: key) == approved else { throw FeedbackFailure.changed }
                guard config.proof(key: key, defaults: defaults) != nil else { throw FeedbackFailure.unverified }
                let version = try await FeedbackAI.checkMetadata(config, key: key, client: client)
                guard config.proof(key: key, defaults: defaults)?.modelVersion == version else { throw FeedbackFailure.unverified }
                let video = try await media.bytes(clip)
                try Task.checkCancellation()
                let current = FeedbackConfiguration.current(defaults: defaults)
                guard let latestKey = try keyStore.read(current.provider), current.identity(key: latestKey) == approved, config == current, current.proof(key: latestKey, defaults: defaults) != nil else { throw FeedbackFailure.changed }
                let response = try await FeedbackAI.analyze(config, key: latestKey, video: video, metrics: clip.metrics, target: target, client: client)
                try Task.checkCancellation()
                guard !left, generation == id else { return }
                report = response; phase = .result
            } catch {
                guard generation == id, !Task.isCancelled, !left else { return }
                self.error = error.localizedDescription; phase = .review
            }
        }
    }
    func cancelAnalysis() {
        guard phase == .analyzing else { return }
        generation = UUID(); work?.cancel(); phase = .review
    }
    func background() {
        showingApproval = false; approvalIdentity = nil
        if writing { stop(discard: true) }
        else if phase == .analyzing { cancelAnalysis() }
        else if phase == .preparing || phase == .processing { cancelPending() }
    }
    func leave() {
        left = true; showingApproval = false; approvalIdentity = nil
        if writing { stop(discard: true) } else { cancelPending() }
    }
    func close() async {
        leave()
        await cleanupTask?.value
    }
    private func cancelPending() {
        guard cleanupTask == nil else { return }
        phase = .processing
        generation = UUID()
        let pending = work; pending?.cancel(); work = nil
        clock?.cancel(); playback.stop()
        cleanupTask = Task { [self] in
            await pending?.value
            await cleanup()
            if !left { phase = .intro }
            cleanupTask = nil
        }
    }
    private func cleanup() async {
        camera.onFinished = nil; camera.onStarted = nil
        await camera.suspendPreview()
        if let folder { await media.remove(folder) }
        folder = nil; rawURL = nil; clip = nil; report = nil; elapsed = 0
        UIApplication.shared.isIdleTimerDisabled = false
        endBackground()
    }
    private func endBackground() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
}
