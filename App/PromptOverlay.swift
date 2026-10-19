import SwiftUI

private struct PromptLabel: UIViewRepresentable {
    let layout: PromptLayout
    var currentWord: Int?
    var onSelect: ((Int) -> Void)?
    @MainActor final class Coordinator: NSObject {
        var attributed: NSAttributedString?
        var layout: PromptLayout?
        var highlighted: Int?
        var onSelect: ((Int) -> Void)?
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? UITextView,
                  let index = layout?.wordIndex(at: gesture.location(in: view)) else { return }
            onSelect?(index)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false; view.isSelectable = false; view.isScrollEnabled = false
        view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.backgroundColor = .clear; view.isAccessibilityElement = true
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.layout = layout; coordinator.onSelect = onSelect
        if coordinator.attributed !== layout.attributed {
            view.attributedText = layout.attributed; view.accessibilityLabel = layout.attributed.string
            coordinator.attributed = layout.attributed; coordinator.highlighted = nil
        }
        guard coordinator.highlighted != currentWord else { return }
        view.textStorage.beginEditing()
        if let old = coordinator.highlighted, layout.wordRanges.indices.contains(old) {
            view.textStorage.removeAttribute(.backgroundColor, range: layout.wordRanges[old])
            view.textStorage.addAttribute(.foregroundColor, value: UIColor.white, range: layout.wordRanges[old])
        }
        if let index = currentWord, layout.wordRanges.indices.contains(index) {
            view.textStorage.addAttributes([.backgroundColor: UIColor(LensTheme.lime), .foregroundColor: UIColor.black], range: layout.wordRanges[index])
        }
        view.textStorage.endEditing()
        coordinator.highlighted = currentWord
    }
}

struct PromptOverlay: View {
    let layout: PromptLayout
    let offset: Double
    let width: CGFloat
    let opacity: Double
    var currentWord: Int? = nil
    var onSelect: ((Int) -> Void)? = nil
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(opacity)
            Rectangle().fill(LensTheme.lime.opacity(0.12)).frame(height: layout.lineHeight)
                .overlay(alignment: .trailing) { Rectangle().fill(LensTheme.lime).frame(width: 3) }.offset(y: 32)
            PromptLabel(layout: layout, currentWord: currentWord, onSelect: onSelect).frame(width: max(1, width - 32), height: layout.height)
                .offset(y: 32 - offset)
                .animation(currentWord == nil ? nil : .easeOut(duration: 0.18), value: offset)
        }.frame(width: width, height: max(190, layout.lineHeight * 3.4), alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .mask { LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.07), .init(color: .black, location: 0.82), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom) }
            .accessibilityIdentifier("prompt-overlay")
    }
}
