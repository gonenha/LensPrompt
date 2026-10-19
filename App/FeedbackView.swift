import SwiftUI
import AVKit
import PrompterCore

struct FeedbackView: View {
    @State private var model: FeedbackModel
    @State private var player: AVPlayer?
    @State private var settings = false
    @State private var layoutCache = PromptLayoutCache()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(script: Script) { _model = State(initialValue: FeedbackModel(script: script)) }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let width = geometry.size.width * model.script.settings.widthFraction
                let layout = layoutCache.layout(text: model.script.presentationMode == .talkingPoints ? "" : model.script.text, width: width - 32, fontSize: model.script.settings.fontSize)
                Group {
                    if model.phase == .recording { capture(layout: layout, width: width) }
                    else { ScrollView { content(travel: layout.lastLineY).padding(24) } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if model.busy {
                            BrandLoadingView(title: loadingTitle, cancel: model.phase == .analyzing ? model.cancelAnalysis : model.delete)
                        }
                    }
            }.background(LensTheme.background).foregroundStyle(LensTheme.text)
                .navigationTitle("תרגול עם משוב").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("סגירה") { player?.pause(); Task { await model.close(); dismiss() } }
                            .disabled(model.busy || model.writing).accessibilityIdentifier("close-feedback")
                    }
                }
                .sheet(isPresented: $settings) {
                    NavigationStack { FeedbackSettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("סיום") { settings = false } } } }
                        .tint(LensTheme.accent).preferredColorScheme(.dark)
                }
                .confirmationDialog("אישור שליחת מקטע", isPresented: $model.showingApproval, titleVisibility: .visible) {
                    Button("אישור ושליחה לניתוח") { player?.pause(); model.analyze() }.accessibilityIdentifier("approve-feedback-upload")
                    Button("ביטול", role: .cancel) { model.approvalIdentity = nil }
                } message: {
                    let config = FeedbackConfiguration.current()
                    Text("\(config.provider.title) · \(config.model)\nיישלחו הווידאו והקול של המקטע (\(Int(model.clip?.duration ?? 0)) שניות), יעד הפרסום ותקציר המדידות. ייתכן חיוב API. ביטול לאחר שליחה אינו מבטל חיוב שכבר החל.")
                }
                .task(id: model.clip?.url) {
                    player?.pause()
                    player = model.clip.map { AVPlayer(url: $0.url) }
                }
                .onChange(of: model.phase) { _, phase in if phase != .review && phase != .result { player?.pause() } }
                .onChange(of: scenePhase) { _, phase in if phase == .background { player?.pause(); model.background() } }
                .onDisappear { player?.pause(); model.leave() }
                .lensError($model.error)
        }.tint(LensTheme.accent).preferredColorScheme(.dark).interactiveDismissDisabled()
    }
    private var loadingTitle: String {
        switch model.phase {
        case .preparing: "מכינים מקטע בדיקה…"
        case .finishing: "סוגרים את המקטע…"
        case .processing: "בודקים במכשיר…"
        case .analyzing: "מנתחים וידאו וקול…"
        default: "רגע אחד…"
        }
    }
    @ViewBuilder private func content(travel: Double) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.phase == .intro {
                Text("תרגול קצר. שיפור ממוקד.").font(.title2.bold())
                Text("נצלם מקטע זמני עם קול למשך 6–8 שניות, ונבדוק אותו קודם באייפון. הוא אינו טייק בספרייה ולא יישלח אוטומטית.").fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("feedback-consent")
                targetPicker
                Text("הצילום כרגע לאורך בלבד. ההמלצה יכולה להתייחס גם לצילום רוחבי לפי היעד.").font(.footnote).foregroundStyle(LensTheme.muted)
                Text("החזק את האייפון כפי שתצלם, קח נשימה ודבר בטבעיות. הגלילה במקטע הבדיקה היא בקצב קבוע.").font(.subheadline)
                Button("התחלת תרגול · עד 8 שניות") { model.start(travel: travel) }.buttonStyle(MainButtonStyle()).accessibilityIdentifier("start-feedback-capture")
                Button("הגדרות מודל ואימות וידאו") { settings = true }.accessibilityIdentifier("open-feedback-settings")
                Text("אפשר לקבל בדיקות מקומיות גם בלי מפתח API. ניתוח בינה דורש מודל וידאו וקול מאומת ואישור שליחה שלך.").font(.caption).foregroundStyle(LensTheme.muted)
            }
            if let clip = model.clip, model.phase == .review || model.phase == .result {
                VideoPlayer(player: player).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("feedback-video")
                Text("\(clip.duration.formatted(.number.precision(.fractionLength(1)))) שניות · \((Double(clip.byteCount) / 1_000_000).formatted(.number.precision(.fractionLength(1)))) MB לשליחה").font(.caption).foregroundStyle(LensTheme.muted)
                Text("הבדיקה המקומית").font(.title3.bold())
                targetPicker
                ForEach(model.findings) { finding in
                    VStack(alignment: .leading, spacing: 7) {
                        Label(finding.title, systemImage: "iphone").font(.headline)
                        Text(finding.detail).font(.subheadline).foregroundStyle(LensTheme.muted)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                }
                if let report = model.report {
                    Text("משוב הבינה · התרשמות ממקטע קצר").font(.title3.bold())
                    if !report.positive.isEmpty { Label(report.positive, systemImage: "checkmark.circle").foregroundStyle(LensTheme.accent) }
                    if report.positive.isEmpty && report.recommendations.isEmpty { Text("המודל לא הציע שינויים נוספים מהמקטע הזה.").font(.subheadline) }
                    ForEach(report.recommendations) { recommendation in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(recommendation.observation).font(.headline)
                            Text(recommendation.action)
                            Text(recommendation.limitation).font(.caption).foregroundStyle(LensTheme.muted)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    Text("אפשר לתקן ולצלם שוב לפי הבדיקה המקומית, או לבקש ניתוח נוסף מהמודל.").font(.footnote)
                    Button("ניתוח נוסף עם בינה") { player?.pause(); model.requestAnalysis() }.buttonStyle(MainButtonStyle()).accessibilityIdentifier("request-feedback-analysis")
                    Button("הגדרות מודל ואימות וידאו") { player?.pause(); settings = true }
                }
                Button("צילום מחדש") { player?.pause(); model.delete() }.buttonStyle(MainButtonStyle(secondary: true))
                Button("סיום עם הבדיקה המקומית") { player?.pause(); Task { await model.close(); dismiss() } }
                Button("מחיקת המקטע", role: .destructive) { player?.pause(); model.delete() }
                Text("המקטע והמשוב זמניים ויימחקו בסגירה. מחיקה מקומית אינה מוחקת מידע שכבר נשלח לספק.").font(.caption).foregroundStyle(LensTheme.muted)
            }
        }
    }
    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("איפה הסרטון יופיע?").font(.subheadline.bold())
            Picker("יעד הסרטון", selection: $model.target) { ForEach(FeedbackTarget.allCases, id: \.self) { Text($0.title).tag($0) } }
                .pickerStyle(.menu).accessibilityIdentifier("feedback-target")
        }
    }
    private func capture(layout: PromptLayout, width: CGFloat) -> some View {
        ZStack {
            CameraPreview(session: model.camera.session).ignoresSafeArea()
            VStack(spacing: 16) {
                Label("מקליטים מקטע בדיקה · \(min(8, Int(model.elapsed))) / 8", systemImage: "record.circle.fill").font(.headline).padding(12).background(.black.opacity(0.7), in: Capsule())
                if model.script.presentationMode == .talkingPoints, let point = model.currentPoint {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(point.stage.title).font(.caption).foregroundStyle(LensTheme.accent)
                        ScrollView { Text(point.text).font(.system(size: model.script.settings.fontSize, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 200)
                        HStack {
                            Button("הקודם") { model.movePoint(-1) }
                            Spacer(); Button("הבא") { model.movePoint(1) }
                        }
                    }.padding(18).frame(width: width).background(LensTheme.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    PromptOverlay(layout: layout, offset: model.playback.clock.offset, width: width, opacity: model.script.settings.backgroundOpacity)
                }
                Spacer(minLength: 12)
                Button(model.elapsed >= 6 ? "סיום ובדיקה מקומית" : "עוד רגע · לפחות 6 שניות") { model.stop() }.buttonStyle(MainButtonStyle()).disabled(model.elapsed < 6)
                Button("ביטול המקטע") { model.stop(discard: true) }.padding(12).background(.black.opacity(0.7), in: Capsule())
            }.padding(20)
        }
    }
}
