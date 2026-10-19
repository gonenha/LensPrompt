import SwiftUI
import AVFoundation

private final class PreviewHost: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> UIView {
        let view = PreviewHost(); view.backgroundColor = .black
        view.preview.session = session; view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? PreviewHost, let connection = view.preview.connection else { return }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = true
        }
    }
}
