import SwiftUI
import UniformTypeIdentifiers
import PrompterCore

struct LibraryView: View {
    @Bindable var library: LibraryModel
    @State private var path: [UUID] = []
    @State private var importing = false
    @State private var showingTakes = false
    @State private var deleting: Script?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) { Circle().fill(LensTheme.green).frame(width: 9, height: 9); Text("מול העדשה").font(.subheadline.weight(.semibold)) }
                        .foregroundStyle(LensTheme.green).padding(.top, 14)
                    Text("התסריטים שלי").font(.largeTitle.bold())
                    Text("מילים מוכנות. עכשיו תורך.").font(.subheadline).foregroundStyle(.secondary).padding(.bottom, 12)
                    if let notice = library.bridgeNotice {
                        Label(notice, systemImage: "arrow.down.doc").font(.footnote).foregroundStyle(LensTheme.green)
                            .accessibilityIdentifier("codex-inbox-notice")
                    }
                    if !library.scriptsLoaded {
                        ContentUnavailableView("התסריטים לא נטענו", systemImage: "exclamationmark.triangle", description: Text("לא שינינו את הקבצים שלך."))
                        Button("ניסיון נוסף") { library.reload() }.buttonStyle(MainButtonStyle())
                    } else {
                        ForEach(library.scripts) { script in
                            Button { path.append(script.id) } label: { ScriptCard(script: script) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(script.isSample ? "sample-script" : "script-\(script.id)")
                                .contextMenu {
                                    Button("שכפול", systemImage: "doc.on.doc") { library.duplicate(script) }
                                    Button("מחיקה", systemImage: "trash", role: .destructive) { deleting = script }
                                }
                        }
                        if library.scripts.isEmpty { Text("כאן יופיעו התסריטים שלך.").foregroundStyle(.secondary).padding(.vertical, 25) }
                        Button { let script = Script(title: "תסריט חדש"); library.upsert(script); path.append(script.id) } label: {
                            Label("תסריט חדש", systemImage: "plus")
                        }.buttonStyle(MainButtonStyle()).accessibilityIdentifier("new-script")
                        Button { importing = true } label: { Label("ייבוא קובץ טקסט", systemImage: "square.and.arrow.down") }
                            .font(.subheadline).frame(maxWidth: .infinity).padding(10)
                    }
                    Text("כותבים במקבוק, מדביקים כאן.\nהמלל נשמר במכשיר שלך.").font(.footnote).foregroundStyle(.secondary).lineSpacing(5).padding(.top, 10)
                }.padding(24)
            }
            .background(LensTheme.paper).foregroundStyle(LensTheme.ink)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { showingTakes = true } label: { Label("הטייקים שלי", systemImage: "film.stack") }.accessibilityIdentifier("takes") }
            }
            .navigationDestination(for: UUID.self) { id in
                if let script = library.scripts.first(where: { $0.id == id }) { EditorView(library: library, initial: script) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first, let script = library.importFile(url) { path.append(script.id) }
                case .failure(let error): library.error = error.localizedDescription
                }
            }
            .sheet(isPresented: $showingTakes) { TakesView(library: library) }
            .confirmationDialog("למחוק את התסריט?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("מחיקת תסריט", role: .destructive) { if let deleting { library.deleteScript(deleting) }; deleting = nil }
                Button("ביטול", role: .cancel) { deleting = nil }
            }
        }.tint(LensTheme.green).lensError($library.error)
    }
}

private struct ScriptCard: View {
    let script: Script
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if script.isSample { Text("תסריט לדוגמה").font(.caption2.weight(.medium)).padding(.horizontal, 9).padding(.vertical, 5).background(LensTheme.pale, in: Capsule()) }
            Text(script.title.isEmpty ? "ללא כותרת" : script.title).font(.title3.bold())
            Text(script.presentationText.isEmpty ? "עדיין אין כאן מלל" : script.presentationText).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).lineSpacing(4)
            HStack {
                if script.presentationMode == .talkingPoints {
                    Text("\(script.activeTalkingPoints.count) נקודות לדיבור · מעבר ידני")
                } else {
                    Text("\(script.wordCount) מילים · כ־\(LensTheme.time(script.settings.duration(wordCount: script.wordCount)))")
                }
                Spacer(); Image(systemName: "arrow.left")
            }.font(.caption).foregroundStyle(LensTheme.green)
            Text(script.updatedAt, format: .dateTime.day().month().hour().minute()).font(.caption2).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(LensTheme.green.opacity(0.1)))
    }
}

struct EditorView: View {
    @Bindable var library: LibraryModel
    @State private var script: Script
    init(library: LibraryModel, initial: Script) { self.library = library; _script = State(initialValue: initial) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("שם התסריט", text: $script.title).font(.title2.bold()).accessibilityIdentifier("script-title")
            Picker("אופן הצגת המלל", selection: $script.presentationMode) {
                Text("טקסט לגלילה").tag(PresentationMode.scrolling)
                Text("נקודות לדיבור").tag(PresentationMode.talkingPoints)
            }.pickerStyle(.segmented).accessibilityIdentifier("presentation-mode")
            if script.presentationMode == .talkingPoints {
                Text("משפט שמזכיר לך מה להגיד בכל שלב. בצילום עוברים ביניהם בכפתור ״הבא״. אפשר להשאיר שלבים ריקים.")
                    .font(.footnote).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(TalkingStage.allCases, id: \.self) { stage in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(stage.title).font(.subheadline.weight(.semibold))
                                TextField("המשפט שיזכיר לך", text: Binding(get: { script.pointText(for: stage) }, set: { script.setPointText($0, for: stage) }), axis: .vertical)
                                    .font(.system(size: 19)).lineLimit(2...5).padding(12)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityLabel(stage.title).accessibilityIdentifier("point-\(stage.rawValue)")
                            }
                        }
                    }
                }.scrollDismissesKeyboard(.interactively)
                Text("\(script.activeTalkingPoints.count) נקודות · שמירה אוטומטית במכשיר").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("הדבק מלל שהעתקת במקבוק, או כתוב כאן.").font(.footnote).foregroundStyle(.secondary)
                TextEditor(text: $script.text).font(.system(size: 19)).lineSpacing(8).scrollContentBackground(.hidden)
                    .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("script-text")
                Text("\(script.wordCount) מילים · שמירה אוטומטית במכשיר").font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink { SetupView(library: library, script: $script) } label: { Text("ממשיכים להכנה ←") }
                .buttonStyle(MainButtonStyle()).disabled(!script.canStart).opacity(script.canStart ? 1 : 0.5).accessibilityIdentifier("prepare")
        }.padding(24).background(LensTheme.paper).navigationTitle("המלל שלך").navigationBarTitleDisplayMode(.inline)
            .onChange(of: script) { _, value in library.upsert(value) }
    }
}
