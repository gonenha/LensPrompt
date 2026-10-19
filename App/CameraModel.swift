@preconcurrency import AVFoundation
import Observation
import UIKit

@Observable @MainActor
final class CameraModel {
    private let hardware = CameraHardware()
    var session: AVCaptureSession { hardware.session }
    var previewAvailable = false
    var preparing = false
    var permissionDenied = false
    var notice: String? = "המצלמה תיפתח לאחר אישור גישה. אפשר לתרגל גם בלי מצלמה."
    var error: String?
    @ObservationIgnored var onStarted: (() -> Void)?
    @ObservationIgnored var onPaused: (() -> Void)?
    @ObservationIgnored var onResumed: (() -> Void)?
    @ObservationIgnored var onFinished: ((URL, String?, Bool) -> Void)?
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    init() {
        let events = hardware.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .started: self.onStarted?()
                case .paused: self.onPaused?()
                case .resumed: self.onResumed?()
                case .finished(let url, let message, let usable): self.onFinished?(url, message, usable)
                }
            }
        }
    }
    deinit { eventTask?.cancel() }

    func preparePreviewIfAuthorized() async {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            previewAvailable = false
            permissionDenied = AVCaptureDevice.authorizationStatus(for: .video) == .denied
            return
        }
        do { try await hardware.preparePreview(); previewAvailable = true; notice = nil }
        catch { previewAvailable = false; notice = error.localizedDescription }
    }

    func prepareRecording() async -> Bool {
        guard !preparing else { return false }
        preparing = true; defer { preparing = false }
        #if targetEnvironment(simulator)
        error = "בסימולטור אין מצלמת אייפון אמיתית. התסריטים והתרגול זמינים; צילום נבדוק על האייפון."
        return false
        #else
        let video = await permission(.video)
        let audio = video ? await permission(.audio) : false
        guard video && audio else { permissionDenied = true; error = CameraFailure.permission.localizedDescription; return false }
        permissionDenied = false
        do {
            try await hardware.preparePreview(); try await hardware.prepareMicrophone()
            previewAvailable = true; notice = nil; return true
        } catch { self.error = error.localizedDescription; return false }
        #endif
    }

    func allowVoicePractice() async -> Bool { await permission(.audio) }
    func startVoiceMonitoring(owner: UUID) async throws { try await hardware.startVoiceMonitoring(owner: owner) }
    func stopVoiceMonitoring(owner: UUID) async { await hardware.stopVoiceMonitoring(owner: owner) }
    func audioLevel() async -> MeterReading { await hardware.audioLevel() }

    private func permission(_ media: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: media)
        default: false
        }
    }
    func startMovie(at url: URL) async throws { try await hardware.startMovie(at: url) }
    func pauseMovie() async throws { try await hardware.pauseMovie() }
    func resumeMovie() async throws { try await hardware.resumeMovie() }
    func stopMovie() async { await hardware.stopMovie() }
    func suspendPreview() async { await hardware.suspend(); previewAvailable = false }
}
