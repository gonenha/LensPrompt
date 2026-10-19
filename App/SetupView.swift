import SwiftUI
import PrompterCore

struct SetupView: View {
    let library: LibraryModel
    @Binding var script: Script
    @State private var camera = CameraModel()
    @State private var presenting = false
    @State private var practice = true
    @State private var voicePermissionDenied = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack {
                    CameraPreview(session: camera.session)
                    if !camera.previewAvailable {
                        LensTheme.pale
                        Image(systemName: "person.crop.rectangle").font(.system(size: 50, weight: .ultraLight)).foregroundStyle(LensTheme.green.opacity(0.35))
                    }
                    Text(String((script.presentationMode == .talkingPoints ? script.activeTalkingPoints.first?.text ?? "" : script.text).prefix(90))).font(.system(size: min(22, script.settings.fontSize * 0.6), weight: .semibold))
                        .lineLimit(2).padding(12).frame(maxWidth: .infinity).background(LensTheme.paper.opacity(0.85), in: RoundedRectangle(cornerRadius: 10)).padding(18)
                }.frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 19))
                if let notice = camera.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                settingLabel("איך מצלמים?")
                HStack {
                    modeButton("ביד", mode: .hand, id: "hand-mode")
                    modeButton("ממרחק מטר", mode: .distance, id: "distance-mode")
                }
                if script.presentationMode == .talkingPoints {
                    Text("נקודות לדיבור · מעבר ידני בכפתור ״הבא״. אפשר לדבר בקצב שלך; ההקלטה נמשכת גם בנקודה האחרונה.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                Toggle("מעקב משוער לפי קול", isOn: $script.settings.followsVoice)
                    .accessibilityIdentifier("voice-follow")
                if script.settings.followsVoice {
                    Text("המילה המשוערת תודגש לפי הקצב שהגדרת. בשתיקה המלל ייעצר; נגיעה במילה תתקן את המיקום. זהו מעקב לפי עוצמת קול, וגם רעש עלול לקדם אותו.")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("רגישות לקול") {
                        Text("אם המלל מתקדם בשקט, הורד רגישות. אם הוא נעצר בזמן דיבור, העלה רגישות.").font(.caption)
                        Slider(value: Binding(get: { -script.settings.soundThreshold }, set: { script.settings.soundThreshold = -$0 }), in: 20...55, step: 1)
                            .accessibilityLabel("רגישות לקול")
                    }.font(.subheadline)
                }
                Picker("קצב הגלילה", selection: $script.settings.pace) {
                    Text("מילים בדקה").tag(Pace.words)
                    Text("משך יעד").tag(Pace.duration)
                }.pickerStyle(.segmented)
                if script.settings.pace == .words {
                    settingLabel("מהירות", value: "\(Int(script.settings.wordsPerMinute)) מילים בדקה")
                    Slider(value: $script.settings.wordsPerMinute, in: 50...220, step: 5).accessibilityLabel("מהירות הגלילה")
                } else {
                    HStack {
                        Text("משך יעד בשניות").font(.subheadline)
                        Spacer()
                        TextField("שניות", value: $script.settings.targetSeconds, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 85).textFieldStyle(.roundedBorder)
                    }
                }
                }
                settingLabel("גודל הטקסט", value: "\(Int(script.settings.fontSize))")
                Slider(value: $script.settings.fontSize, in: 20...40, step: 1).accessibilityLabel("גודל הטקסט")
                DisclosureGroup("רוחב ורקע המלל") {
                    VStack(spacing: 12) {
                        settingLabel("רוחב אזור הקריאה")
                        Slider(value: $script.settings.widthFraction, in: 0.65...0.98).accessibilityLabel("רוחב המלל")
                        settingLabel("כהות הרקע")
                        Slider(value: $script.settings.backgroundOpacity, in: 0.2...0.95).accessibilityLabel("כהות רקע המלל")
                    }.padding(.top, 10)
                }.font(.subheadline)
                HStack {
                    Text("ספירה לאחור").font(.subheadline.weight(.semibold))
                    Spacer()
                    Picker("ספירה לאחור", selection: $script.settings.countdown) {
                        Text("ללא").tag(0)
                        ForEach([3, 5, 7], id: \.self) { Text("\($0) שניות").tag($0) }
                    }.labelsHidden().accessibilityIdentifier("countdown-picker")
                }
                if script.presentationMode == .talkingPoints {
                    Text("\(script.activeTalkingPoints.count) נקודות · ללא מעבר אוטומטי").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(script.wordCount) מילים · משך גלילה משוער \(LensTheme.time(script.settings.duration(wordCount: script.wordCount)))\nהצילום ממשיך גם אחרי סוף המלל.")
                        .font(.caption).lineSpacing(5).foregroundStyle(.secondary)
                }
                Button {
                    script.settings = script.settings.validated()
                    Task { if await camera.prepareRecording() { practice = false; presenting = true } }
                } label: { Label("התחלת צילום", systemImage: "record.circle") }.buttonStyle(MainButtonStyle())
                    .disabled(camera.preparing || !script.canStart).accessibilityIdentifier("record")
                Button {
                    script.settings = script.settings.validated()
                    Task {
                        if script.presentationMode == .scrolling && script.settings.followsVoice {
                            guard await camera.allowVoicePractice() else { voicePermissionDenied = true; return }
                        }
                        practice = true; presenting = true
                    }
                } label: { Label("תרגול ללא צילום", systemImage: "play") }
                    .buttonStyle(MainButtonStyle(secondary: true)).disabled(!script.canStart).accessibilityIdentifier("rehearse")
                if camera.permissionDenied {
                    Button("פתיחת הגדרות הרשאות") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.font(.footnote)
                }
            }.padding(24)
        }.background(LensTheme.paper).navigationTitle("לפני הטייק").navigationBarTitleDisplayMode(.inline)
            .task { await camera.preparePreviewIfAuthorized() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && !presenting { Task { await camera.preparePreviewIfAuthorized() } }
                else if phase == .background && !presenting { Task { await camera.suspendPreview() } }
            }
            .onDisappear { if !presenting { Task { await camera.suspendPreview() } } }
            .fullScreenCover(isPresented: $presenting, onDismiss: { Task { await camera.preparePreviewIfAuthorized() } }) {
                RecordingView(library: library, script: $script, camera: camera, practice: practice)
                    .environment(\.layoutDirection, .rightToLeft).environment(\.locale, Locale(identifier: "he_IL"))
            }
            .alert("נדרשת גישה למיקרופון למעקב לפי קול", isPresented: $voicePermissionDenied) {
                Button("תרגול בגלילה רגילה") { script.settings.followsVoice = false; practice = true; presenting = true }
                Button("ביטול", role: .cancel) {}
            } message: { Text("אפשר לאפשר גישה בהגדרות האייפון, או לתרגל בלי מעקב לפי קול.") }
            .lensError($camera.error)
    }

    private func settingLabel(_ title: String, value: String? = nil) -> some View {
        HStack { Text(title).font(.subheadline.weight(.semibold)); Spacer(); if let value { Text(value).font(.caption).foregroundStyle(.secondary) } }
    }
    private func modeButton(_ title: String, mode: FilmingMode, id: String) -> some View {
        Button { script.settings.apply(mode) } label: {
            Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(12)
                .background(script.settings.mode == mode ? Color.white : LensTheme.pale, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LensTheme.green.opacity(script.settings.mode == mode ? 0.3 : 0.05)))
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
