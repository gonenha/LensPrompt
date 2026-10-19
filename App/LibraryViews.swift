import SwiftUI
import UniformTypeIdentifiers
import PrompterCore

struct LibraryView: View {
    @Bindable var library: LibraryModel
    @State private var path: [UUID] = []
    @State private var importing = false
    @State private var showingTakes = false
    @State private var takeScriptFilter: UUID?
    @State private var deleting: Script?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: "viewfinder").font(.system(size: 32, weight: .medium)).foregroundStyle(LensTheme.accent)
                        Text("מול העדשה").font(.largeTitle.bold())
                    }.padding(.top, 14).padding(.bottom, 12)
                    Text("מוכנים לטייק הבא?").font(.title2.bold()).padding(.bottom, 8)
                    if let notice = library.bridgeNotice {
                        Label(notice, systemImage: "arrow.down.doc").font(.footnote).foregroundStyle(LensTheme.accent)
                            .accessibilityIdentifier("codex-inbox-notice")
                    }
                    if !library.scriptsLoaded {
                        ContentUnavailableView("התסריטים לא נטענו", systemImage: "exclamationmark.triangle", description: Text("לא שינינו את הקבצים שלך."))
                        Button("ניסיון נוסף") { library.reload() }.buttonStyle(MainButtonStyle())
                    } else {
                        ForEach(Array(library.scripts.enumerated()), id: \.element.id) { index, script in
                            VStack(spacing: 0) {
                            Button { path.append(script.id) } label: { ScriptCard(script: script, number: index + 1) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(script.isSample ? "sample-script" : "script-\(script.id)")
                                .contextMenu {
                                    Button("שכפול", systemImage: "doc.on.doc") { library.duplicate(script) }
                                    Button("מחיקה", systemImage: "trash", role: .destructive) { deleting = script }
                                }
                                let count = library.takes(for: script.id).count
                                if count > 0 {
                                    Button { takeScriptFilter = script.id; showingTakes = true } label: {
                                        HStack { Image(systemName: "film.stack"); Text("\(count) טייקים לתסריט"); Spacer(); Image(systemName: "chevron.left") }
                                            .font(.subheadline).foregroundStyle(LensTheme.accent).padding(16)
                                    }.buttonStyle(.plain).accessibilityIdentifier("script-takes-" + script.id.uuidString)
                                }
                            }.background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 20))

                        }
                        if library.scripts.isEmpty { Text("כאן יופיעו התסריטים שלך.").foregroundStyle(.secondary).padding(.vertical, 25) }

                    }
                    Text("התסריטים והטייקים נשמרים במכשיר שלך.").font(.footnote).foregroundStyle(.secondary).lineSpacing(5).padding(.top, 10)
                }.padding(24)
            }
            .background(LensTheme.background).foregroundStyle(LensTheme.text)
            .toolbar(path.isEmpty ? .hidden : .visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if path.isEmpty {
                    VStack(spacing: 8) {
                        if library.scriptsLoaded {
                            Button { let script = Script(title: "תסריט חדש"); library.upsert(script); path.append(script.id) } label: {
                                Label("תסריט חדש", systemImage: "plus")
                            }.buttonStyle(MainButtonStyle()).accessibilityIdentifier("new-script").padding(.horizontal, 24)
                            Button { importing = true } label: {
                                Label("ייבוא קובץ טקסט", systemImage: "square.and.arrow.down")
                                    .font(.subheadline).frame(maxWidth: .infinity, minHeight: 48)
                            }
                        }
                        HStack(spacing: 24) {
                            Button {} label: {
                                VStack(spacing: 5) { Image(systemName: "doc.text.fill").font(.title3); Text("תסריטים").font(.caption) }
                                    .frame(maxWidth: .infinity, minHeight: 52)
                            }.foregroundStyle(LensTheme.accent).accessibilityIdentifier("library-tab").accessibilityAddTraits(.isSelected)
                            Button { takeScriptFilter = nil; showingTakes = true } label: {
                                VStack(spacing: 5) { Image(systemName: "play.rectangle").font(.title3); Text("הטייקים שלי").font(.caption) }
                                    .frame(maxWidth: .infinity, minHeight: 52)
                            }.foregroundStyle(LensTheme.muted).accessibilityIdentifier("takes")
                        }.padding(.horizontal, 20)
                    }.padding(.top, 12).background(LensTheme.background)
                        .overlay(alignment: .top) { Divider().overlay(LensTheme.divider) }
                }
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
            .sheet(isPresented: $showingTakes) { TakesView(library: library, scriptFilter: takeScriptFilter) }
            .confirmationDialog("למחוק את התסריט?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("מחיקת תסריט", role: .destructive) { if let deleting { library.deleteScript(deleting) }; deleting = nil }
                Button("ביטול", role: .cancel) { deleting = nil }
            }
        }.tint(LensTheme.accent).lensError($library.error)
    }
}

private struct ScriptCard: View {
    let script: Script
    let number: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(String(format: "%02d", number)).font(.subheadline.monospacedDigit()).foregroundStyle(LensTheme.muted)
            Text(script.title.isEmpty ? "ללא כותרת" : script.title).font(.title2.bold()).multilineTextAlignment(.leading)
            Text(script.presentationText.isEmpty ? "עדיין אין כאן מלל" : script.presentationText).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).lineSpacing(4)
            HStack {
                if script.presentationMode == .talkingPoints {
                    Text("\(script.activeTalkingPoints.count) נקודות לדיבור · מעבר ידני")
                } else {
                    Text("\(script.wordCount) מילים · כ־\(LensTheme.time(script.settings.duration(wordCount: script.wordCount)))")
                }
                Spacer(); Image(systemName: "arrow.left").font(.headline).accessibilityHidden(true)
            }.font(.caption).foregroundStyle(LensTheme.accent)
            Text(script.updatedAt, format: .dateTime.day().month().hour().minute()).font(.caption2).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LensTheme.divider.opacity(0.65)))
    }
}

struct EditorView: View {
    @Bindable var library: LibraryModel
    @State private var script: Script
    @FocusState private var focusedField: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    init(library: LibraryModel, initial: Script) { self.library = library; _script = State(initialValue: initial) }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("שם התסריט", text: $script.title).focused($focusedField, equals: "title").font(.title2.bold()).padding(14)
                        .background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("script-title")
                    let choiceLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
                    choiceLayout {
                        StudioChoice(title: "טקסט לגלילה", selected: script.presentationMode == .scrolling) { script.presentationMode = .scrolling }
                        StudioChoice(title: "נקודות לדיבור", selected: script.presentationMode == .talkingPoints) { script.presentationMode = .talkingPoints }
                    }.padding(4).background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("presentation-mode")
                    if script.presentationMode == .talkingPoints {
                        Text("משפט שמזכיר לך מה להגיד בכל שלב. בצילום עוברים ביניהם בכפתור ״הבא״. אפשר להשאיר שלבים ריקים.")
                            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ForEach(TalkingStage.allCases, id: \.self) { stage in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(stage.title).font(.subheadline.weight(.semibold))
                                TextField("המשפט שיזכיר לך", text: Binding(get: { script.pointText(for: stage) }, set: { script.setPointText($0, for: stage) }), axis: .vertical)
                                    .focused($focusedField, equals: stage.rawValue)
                                    .font(.body).lineLimit(2...5).padding(12)
                                    .background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityLabel(stage.title).accessibilityIdentifier("point-\(stage.rawValue)")
                            }
                        }
                        Text("\(script.activeTalkingPoints.count) נקודות · שמירה אוטומטית במכשיר").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("הדבק מלל שהעתקת במקבוק, או כתוב כאן.").font(.footnote).foregroundStyle(.secondary)
                        TextEditor(text: $script.text).focused($focusedField, equals: "text").font(.body).lineSpacing(8).scrollContentBackground(.hidden)
                            .frame(minHeight: max(220, geometry.size.height * 0.5))
                            .padding(12).background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("script-text")
                        Text("\(script.wordCount) מילים · שמירה אוטומטית במכשיר").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(24)
            }.scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    if focusedField == nil {
                        NavigationLink { SetupView(library: library, script: $script) } label: { Text("ממשיכים להכנה") }
                            .buttonStyle(MainButtonStyle()).disabled(!script.canStart).accessibilityIdentifier("prepare")
                            .padding(.horizontal, 24).padding(.vertical, 12).background(LensTheme.background)
                    }
                }
        }.background(LensTheme.background).foregroundStyle(LensTheme.text).navigationTitle("המלל שלך").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("סיום הקלדה") { focusedField = nil }.accessibilityIdentifier("dismiss-keyboard")
                }
            }
            .onChange(of: script) { _, value in library.upsert(value) }
    }
}
