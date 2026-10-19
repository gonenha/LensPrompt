import SwiftUI
import PrompterCore

struct AISettingsView: View {
    @AppStorage("ai.provider") private var selected = AIProvider.openAI.rawValue
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("יצירת גרסאות") {
                    Picker("הספק הפעיל", selection: $selected) {
                        ForEach(AIProvider.allCases) { Text($0.title).tag($0.rawValue) }
                    }.accessibilityIdentifier("ai-provider")
                    ForEach(AIProvider.allCases) { provider in
                        NavigationLink(provider.title) { ProviderSettingsView(provider: provider) }
                    }
                }
                Section("פרטיות ועלויות") {
                    Text("המפתחות נשמרים ב־Keychain באייפון הזה בלבד. אין שרת מתווך ואין מפתח משותף לאפליקציה.")
                    Text("בלחיצה על יצירה נשלחים הכותרת, הטקסט ונקודות הדיבור לספק הפעיל. לא נשלחים סרטונים. השימוש מחויב בחשבון ה־API שלך, בנפרד ממנוי הצ׳אט.")
                    Text("מחיקת מפתח כאן מסירה אותו מהמכשיר. כדי לבטל אותו לגמרי יש לבטל אותו גם באתר הספק.")
                }
                Section("האולפן") {
                    NavigationLink("משוב צילום · מודל ואימות וידאו") { FeedbackSettingsView() }.accessibilityIdentifier("feedback-settings")
                    Text("מהירות הגלילה, גודל הטקסט והספירה לאחור נשמרים בנפרד לכל תסריט במסך ״לפני הטייק״.")
                }
            }.scrollContentBackground(.hidden).background(LensTheme.background).navigationTitle("הגדרות")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("סיום") { dismiss() } } }
        }.tint(LensTheme.accent).preferredColorScheme(.dark)
    }
}

struct ProviderSettingsView: View {
    let provider: AIProvider
    var showsTextModel = true
    @State private var key = ""
    @State private var model = ""
    @State private var saved = false
    @State private var status: String?
    @State private var error: String?
    @State private var checking = false
    @State private var task: Task<Void, Never>?
    private let store = APIKeyStore()
    var body: some View {
        Form {
            Section("מפתח אישי") {
                Text(saved ? "מפתח שמור במכשיר" : "לא נשמר מפתח")
                SecureField(saved ? "מפתח חדש להחלפה" : "מפתח API", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("api-key")
                Button(saved ? "החלפת המפתח" : "שמירת המפתח") {
                    do { try store.save(key, provider: provider); key = ""; saved = true; status = "המפתח נשמר. החיבור עדיין לא נבדק." }
                    catch { self.error = error.localizedDescription }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking)
                if saved {
                    Button("מחיקת המפתח מהמכשיר", role: .destructive) {
                        do { try store.delete(provider); saved = false; status = nil; key = "" }
                        catch { self.error = error.localizedDescription }
                    }.disabled(checking)
                }
            }
            if showsTextModel {
                Section("מודל") {
                    TextField("שם המודל", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight).disabled(checking)
                    Text("אפשר לשנות לשם מודל אחר שהחשבון שלך מורשה להשתמש בו ושמתאים ליצירת טקסט מובנה.").font(.caption)
                    Button(checking ? "בודקים…" : "בדיקת חיבור וגישה למודל") { check() }
                        .disabled(!saved || checking || !key.isEmpty)
                    if checking { ProgressView() }
                    if let status { Text(status).font(.footnote).accessibilityIdentifier("connection-status") }
                    Text("הבדיקה אינה מייצרת תסריט. הגישה ליצירה ולחיוב תאומת בבקשת היצירה עצמה.").font(.caption)
                }
            } else {
                Section("משוב צילום") {
                    Text("זהו המפתח של הספק. מודל המשוב נבחר ונבדק במסך הקודם, בנפרד ממודל יצירת התסריטים.").font(.footnote)
                    if let status { Text(status).font(.footnote) }
                }
            }
        }.scrollContentBackground(.hidden).background(LensTheme.background).navigationTitle(provider.title)
            .onAppear {
                model = UserDefaults.standard.string(forKey: "ai.model." + provider.rawValue) ?? provider.defaultModel
                do { saved = try store.read(provider) != nil } catch { self.error = error.localizedDescription }
            }
            .onChange(of: model) { _, value in UserDefaults.standard.set(value.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "ai.model." + provider.rawValue); status = nil }
            .onChange(of: key) { _, _ in status = nil }
            .onDisappear { task?.cancel(); key = "" }
            .lensError($error)
    }
    private func check() {
        checking = true; status = nil
        task = Task {
            defer { checking = false }
            do {
                guard let key = try store.read(provider) else { throw AIError.missingKey }
                let request = try AIContract.request(provider: provider, model: model.trimmingCharacters(in: .whitespacesAndNewlines), key: key, source: nil)
                _ = try await AIClient().send(request)
                try Task.checkCancellation()
                status = "המפתח והגישה למודל נבדקו בהצלחה כעת."
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}

struct ScriptStylesView: View {
    let library: LibraryModel
    let source: Script
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("ai.provider") private var selected = AIProvider.openAI.rawValue
    @State private var variants: [Script] = []
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @State private var settings = false
    @State private var generationProvider: String?
    private var provider: AIProvider { AIProvider(rawValue: selected) ?? .openAI }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(source.title).font(.title2.bold())
                    if variants.isEmpty {
                        Text("אותו מסר, בשלושה סגנונות").font(.headline)
                        ForEach(ScriptStyle.allCases, id: \.self) { style in
                            Label(style.title, systemImage: "sparkles").padding(16).frame(maxWidth: .infinity, alignment: .leading).background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        }
                        Text("הטקסט ונקודות הדיבור יישלחו ל־\(provider.title). ייתכן חיוב בחשבון ה־API שלך. המקור יישמר ללא שינוי.")
                            .font(.footnote).foregroundStyle(LensTheme.muted)
                        Button("הגדרות חיבור · " + provider.title) { settings = true }
                        Button("יצירת שלוש גרסאות") { generate() }.buttonStyle(MainButtonStyle())
                            .disabled(!AIContract.canGenerate(source)).accessibilityIdentifier("generate-styles")
                        if !AIContract.canGenerate(source) { Text("יש להזין טקסט או נקודות לדיבור, עד 20,000 תווים כולל הכותרת והנקודות.").font(.footnote) }
                    } else {
                        Text("נוצר באמצעות \(generationProvider ?? provider.title)").font(.caption).foregroundStyle(LensTheme.muted)
                        Text("בדוק את העובדות וההצעה לפני השמירה. כל גרסה תיפתח לעריכה ולצילום בנפרד.").font(.footnote)
                        ForEach(variants) { variant in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(variant.scriptStyle?.title ?? "גרסה").font(.title3.bold()).foregroundStyle(LensTheme.accent)
                                CopyTextButton(text: variant.text, field: "טקסט הגרסה", identifier: variant.id.uuidString)
                                Text(variant.text).textSelection(.enabled)
                                ForEach(variant.activeTalkingPoints) { point in
                                    Text(point.stage.title + ": " + point.text).font(.subheadline).foregroundStyle(LensTheme.muted)
                                }
                            }.padding(18).background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                        }
                        Button("שמירת הגרסאות בספרייה") { if library.saveVariants(variants) { dismiss() } else { error = library.error } }
                            .buttonStyle(MainButtonStyle()).accessibilityIdentifier("save-styles")
                    }
                }.padding(24)
            }.background(LensTheme.background).foregroundStyle(LensTheme.text).navigationTitle("גרסאות לתסריט").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגירה") { task?.cancel(); dismiss() }.disabled(busy) } }
                .overlay { if busy { BrandLoadingView(title: "יוצרים שלוש דרכים לספר את זה…", cancel: cancel) } }
                .sheet(isPresented: $settings) { AISettingsView() }
                .onDisappear { task?.cancel() }
                .onChange(of: scenePhase) { _, phase in if phase == .background { cancel() } }
                .lensError($error)
        }.tint(LensTheme.accent).preferredColorScheme(.dark)
    }
    private func cancel() { task?.cancel(); busy = false }
    private func generate() {
        guard !busy else { return }
        let provider = provider
        busy = true
        task = Task {
            defer { if !Task.isCancelled { busy = false } }
            do {
                guard let key = try APIKeyStore().read(provider) else { throw AIError.missingKey }
                let model = UserDefaults.standard.string(forKey: "ai.model." + provider.rawValue) ?? provider.defaultModel
                let request = try AIContract.request(provider: provider, model: model, key: key, source: source)
                let data = try await AIClient().send(request)
                try Task.checkCancellation()
                let output = try AIContract.output(provider: provider, data: data)
                let result = try ScriptVariants.decode(output, source: source)
                try Task.checkCancellation()
                variants = result; generationProvider = provider.title
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
