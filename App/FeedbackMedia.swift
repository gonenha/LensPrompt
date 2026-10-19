@preconcurrency import AVFoundation
@preconcurrency import Vision
import Foundation
import PrompterCore

struct FeedbackClip: Sendable {
    let url: URL
    let duration: Double
    let byteCount: Int
    let metrics: FeedbackMetrics
}
struct SyntheticVideo: Sendable {
    let url: URL
    let firstColor: String
    let secondColor: String
    let firstBeeps: Int
    let secondBeeps: Int
}
enum FeedbackFailure: LocalizedError {
    case media, duration, size, unsupported, unverified, testFailed, changed
    var errorDescription: String? {
        switch self {
        case .media: "לא ניתן לבדוק את המקטע. נסה לצלם שוב עם מצלמה ומיקרופון פעילים."
        case .duration: "למשוב צריך מקטע של 6–8 שניות. נסה שוב."
        case .size: "לא ניתן להכין מקטע בגודל המתאים לשליחה. לא נשלחה מדיה."
        case .unsupported: "המודל הזה לא אומת לניתוח וידאו וקול. בחר Gemini 4 Argon בהגדרות המשוב."
        case .unverified: "יש לבצע בדיקת ניתוח וידאו בהגדרות לפני שליחת המקטע שלך."
        case .testFailed: "בדיקת קלט הווידאו והקול לא עברה. לא נשלח מקטע אישי. אפשר לבדוק את ההגדרות ולנסות שוב ביוזמתך."
        case .changed: "הספק, המודל או המפתח השתנו. בדוק שוב ואשר שליחה מחדש."
        }
    }
}

actor FeedbackMedia {
    private static let root = URL.cachesDirectory.appendingPathComponent("PracticeFeedback", isDirectory: true)
    static func cleanStaleSessions() {
        // Called once at app startup, never when another feedback session is active.
        try? FileManager.default.removeItem(at: root)
    }
    func makeFolder() throws -> URL {
        let folder = Self.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var value = URLResourceValues(); value.isExcludedFromBackup = true
        var url = folder; try url.setResourceValues(value)
        return folder
    }
    func remove(_ folder: URL) {
        guard folder.deletingLastPathComponent().standardizedFileURL == Self.root.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: folder)
    }
    func bytes(_ clip: FeedbackClip) throws -> Data { try bytes(at: clip.url) }
    func bytes(at url: URL) throws -> Data {
        try Task.checkCancellation()
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 8_000_000 else { throw FeedbackFailure.size }
        return try Data(contentsOf: url)
    }
    func prepare(_ input: URL, in folder: URL) async throws -> FeedbackClip {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: input)
        guard try await asset.load(.isPlayable), !(try await asset.loadTracks(withMediaType: .video)).isEmpty,
              !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else { throw FeedbackFailure.media }
        let seconds = try await asset.load(.duration).seconds
        guard seconds.isFinite, seconds >= 6 else { throw FeedbackFailure.duration }
        let length = min(8, seconds)
        var prepared: URL?
        // The size hint is advisory: same-size exports can preserve the source
        // bitrate. Retry a smaller video preset rather than reject the clip.
        for preset in [AVAssetExportPreset1280x720, AVAssetExportPreset960x540, AVAssetExportPreset640x480] {
            try Task.checkCancellation()
            let candidate = folder.appendingPathComponent("review-" + UUID().uuidString + ".mp4")
            guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else { throw FeedbackFailure.media }
            exporter.outputURL = candidate; exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = true
            exporter.fileLengthLimit = 7_500_000
            exporter.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: length, preferredTimescale: 600))
            try await FeedbackExport(exporter).run()
            try Task.checkCancellation()
            let size = try candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            CaptureTrace.record("media.export preset=\(preset) bytes=\(size)")
            guard size > 0 else { throw FeedbackFailure.media }
            if size <= 8_000_000 { prepared = candidate; break }
            try FileManager.default.removeItem(at: candidate)
        }
        guard let destination = prepared else { throw FeedbackFailure.size }
        let final = AVURLAsset(url: destination)
        let duration = try await final.load(.duration).seconds
        guard FeedbackRules.validDuration(duration), let finalVideo = try await final.loadTracks(withMediaType: .video).first, !(try await final.loadTracks(withMediaType: .audio)).isEmpty else { throw FeedbackFailure.duration }
        let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        CaptureTrace.record("media.export bytes=\(size) duration=\(duration)")
        guard size > 0, size <= 8_000_000 else { throw FeedbackFailure.size }
        let natural = try await finalVideo.load(.naturalSize)
        let transform = try await finalVideo.load(.preferredTransform)
        let dimensions = natural.applying(transform)
        let visual = try frames(final, duration: duration)
        let audio = try sound(final, duration: duration)
        try Task.checkCancellation()
        let metrics = FeedbackMetrics(brightness: visual.brightness, clippedPixels: visual.clippedPixels, sharpness: visual.sharpness, faceCount: visual.faceCount, faceTouchesEdge: visual.edge, silenceFraction: audio.silence, clippingFraction: audio.clipping, width: Int(abs(dimensions.width)), height: Int(abs(dimensions.height)))
        return FeedbackClip(url: destination, duration: duration, byteCount: size, metrics: metrics)
    }
    private func frames(_ asset: AVAsset, duration: Double) throws -> (brightness: Double, clippedPixels: Double, sharpness: Double, faceCount: Int, edge: Bool) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 640, height: 640)
        var brightness = 0.0, clipped = 0.0, sharpness = 0.0
        var singleFace = true, edge = false
        for fraction in [0.1, 0.3, 0.5, 0.7, 0.9] {
            try Task.checkCancellation()
            let image = try generator.copyCGImage(at: CMTime(seconds: duration * fraction, preferredTimescale: 600), actualTime: nil)
            var pixels = [UInt8](repeating: 0, count: 64 * 64)
            let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(data: bytes.baseAddress, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64)); return true
            }
            guard drawn else { throw FeedbackFailure.media }
            brightness += Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count) / 255
            clipped += Double(pixels.filter { $0 >= 250 }.count) / Double(pixels.count)
            var differences = 0.0
            for y in 1..<63 { for x in 1..<63 {
                let i = y * 64 + x
                differences += abs(Double(pixels[i - 1]) + Double(pixels[i + 1]) + Double(pixels[i - 64]) + Double(pixels[i + 64]) - 4 * Double(pixels[i]))
            } }
            sharpness += differences / Double(62 * 62)
            let request = VNDetectFaceRectanglesRequest()
            // Some simulator/device configurations cannot create a Vision context.
            // Preserve other measurements and report framing as unknown.
            try? VNImageRequestHandler(cgImage: image).perform([request])
            if let faces = request.results, faces.count == 1, let face = faces.first, face.confidence >= 0.6 {
                let box = face.boundingBox
                edge = edge || box.minX < 0.04 || box.maxX > 0.96 || box.maxY > 0.96
            } else { singleFace = false }
        }
        return (brightness / 5, clipped / 5, sharpness / 5, singleFace ? 1 : 0, edge)
    }
    private func sound(_ asset: AVAsset, duration: Double) throws -> (silence: Double, clipping: Double) {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
        guard let track = asset.tracks(withMediaType: .audio).first else { throw FeedbackFailure.media }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1])
        guard reader.canAdd(output) else { throw FeedbackFailure.media }
        reader.add(output); guard reader.startReading() else { throw FeedbackFailure.media }
        defer { reader.cancelReading() }
        var total = 0, quiet = 0, clipped = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { throw FeedbackFailure.media }
            let length = CMBlockBufferGetDataLength(block)
            var values = [Float](repeating: 0, count: length / 4)
            let status = values.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            guard status == kCMBlockBufferNoErr else { throw FeedbackFailure.media }
            total += values.count
            clipped += values.filter { abs($0) >= 0.99 }.count
            let rms = sqrt(values.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, values.count)))
            if rms < 0.015 { quiet += values.count }
        }
        guard reader.status != .failed, total > 0 else { throw FeedbackFailure.media }
        return (Double(quiet) / Double(total), Double(clipped) / Double(total))
    }
    func synthetic(in folder: URL) async throws -> SyntheticVideo {
        let reversed = Bool.random()
        let first = reversed ? "blue" : "red", second = reversed ? "red" : "blue"
        let oneFirst = Bool.random(), firstBeeps = oneFirst ? 1 : 2, secondBeeps = oneFirst ? 2 : 1
        let silent = folder.appendingPathComponent("synthetic-silent.mov")
        let writer = try AVAssetWriter(outputURL: silent, fileType: .mov)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 160])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 160])
        writer.add(input); guard writer.startWriting() else { throw FeedbackFailure.media }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<240 {
            try Task.checkCancellation()
            var waits = 0
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, waits < 500 else { throw FeedbackFailure.media }
                waits += 1; try await Task.sleep(for: .milliseconds(5))
            }
            var optional: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, 160, 160, kCVPixelFormatType_32ARGB, nil, &optional) == kCVReturnSuccess, let buffer = optional else { throw FeedbackFailure.media }
            CVPixelBufferLockBaseAddress(buffer, [])
            let red = frame < 120 ? first == "red" : second == "red"
            if let address = CVPixelBufferGetBaseAddress(buffer) {
                let stride = CVPixelBufferGetBytesPerRow(buffer)
                let p = address.assumingMemoryBound(to: UInt8.self)
                for y in 0..<160 { for x in 0..<160 {
                    let i = y * stride + x * 4; p[i] = 255; p[i+1] = red ? 255 : 0; p[i+2] = 0; p[i+3] = red ? 0 : 255
                } }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw FeedbackFailure.media }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw FeedbackFailure.media }
        let wave = folder.appendingPathComponent("synthetic.wav")
        try Self.wave(first: firstBeeps, second: secondBeeps).write(to: wave)
        let videoAsset = AVURLAsset(url: silent), audioAsset = AVURLAsset(url: wave)
        let composition = AVMutableComposition()
        guard let v = try await videoAsset.loadTracks(withMediaType: .video).first, let a = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw FeedbackFailure.media }
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 8, preferredTimescale: 600))
        try videoTrack.insertTimeRange(range, of: v, at: .zero); try audioTrack.insertTimeRange(range, of: a, at: .zero)
        let url = folder.appendingPathComponent("synthetic.mp4")
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetMediumQuality) else { throw FeedbackFailure.media }
        export.outputURL = url; export.outputFileType = .mp4
        try await FeedbackExport(export).run()
        try Task.checkCancellation(); guard export.status == .completed else { throw FeedbackFailure.media }
        return SyntheticVideo(url: url, firstColor: first, secondColor: second, firstBeeps: firstBeeps, secondBeeps: secondBeeps)
    }
    private static func wave(first: Int, second: Int) -> Data {
        let rate = 16000, count = 8 * rate
        var pcm = Data(capacity: count * 2)
        for i in 0..<count {
            let time = Double(i) / Double(rate), half = time < 4 ? 0.0 : 4.0, beeps = time < 4 ? first : second
            let on = (0..<beeps).contains { n in let start = half + 0.8 + Double(n) * 1.2; return time >= start && time < start + 0.35 }
            var value = Int16(on ? sin(2 * .pi * 600 * time) * 16000 : 0).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        append(UInt32(36 + pcm.count)); data.append(Data("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16)); data.append(Data("data".utf8)); append(UInt32(pcm.count)); data.append(pcm)
        return data
    }
}

// AVFoundation supports cancelling an asynchronous export from another queue.
// Only run/cancel cross executors; configuration is complete before this wrapper.
private final class FeedbackExport: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
    func run() async throws {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                session.exportAsynchronously { continuation.resume() }
            }
        } onCancel: { self.session.cancelExport() }
        try Task.checkCancellation()
        guard session.status == .completed else { throw FeedbackFailure.media }
    }
}
