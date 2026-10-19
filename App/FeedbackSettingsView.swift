import SwiftUI
import PrompterCore

@Observable @MainActor final class FeedbackVerifier {
    var busy = false
    var error: String?
    var status = "טרם אומתה יכולת וידאו וקול"
    @ObservationIgnored private var work: Task<Void, Never>?
    private let media = FeedbackMedia()
    func refresh() {
        let config = FeedbackConfiguration.current()
        guard FeedbackAI.supported(provider: config.provider, model: config.model) else { status = "מודל זה אינו נתמך כרגע לניתוח וידאו וקול"; return }
        if let key = try? APIKeyStore().read(config.provider), let proof = config.proof(key: key) {
            status = "בדיקת קלט וידאו וקול עברה · " + proof.checkedAt.formatted(date: .abbreviated, time: .shortened)
        } else { status = "טרם אומתה יכולת וידאו וקול, או שהבדיקה פגה" }
    }
    func verify() {
        guard !busy else { return }
        busy = true
        work = Task {
            var folder: URL?
            do {
                let config = FeedbackConfiguration.current()
                guard FeedbackAI.supported(provider: config.provider, model: config.model) else { throw FeedbackFailure.unsupported }
                guard let key = try APIKeyStore().read(config.provider) else { throw AIError.missingKey }
                let directory = try await media.makeFolder(); folder = directory
                let fixture = try await media.synthetic(in: directory)
                let bytes = try await media.bytes(at: fixture.url)
                try Task.checkCancellation()
                guard let currentKey = try APIKeyStore().read(config.provider), config == FeedbackConfiguration.current(), config.identity(key: currentKey) == config.identity(key: key) else { throw FeedbackFailure.changed }
                let proof = try await FeedbackAI.verify(config, key: key, fixture: fixture, video: bytes)
                try Task.checkCancellation()
                guard config == FeedbackConfiguration.current(), let latest = try APIKeyStore().read(config.provider), proof.valid(identity: config.identity(key: latest)) else { throw FeedbackFailure.changed }
                UserDefaults.standard.set(try JSONEncoder().encode(proof), forKey: "feedback.proof")
                refresh()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if let folder { await media.remove(folder) }
            busy = false
        }
    }
    func cancel() { work?.cancel() }
}

struct FeedbackSettingsView: View {
    @AppStorage("feedback.provider") private var selected = "gemini"
    @AppStorage("feedback.model") private var model = "gemini-4-argon"
    @State private var verifier = FeedbackVerifier()
    @State private var confirming = false
    @Environment(\.scenePhase) private var scenePhase
    private var provider: AIProvider { AIProvider(rawValue: selected) ?? .gemini }
    var body: some View {
        Form {
            Section("מודל למשוב צילום") {
                Picker("ספק", selection: $selected) { ForEach(AIProvider.allCases) { Text($0.title).tag($0.rawValue) } }.disabled(verifier.busy)
                HStack {
                    TextField("שם המודל", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(verifier.busy)
                        .environment(\.layoutDirection, .leftToRight).accessibilityIdentifier("feedback-model")
                    CopyTextButton(text: model, field: "שם מודל המשוב", identifier: "feedback-model").labelStyle(.iconOnly)
                }
                Text("למשוב וידאו וקול נתמך כרגע Gemini 4 Argon. המודל נבחר בנפרד ממודל התסריטים. OpenAI ו־Claude נשארים זמינים לתסריטים; לא נחליף וידאו בתמונות בלי הודעה.").font(.footnote)
                NavigationLink("מפתח API של " + provider.title) { ProviderSettingsView(provider: provider, showsTextModel: false) }.disabled(verifier.busy)
            }
            Section("אימות וידאו וקול") {
                Text(verifier.status).font(.subheadline).accessibilityIdentifier("video-capability-status")
                Text("הבדיקה בודקת תיעוד נתמך, גישה למודל וקליפ סינתטי קצר עם צבעים וצלילים, ללא אדם. ייתכן חיוב API. הצלחה אינה מבטיחה איכות של כל המלצה.").font(.footnote)
                Text("האימות תקף לשבעה ימים ולמודל ולמפתח שנבדקו. החלפתם מחייבת בדיקה חדשה. אין שליחה בפתיחת המסך.").font(.caption)
                Button(verifier.busy ? "בודקים וידאו וקול…" : "בדיקת ניתוח וידאו") { confirming = true }
                    .disabled(verifier.busy).accessibilityIdentifier("verify-video")
                if verifier.busy { ProgressView(); Button("ביטול הבדיקה") { verifier.cancel() } }
            }
        }.scrollContentBackground(.hidden).background(LensTheme.background).navigationTitle("משוב צילום")
            .onAppear { verifier.refresh() }
            .onChange(of: selected) { _, _ in verifier.refresh() }
            .onChange(of: model) { _, _ in verifier.refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { verifier.cancel() } }
            .onDisappear { verifier.cancel() }
            .confirmationDialog("לשלוח קליפ סינתטי ל־\(provider.title)?", isPresented: $confirming, titleVisibility: .visible) {
                Button("אישור בדיקה · ייתכן חיוב API") { verifier.verify() }
                Button("ביטול", role: .cancel) {}
            } message: { Text("המודל: \(model). נשלח קליפ שנוצר במכשיר, ללא צילום שלך. זו בדיקה בתשלום אפשרי, לא ניתוח מקטע אישי.") }
            .lensError($verifier.error)
    }
}
