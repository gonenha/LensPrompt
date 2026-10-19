import SwiftUI
import AVFoundation
import PrompterCore

@Observable @MainActor
final class RecordingModel {
    let library: LibraryModel
    let camera: CameraModel
    let script: Script
    let practice: Bool
    let playback = PlaybackModel()
    var settings: PromptSettings
    var lifecycle = CaptureLifecycle()
    var countdownRemaining = 0
    var pointIndex = 0
    var isTalkingPoints: Bool { script.presentationMode == .talkingPoints }
    var talkingPoints: [TalkingPoint] { script.activeTalkingPoints }
    var currentPoint: TalkingPoint? {
        talkingPoints.indices.contains(pointIndex) ? talkingPoints[pointIndex] : nil
    }
    private var followsVoice: Bool { !isTalkingPoints && settings.followsVoice }
    func movePoint(by delta: Int) {
        guard isTalkingPoints, lifecycle.phase == .recording, !talkingPoints.isEmpty else { return }
        pointIndex = min(talkingPoints.count - 1, max(0, pointIndex + delta))
    }
    var canPause: Bool {
        if practice { return true }
        if #available(iOS 18.0, *) { return true }
        return false
    }
    var pauseTransition: Bool { lifecycle.phase == .pausing || lifecycle.phase == .resuming }
    var recordingPaused: Bool { lifecycle.phase == .paused || lifecycle.phase == .resuming }
    var reviewableTake: Take? {
        guard finished, !practice, let take, take.status == .ready || take.status == .interrupted else { return nil }
        return take
    }
    var take: Take?
    var finished = false
    var shouldDismiss = false
    var interrupted = false
    var message: String?
    var error: String?
    var voiceNotice: String?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private let monitorOwner = UUID()
    @ObservationIgnored private var travel: Double = 1
    @ObservationIgnored private var started = false
    @ObservationIgnored private var hasLeft = false
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(library: LibraryModel, camera: CameraModel, script: Script, practice: Bool) {
        self.library = library; self.camera = camera; self.script = script; self.practice = practice
        settings = script.settings.validated()
    }

    func begin(travel: Double) {
        guard !started, !hasLeft else { return }
        started = true; self.travel = travel; library.inboxSuspended = true
        lifecycle.beginCountdown()
        camera.onStarted = { [weak self] in self?.captureStarted() }
        camera.onPaused = { [weak self] in self?.capturePaused() }
        camera.onResumed = { [weak self] in self?.captureResumed() }
        camera.onFinished = { [weak self] url, error, usable in
            Task { await self?.captureFinished(url: url, captureError: error, usable: usable) }
        }
        UIApplication.shared.isIdleTimerDisabled = true
        countdownRemaining = practice ? 0 : settings.countdown
        countdownTask = Task { [weak self] in
            guard let self else { return }
            if self.followsVoice {
                do { try await self.camera.startVoiceMonitoring(owner: self.monitorOwner) }
                catch {
                    await self.camera.stopVoiceMonitoring(owner: self.monitorOwner)
                    if !self.practice { _ = await self.camera.prepareRecording() }
                    self.settings.followsVoice = false
                    self.voiceNotice = "המעקב לפי קול אינו זמין כרגע. הגלילה ממשיכה בקצב רגיל."
                }
                guard !Task.isCancelled else { await self.camera.stopVoiceMonitoring(owner: self.monitorOwner); return }
            }
            while self.countdownRemaining > 0 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
                self.countdownRemaining -= 1
            }
            guard !Task.isCancelled, self.lifecycle.requestStart() else { return }
            if self.practice { self.captureStarted(); return }
            do {
                let capacity = try self.library.disk.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                guard capacity > 200_000_000 else { throw CameraFailure.space }
                let take = try self.library.disk.beginTake(scriptTitle: self.script.title)
                self.take = take; self.library.reloadTakes()
                try await self.camera.startMovie(at: self.library.disk.movieURL(for: take))
            } catch {
                if let take = self.take { try? self.library.disk.failTake(id: take.id); self.library.reloadTakes() }
                self.lifecycle.didFinish(); self.finished = true; self.message = "הצילום לא התחיל."
                self.error = error.localizedDescription; self.restoreIdleTimer(); self.endMonitoring()
            }
        }
    }

    private func captureStarted() {
        guard lifecycle.didStart() else { Task { await camera.stopMovie() }; return }
        playback.start(travel: travel, duration: settings.duration(wordCount: script.wordCount), text: script.text, followsVoice: followsVoice, threshold: settings.soundThreshold)
        if isTalkingPoints { playback.clock.isPaused = true }
        if followsVoice {
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let level = await self.camera.audioLevel()
                    guard !Task.isCancelled else { return }
                    self.playback.receiveAudio(level: level.level, at: level.time)
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                }
            }
        }
    }

    func toggleRecordingPause() {
        guard canPause else { return }
        let resuming = lifecycle.phase == .paused
        guard resuming ? lifecycle.requestResume() : lifecycle.requestPause() else { return }
        if practice {
            if resuming { captureResumed() } else { capturePaused() }
            return
        }
        Task {
            do {
                if resuming { try await camera.resumeMovie() } else { try await camera.pauseMovie() }
            } catch {
                guard lifecycle.phase == (resuming ? .resuming : .pausing) else { return }
                lifecycle.cancelPauseTransition()
                self.error = "לא ניתן לשנות את מצב ההקלטה כרגע. אפשר לסיים את הטייק. " + error.localizedDescription
            }
        }
    }
    private func capturePaused() {
        guard lifecycle.didPause() else { return }
        playback.setCapturePaused(true)
    }
    private func captureResumed() {
        guard lifecycle.didResume() else { return }
        playback.setCapturePaused(false)
    }

    func stop(interrupted: Bool = false) {
        self.interrupted = self.interrupted || interrupted
        switch lifecycle.phase {
        case .countdown, .idle:
            countdownTask?.cancel(); lifecycle.cancel(); endMonitoring(); restoreIdleTimer(); shouldDismiss = true
        case .starting, .recording, .pausing, .paused, .resuming:
            lifecycle.requestStop(); playback.stop(); meterTask?.cancel()
            if practice { lifecycle.didFinish(); finished = true; endMonitoring(); restoreIdleTimer() }
            else {
                if backgroundTask == .invalid {
                    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish movie") { [weak self] in
                        Task { @MainActor in self?.endBackgroundTask() }
                    }
                }
                Task { await camera.stopMovie() }
            }
        case .finishing, .finished: break
        }
    }

    func captureFinished(url: URL, captureError: String?, usable: Bool) async {
        playback.stop(); lifecycle.didFinish(); endMonitoring()
        await camera.suspendPreview()
        defer { finished = true; restoreIdleTimer(); endBackgroundTask(); library.reloadTakes() }
        guard let take else { error = "ההקלטה הסתיימה ללא רשומת טייק. הקובץ לא נמחק."; return }
        do {
            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard playable, duration.isFinite, duration > 0, !tracks.isEmpty else { throw MovieError.invalid }
            try library.disk.finishTake(id: take.id, duration: duration, interrupted: interrupted || !usable || captureError != nil)
            self.take = try library.disk.loadTakes().first(where: { $0.id == take.id })
            if interrupted || captureError != nil { message = "הצילום נקטע. החלק התקין נשמר במכשיר." }
        } catch {
            try? library.disk.failTake(id: take.id)
            self.error = "לא ניתן לאשר שהטייק תקין. הקובץ נשמר לבדיקה בטייקים שלי. \(error.localizedDescription)"
        }
    }

    func changeSpeed(_ value: Double) {
        settings.wordsPerMinute = value; settings.pace = .words
        playback.setDuration(settings.duration(wordCount: script.wordCount))
    }
    func prepareRetake() async -> Bool {
        guard finished, !hasLeft, !Task.isCancelled else { return false }
        if !practice {
            let ready = await camera.prepareRecording()
            guard !hasLeft, !Task.isCancelled else {
                await camera.suspendPreview()
                return false
            }
            guard ready else { error = camera.error; return false }
        }
        return !hasLeft && !Task.isCancelled
    }

    func leave() {
        hasLeft = true
        countdownTask?.cancel(); playback.stop(); endMonitoring(); restoreIdleTimer()
        camera.onStarted = nil; camera.onPaused = nil; camera.onResumed = nil; camera.onFinished = nil
        endBackgroundTask()
    }
    private func endMonitoring() {
        meterTask?.cancel(); meterTask = nil
        let camera = camera, owner = monitorOwner
        Task { await camera.stopVoiceMonitoring(owner: owner) }
    }
    private func restoreIdleTimer() { UIApplication.shared.isIdleTimerDisabled = false; library.inboxSuspended = false }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
}

enum MovieError: LocalizedError {
    case invalid
    var errorDescription: String? { "הקובץ אינו מכיל סרטון שניתן לנגן." }
}
