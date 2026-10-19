import SwiftUI

enum LensTheme {
    static let paper = Color(red: 0.96, green: 0.96, blue: 0.93)
    static let ink = Color(red: 0.14, green: 0.19, blue: 0.16)
    static let green = Color(red: 0.19, green: 0.36, blue: 0.28)
    static let pale = Color(red: 0.91, green: 0.94, blue: 0.86)
    static let lime = Color(red: 0.85, green: 0.93, blue: 0.60)
    static func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

struct MainButtonStyle: ButtonStyle {
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(secondary ? LensTheme.green : .white)
            .background(secondary ? LensTheme.pale : LensTheme.green, in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension View {
    func lensError(_ message: Binding<String?>) -> some View {
        alert("לא ניתן להשלים את הפעולה", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("הבנתי", role: .cancel) { message.wrappedValue = nil }
        } message: { Text(message.wrappedValue ?? "") }
    }
}
