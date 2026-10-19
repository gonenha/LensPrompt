import SwiftUI
import Observation

@Observable @MainActor final class CapturePreparation {
    private(set) var busy = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var token = UUID()
    func begin(operation: @escaping @MainActor () async -> Bool, ready: @escaping @MainActor () -> Void) {
        guard !busy else { return }
        busy = true
        let id = UUID(); token = id
        task = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            let success = await operation()
            guard !Task.isCancelled, token == id else { return }
            if success { ready() } else { busy = false }
        }
    }
    func didPresent() { busy = false; task = nil }
    func cancel() { token = UUID(); task?.cancel(); task = nil; busy = false }
}

struct BrandLoadingView: View {
    let title: String
    var cancel: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 22) {
            PulsingLogo(animated: !reduceMotion).frame(width: 58, height: 58).accessibilityHidden(true)
            ProgressView().tint(LensTheme.accent)
            Text(title).font(.headline).multilineTextAlignment(.center)
            if let cancel { Button("ביטול", action: cancel).padding(12) }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LensTheme.background.opacity(0.98)).foregroundStyle(LensTheme.text)
            .accessibilityIdentifier("preparation-loader")
    }
}
private struct PulsingLogo: UIViewRepresentable {
    let animated: Bool
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: UIImage(named: "LensLogo")); view.contentMode = .scaleAspectFit
        view.layer.cornerRadius = 14; view.clipsToBounds = true
        return view
    }
    // UIImageView's intrinsic size is the full asset resolution; honor SwiftUI's
    // proposed bounds so the image cannot expand beyond the loading logo frame.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 58, height: proposal.height ?? 58)
    }
    func updateUIView(_ view: UIImageView, context: Context) {
        if animated && view.layer.animation(forKey: "pulse") == nil {
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.94; pulse.toValue = 1.06; pulse.duration = 0.8
            pulse.autoreverses = true; pulse.repeatCount = .infinity
            view.layer.add(pulse, forKey: "pulse")
        } else if !animated { view.layer.removeAnimation(forKey: "pulse") }
    }
}
