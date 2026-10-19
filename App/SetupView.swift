import SwiftUI
import PrompterCore

struct SetupView: View {
    let library: LibraryModel
    @Binding var script: Script
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var camera = CameraModel()
    @State private var presenting = false
    @State private var preparation = CapturePreparation()
    @State private var practice = true
    @State private var voicePermissionDenied = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack {
                    CameraPreview(session: camera.session)
                    if !camera.previewAvailable {
                        LensTheme.surface
                        Image(systemName: "person.crop.rectangle").font(.system(size: 50, weight: .ultraLight)).foregroundStyle(LensTheme.accent.opacity(0.35))
                    }
                    Text(String((script.presentationMode == .talkingPoints ? script.activeTalkingPoints.first?.text ?? "" : script.text).prefix(90))).font(.system(size: min(22, script.settings.fontSize * 0.6), weight: .semibold))
                        .lineLimit(2).padding(12).frame(maxWidth: .infinity).background(LensTheme.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 10)).padding(18)
                }.frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 19))
                if let notice = camera.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                DisclosureGroup("צילום ללא הפרעות") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("האפליקציה מבקשת לצמצם הפרעות לקול. להשתקת באנרים, הודעות ושיחות צריך להגדיר באייפון מצב ריכוז פעם אחת.")
                        Text("1. הגדרות ← ריכוז ← + ← מותאם אישית. שם המצב: צילום.")
                        Text("2. אנשים: אפשר התראות מאנשים מורשים בלבד, בלי להוסיף אנשים. כבה שיחות חוזרות.")
                        Text("3. יישומים: אפשר התראות מיישומים מורשים בלבד, בלי להוסיף יישומים. כבה התראות רגישות לזמן וסינון חכם שמאפשר פריצות.")
                        Text("4. הוסף תזמון לפי יישום ובחר ״מול העדשה״. ודא שההשתקה חלה גם כשהמכשיר פתוח.")
                        Text("5. בהגדרות הטלפון בחר הצגת שיחות נכנסות כבאנר. מענה לשיחה עדיין יקטע את הצילום; התראות חירום מורשות עשויות לעבור.")
                        Text("מצב הריכוז מופעל דרך הגדרות iOS. האפליקציה אינה יכולה להפעיל אותו בעצמה.")
                    }.font(.footnote).foregroundStyle(LensTheme.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                }.font(.subheadline).accessibilityIdentifier("focus-guide")
                settingLabel("איך מצלמים?")
                let choiceLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
                choiceLayout {
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
                choiceLayout {
                    StudioChoice(title: "מילים בדקה", selected: script.settings.pace == .words) { script.settings.pace = .words }
                    StudioChoice(title: "משך יעד", selected: script.settings.pace == .duration) { script.settings.pace = .duration }
                }.padding(4).background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 16))
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
                    CopyTextButton(text: script.settings.targetSeconds.formatted(.number.precision(.fractionLength(0))), field: "משך היעד בשניות", identifier: "duration")
                        .frame(maxWidth: .infinity, alignment: .trailing)
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
                    preparation.begin(operation: { await camera.prepareRecording() }, ready: { practice = false; presenting = true })
                } label: { Label("התחלת צילום", systemImage: "record.circle") }.buttonStyle(MainButtonStyle())
                    .disabled(preparation.busy || camera.preparing || !script.canStart).accessibilityIdentifier("record")
                Button {
                    script.settings = script.settings.validated()
                    startPractice()
                } label: { Label("תרגול ללא צילום", systemImage: "play") }
                    .buttonStyle(MainButtonStyle(secondary: true)).disabled(preparation.busy || !script.canStart).accessibilityIdentifier("rehearse")
                if camera.permissionDenied {
                    Button("פתיחת הגדרות הרשאות") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.font(.footnote)
                }
            }.padding(24)
        }.background(LensTheme.background).foregroundStyle(LensTheme.text).tint(LensTheme.accent).navigationTitle("לפני הטייק").navigationBarTitleDisplayMode(.inline)
            .overlay { if preparation.busy { BrandLoadingView(title: "מכינים את האולפן…", cancel: { preparation.cancel() }) } }
            .task { await camera.preparePreviewIfAuthorized() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && !presenting && !preparation.busy { Task { await camera.preparePreviewIfAuthorized() } }
                else if phase == .background && !presenting { preparation.cancel(); Task { await camera.suspendPreview() } }
            }
            .onDisappear { if !presenting { preparation.cancel(); Task { await camera.suspendPreview() } } }
            .fullScreenCover(isPresented: $presenting, onDismiss: { Task { await camera.preparePreviewIfAuthorized() } }) {
                RecordingView(library: library, script: $script, camera: camera, practice: practice)
                    .onAppear { preparation.didPresent() }
                    .environment(\.layoutDirection, .rightToLeft).environment(\.locale, Locale(identifier: "he_IL"))
            }
            .alert("נדרשת גישה למיקרופון למעקב לפי קול", isPresented: $voicePermissionDenied) {
                Button("תרגול בגלילה רגילה") { script.settings.followsVoice = false; startPractice() }
                Button("ביטול", role: .cancel) {}
            } message: { Text("אפשר לאפשר גישה בהגדרות האייפון, או לתרגל בלי מעקב לפי קול.") }
            .lensError($camera.error)
    }

    private func startPractice() {
        preparation.begin(operation: {
            if script.presentationMode == .scrolling && script.settings.followsVoice {
                let allowed = await camera.allowVoicePractice()
                guard !Task.isCancelled else { return false }
                guard allowed else { voicePermissionDenied = true; return false }
            }
            return true
        }, ready: { practice = true; presenting = true })
    }
    private func settingLabel(_ title: String, value: String? = nil) -> some View {
        HStack { Text(title).font(.subheadline.weight(.semibold)); Spacer(); if let value { Text(value).font(.caption).foregroundStyle(.secondary) } }
    }
    private func modeButton(_ title: String, mode: FilmingMode, id: String) -> some View {
        StudioChoice(title: title, selected: script.settings.mode == mode) { script.settings.apply(mode) }
            .accessibilityIdentifier(id)
    }
}
