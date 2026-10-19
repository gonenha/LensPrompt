import SwiftUI
import PrompterCore

@main
struct LensPromptApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var library: LibraryModel?
    @State private var startupError: String?

    init() {
        FeedbackMedia.cleanStaleSessions()
        do {
            let root = URL.documentsDirectory.appendingPathComponent("LensPrompt", isDirectory: true)
            _library = State(initialValue: LibraryModel(disk: try ScriptLibrary(root: root)))
        } catch { _startupError = State(initialValue: error.localizedDescription) }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let library { LibraryView(library: library) }
                else { ContentUnavailableView("לא ניתן לפתוח אחסון מקומי", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError ?? "יש לנסות לפתוח את האפליקציה מחדש.")) }
            }.environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .preferredColorScheme(.dark)
                .task(id: scenePhase) {
                    guard scenePhase == .active, let library else { return }
                    while !Task.isCancelled {
                        library.receiveCodexInbox()
                        do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    }
                }
        }
    }
}
