import SwiftUI
import UIKit

enum LensTheme {
    static let background = Color(red: 23/255, green: 25/255, blue: 22/255)
    static let surface = Color(red: 37/255, green: 40/255, blue: 34/255)
    static let text = Color(red: 242/255, green: 241/255, blue: 232/255)
    static let muted = Color(red: 166/255, green: 171/255, blue: 160/255)
    static let accent = Color(red: 214/255, green: 231/255, blue: 135/255)
    static let recording = Color(red: 239/255, green: 112/255, blue: 102/255)
    static let divider = Color(red: 58/255, green: 62/255, blue: 53/255)

    static func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

struct MainButtonStyle: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 24).padding(.vertical, 14).padding(.horizontal, 12)
            .foregroundStyle(secondary ? LensTheme.accent : LensTheme.background)
            .background(secondary ? LensTheme.surface : LensTheme.accent, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(secondary ? LensTheme.divider : .clear))
            .opacity(!isEnabled ? 0.55 : configuration.isPressed ? 0.75 : 1)
    }
}

extension View {
    func lensError(_ message: Binding<String?>) -> some View {
        alert("לא ניתן להשלים את הפעולה", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("הבנתי", role: .cancel) { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "") }
    }
}

struct StudioChoice: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 8)
                .foregroundStyle(selected ? LensTheme.background : LensTheme.muted)
                .background(selected ? LensTheme.accent : LensTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CopyTextButton: View {
    let text: String
    let field: String
    let identifier: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
        } label: {
            Label(copied ? "הועתק" : "העתקה", systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.semibold)).fixedSize(horizontal: true, vertical: true)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(LensTheme.accent)
            .disabled(text.isEmpty)
            .accessibilityLabel("העתקת " + field)
            .accessibilityValue(copied ? "הועתק ללוח" : "")
            .accessibilityIdentifier("copy-" + identifier)
            .onChange(of: text) { _, _ in copied = false }
            .task(id: copied) {
                guard copied else { return }
                do { try await Task.sleep(for: .seconds(2)); copied = false }
                catch { }
            }
    }
}
