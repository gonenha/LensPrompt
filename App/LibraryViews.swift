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
    @State private var settings = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image("LensLogo").resizable().scaledToFit().frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("מול העדשה").font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("by").foregroundStyle(LensTheme.muted)
                                (Text("Gig").foregroundColor(Color(red: 195/255, green: 238/255, blue: 43/255)) + Text("lo").foregroundColor(LensTheme.text) + Text(".").foregroundColor(Color(red: 1, green: 79/255, blue: 53/255))).fontWeight(.heavy)
                            }.font(.caption).environment(\.layoutDirection, .leftToRight)
                                .accessibilityElement(children: .ignore).accessibilityLabel("מבית גיגלו")
                        }
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
                        ForEach(Array(library.scriptFamilies.enumerated()), id: \.element.id) { index, family in
                            let script = family.scripts[0]
                            VStack(spacing: 0) {
                            Button { path.append(script.id) } label: { ScriptCard(script: script, number: index + 1) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(script.isSample ? "sample-script" : "script-\(script.id)")
                                .contextMenu {
                                    Button("שכפול", systemImage: "doc.on.doc") { library.duplicate(script) }
                                    Button("מחיקה", systemImage: "trash", role: .destructive) { deleting = script }
                                }
                                ForEach(Array(family.scripts.dropFirst())) { variant in
                                    Button { path.append(variant.id) } label: {
                                        HStack {
                                            Image(systemName: "sparkles")
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(variant.scriptStyle?.title ?? variant.title)
                                                Text("\(library.takes(for: variant.id).count) טייקים").font(.caption).foregroundStyle(LensTheme.muted)
                                            }
                                            Spacer(); Image(systemName: "chevron.left")
                                        }.font(.subheadline).foregroundStyle(LensTheme.accent).padding(16)
                                    }.buttonStyle(.plain).accessibilityIdentifier("script-" + variant.id.uuidString)
                                        .contextMenu {
                                            Button("מחיקה", systemImage: "trash", role: .destructive) { deleting = variant }
                                        }
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
                        Button { settings = true } label: { Label("הגדרות", systemImage: "gearshape").font(.subheadline).frame(minHeight: 44) }.accessibilityIdentifier("settings")
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
            .sheet(isPresented: $settings) { AISettingsView() }
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
    @State private var styles = false
    @FocusState private var focusedField: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    init(library: LibraryModel, initial: Script) { self.library = library; _script = State(initialValue: initial) }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button { focusedField = nil; styles = true } label: { Label("יצירת גרסאות עם בינה", systemImage: "sparkles") }.accessibilityIdentifier("script-styles")
                    let familyID = script.sourceScriptID ?? script.id
                    let family = library.scripts.filter { ($0.sourceScriptID ?? $0.id) == familyID && $0.id != script.id }
                    if !family.isEmpty {
                        DisclosureGroup("המקור והגרסאות שלי") {
                            ForEach(family) { member in
                                NavigationLink { EditorView(library: library, initial: member) } label: {
                                    Text(member.scriptStyle?.title ?? "המקור").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                                }
                            }
                        }.font(.subheadline)
                    }
                    fieldHeader("כותרת", text: script.title, field: "כותרת התסריט", identifier: "title")
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
                                fieldHeader(stage.title, text: script.pointText(for: stage), field: stage.title, identifier: "point-" + stage.rawValue)
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
                        fieldHeader("התסריט", text: script.text, field: "טקסט התסריט", identifier: "text")
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
            .sheet(isPresented: $styles) { ScriptStylesView(library: library, source: script) }
            .onChange(of: script) { _, value in library.upsert(value) }
    }
    private func fieldHeader(_ title: String, text: String, field: String, identifier: String) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout())
        return layout {
            Text(title).font(.subheadline.weight(.semibold))
            if !typeSize.isAccessibilitySize { Spacer() }
            CopyTextButton(text: text, field: field, identifier: identifier)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
