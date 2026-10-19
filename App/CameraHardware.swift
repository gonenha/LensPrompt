@preconcurrency import AVFoundation
import Foundation
import os
import QuartzCore

enum CaptureEvent: Sendable {
    case started
    case finished(URL, error: String?, usable: Bool)
}

private final class MovieDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, Sendable {
    let continuation: AsyncStream<CaptureEvent>.Continuation
    init(_ continuation: AsyncStream<CaptureEvent>.Continuation) { self.continuation = continuation }
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        continuation.yield(.started)
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: (any Error)?) {
        let nsError = error as NSError?
        let usable = error == nil || (nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        continuation.yield(.finished(url, error: error?.localizedDescription, usable: usable))
    }
}

struct MeterReading: Sendable {
    let level: Double
    let time: Double
}

private final class MeterDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, Sendable {
    private let reading = OSAllocatedUnfairLock(initialState: MeterReading(level: -.infinity, time: 0))
    func reset() { reading.withLock { $0 = MeterReading(level: -.infinity, time: 0) } }
    func latest() -> MeterReading { reading.withLock { $0 } }
    // Only a scalar level and timestamp cross the queue; no practice audio is saved.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let level = Double(connection.audioChannels.map(\.averagePowerLevel).max() ?? -.infinity)
        reading.withLock { $0 = MeterReading(level: level, time: CACurrentMediaTime()) }
    }
}

/// Session mutations run on this actor, never on the UI thread. The preview layer only reads session output.
actor CameraHardware {
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated let events: AsyncStream<CaptureEvent>
    private let delegate: MovieDelegate
    private let output = AVCaptureMovieFileOutput()
    private let meter = AVCaptureAudioDataOutput()
    private let meterDelegate = MeterDelegate()
    private let meterQueue = DispatchQueue(label: "personal.lensprompt.meter")
    private var meterConfigured = false
    private var monitorOwner: UUID?
    private var microphoneInput: AVCaptureDeviceInput?
    private var videoConfigured = false
    private var microphoneConfigured = false

    init() {
        let stream = AsyncStream<CaptureEvent>.makeStream()
        events = stream.stream; delegate = MovieDelegate(stream.continuation)
    }

    func preparePreview() throws {
        if !videoConfigured {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                throw CameraFailure.unavailable
            }
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
            guard session.canAddInput(input), session.canAddOutput(output) else { throw CameraFailure.unavailable }
            session.addInput(input); session.addOutput(output)
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false
                }
            }
            try device.lockForConfiguration()
            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            }
            device.unlockForConfiguration(); videoConfigured = true
        }
        if !session.isRunning { session.startRunning() }
    }

    func prepareMicrophone() throws {
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try AVAudioSession.sharedInstance().setActive(true)
        guard !microphoneConfigured else { return }
        guard let device = AVCaptureDevice.default(for: .audio) else { throw CameraFailure.microphone }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration(); defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { throw CameraFailure.microphone }
        session.addInput(input); microphoneInput = input; microphoneConfigured = true
    }

    func startVoiceMonitoring(owner: UUID) throws {
        monitorOwner = owner
        try prepareMicrophone()
        if !meterConfigured {
            session.beginConfiguration()
            guard session.canAddOutput(meter) else { session.commitConfiguration(); throw CameraFailure.microphone }
            meterDelegate.reset()
            meter.setSampleBufferDelegate(meterDelegate, queue: meterQueue)
            session.addOutput(meter); meterConfigured = true
            session.commitConfiguration()
        }
        if !session.isRunning { session.startRunning() }
    }
    func audioLevel() -> MeterReading {
        guard meterConfigured, session.isRunning else { return MeterReading(level: -.infinity, time: 0) }
        return meterDelegate.latest()
    }
    func stopVoiceMonitoring(owner: UUID) {
        guard monitorOwner == owner else { return }
        monitorOwner = nil
        session.beginConfiguration()
        if meterConfigured {
            session.removeOutput(meter); meter.setSampleBufferDelegate(nil, queue: nil); meterConfigured = false
        }
        if !output.isRecording, let microphoneInput {
            session.removeInput(microphoneInput); self.microphoneInput = nil; microphoneConfigured = false
        }
        session.commitConfiguration()
        if !output.isRecording {
            if !videoConfigured, session.isRunning { session.stopRunning() }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func startMovie(at url: URL) throws {
        guard session.isRunning, videoConfigured, microphoneConfigured, !output.isRecording else { throw CameraFailure.unavailable }
        output.startRecording(to: url, recordingDelegate: delegate)
    }
    func stopMovie() { if output.isRecording { output.stopRecording() } }
    func suspend() {
        guard !output.isRecording else { output.stopRecording(); return }
        if session.isRunning { session.stopRunning() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum CameraFailure: LocalizedError {
    case unavailable, microphone, permission, space
    var errorDescription: String? {
        switch self {
        case .unavailable: "המצלמה אינה זמינה כרגע. אפשר להמשיך בתרגול ללא צילום."
        case .microphone: "לא ניתן לחבר מיקרופון להקלטה."
        case .permission: "כדי לצלם יש לאפשר גישה למצלמה ולמיקרופון בהגדרות. התרגול נשאר זמין."
        case .space: "אין מספיק מקום פנוי להתחלת צילום. יש לפנות לפחות 200MB ולנסות שוב."
        }
    }
}
