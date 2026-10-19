import SwiftUI
import AVFoundation
import PrompterCore

struct RecordingView: View {
    @Binding var script: Script
    @State private var model: RecordingModel
    @State private var layoutCache = PromptLayoutCache()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(library: LibraryModel, script: Binding<Script>, camera: CameraModel, practice: Bool) {
        _script = script; _model = State(initialValue: RecordingModel(library: library, camera: camera, script: script.wrappedValue, practice: practice))
    }
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * model.settings.widthFraction
            let layout = layoutCache.layout(text: model.isTalkingPoints ? "" : model.script.text, width: width - 32, fontSize: model.settings.fontSize)
            ZStack {
                LensTheme.background.ignoresSafeArea()
                if model.camera.previewAvailable { CameraPreview(session: model.camera.session).ignoresSafeArea() }
                else {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.rectangle").font(.system(size: 75, weight: .ultraLight))
                        Text("תרגול ללא הקלטה").font(.caption)
                    }.foregroundStyle(.white.opacity(0.25))
                }
                VStack(spacing: 20) {
                    HStack {
                        Button { model.stop() } label: { Image(systemName: "xmark").padding(10).background(.white.opacity(0.12), in: Circle()) }
                            .accessibilityLabel("יציאה מהצילום")
                        Spacer()
                        Text(model.practice ? "תרגול בלבד" : phaseLabel).font(.caption.weight(.medium))
                        Spacer()
                        HStack(spacing: 5) {
                            Circle().fill(model.practice ? LensTheme.accent : LensTheme.recording).frame(width: 7, height: 7)
                            Text(LensTheme.time(model.playback.clock.elapsed)).monospacedDigit().accessibilityIdentifier("take-timer")
                        }.font(.caption).padding(9).background(.black.opacity(0.35), in: Capsule()).environment(\.layoutDirection, .leftToRight)
                    }.padding(.horizontal, 20)
                    if model.isTalkingPoints {
                        talkingPointCard(width: width, height: min(340, geometry.size.height * 0.45))
                    } else {
                    PromptOverlay(layout: layout,
                                  offset: model.playback.currentWord.map { Double(layout.wordLineY[$0]) } ?? model.playback.clock.offset,
                                  width: width, opacity: model.settings.backgroundOpacity,
                                  currentWord: model.playback.currentWord,
                                  onSelect: model.settings.followsVoice ? { model.playback.selectWord($0) } : nil)
                    if model.settings.followsVoice && model.playback.isRunning {
                        Text(model.playback.clock.isPaused ? "המלל מושהה" : model.playback.soundActive ? "יש קול · מיקום משוער" : "ממתין לקול · מיקום משוער")
                            .font(.caption).padding(8).background(.black.opacity(0.5), in: Capsule()).accessibilityIdentifier("voice-status")
                    }
                    if let notice = model.voiceNotice { Text(notice).font(.caption) }
                    if model.playback.clock.reachedEnd && model.playback.isRunning {
                        Text(model.practice ? "סוף המלל" : "סוף המלל · ההקלטה נמשכת").font(.caption).padding(8).background(.black.opacity(0.5), in: Capsule())
                    }
                    }
                    Spacer(minLength: 20)
                    controls
                }.padding(.vertical, 12)
                if model.lifecycle.phase == .countdown && model.countdownRemaining > 0 {
                    Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                    VStack(spacing: 22) {
                        Text("\(model.countdownRemaining)").font(.system(size: 110, weight: .bold, design: .rounded)).contentTransition(.numericText())
                        Text("רגע לנשום. עוד מעט מתחילים.").font(.subheadline)
                        Button("ביטול וחזרה") { model.stop() }.buttonStyle(.bordered).tint(.white).accessibilityIdentifier("cancel-countdown")
                    }
                }
                if model.finished { result }
            }.foregroundStyle(LensTheme.text)
                .task { model.begin(travel: layout.lastLineY) }
        }
        .interactiveDismissDisabled()
        .onChange(of: model.shouldDismiss) { _, value in if value { dismiss() } }
        .onChange(of: model.settings) { _, value in script.settings = value }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.stop(interrupted: true) } }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: model.camera.session)) { _ in model.stop(interrupted: true) }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification, object: model.camera.session)) { _ in model.stop(interrupted: true) }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               type == AVAudioSession.InterruptionType.began.rawValue { model.stop(interrupted: true) }
        }
        .onDisappear { model.leave() }
        .lensError($model.error)
    }
    private var phaseLabel: String {
        switch model.lifecycle.phase {
        case .starting: "מתחילים צילום…"
        case .finishing: "שומרים טייק…"
        default: "מצלמים"
        }
    }
    private func talkingPointCard(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let point = model.currentPoint {
                HStack(spacing: 6) {
                    ForEach(model.talkingPoints.indices, id: \.self) { index in
                        Capsule().fill(index == model.pointIndex ? LensTheme.accent : LensTheme.divider).frame(height: 5)
                    }
                }.accessibilityHidden(true)
                HStack {
                    Text(point.stage.title).font(.subheadline.weight(.semibold)).foregroundStyle(LensTheme.accent)
                        .accessibilityIdentifier("point-stage")
                    Spacer()
                    Text("\(model.pointIndex + 1) מתוך \(model.talkingPoints.count)").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                ScrollView {
                    Text(point.text).font(.system(size: model.settings.fontSize, weight: .semibold))
                        .lineSpacing(8).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("point-sentence")
                }.id(point.stage)
                Text(model.pointIndex == model.talkingPoints.count - 1 ? (model.practice ? "הנקודה האחרונה" : "הנקודה האחרונה · ההקלטה נמשכת") : "מוכן להמשיך? לחץ על הבא")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }.padding(20).frame(width: width, height: height, alignment: .topLeading)
            .background(LensTheme.background.opacity(model.settings.backgroundOpacity), in: RoundedRectangle(cornerRadius: 16))
    }
    private var controls: some View {
        VStack(spacing: 16) {
            if !model.isTalkingPoints {
            HStack {
                Text("קצב הגלילה")
                Spacer()
                let effective = model.settings.pace == .duration ? Double(model.script.wordCount) / model.settings.duration(wordCount: model.script.wordCount) * 60 : model.settings.wordsPerMinute
                Text("\(Int(effective)) מילים/דקה")
            }.font(.caption)
            Slider(value: Binding(get: { min(220, max(50, model.settings.pace == .duration ? Double(model.script.wordCount) / model.settings.duration(wordCount: model.script.wordCount) * 60 : model.settings.wordsPerMinute)) }, set: { model.changeSpeed($0) }), in: 50...220, step: 5)
                .tint(LensTheme.accent).environment(\.layoutDirection, .leftToRight).accessibilityLabel("מהירות בזמן צילום")
            }
            HStack(alignment: .center, spacing: 12) {
                if model.isTalkingPoints {
                    control("chevron.right", title: "הקודם", id: "previous-point") { model.movePoint(by: -1) }
                        .disabled(model.pointIndex == 0).opacity(model.pointIndex == 0 ? 0.35 : 1)
                    control("chevron.left", title: "הבא", id: "next-point", prominent: true) { model.movePoint(by: 1) }
                        .disabled(model.pointIndex >= model.talkingPoints.count - 1)
                        .opacity(model.pointIndex >= model.talkingPoints.count - 1 ? 0.35 : 1)
                } else {
                    control("arrow.counterclockwise", title: "להתחלה", id: "reset-text") { model.playback.resetText() }
                    control(model.playback.clock.isPaused ? "play.fill" : "pause.fill", title: model.playback.clock.isPaused ? "המשך גלילה" : "השהיית מלל", id: "pause-text", prominent: true) { model.playback.pauseText() }
                }
                Spacer(minLength: 4)
                Button { model.stop() } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "stop.fill").font(.system(size: 23))
                            .foregroundStyle(LensTheme.background).frame(width: 62, height: 62)
                            .background(LensTheme.recording, in: Circle())
                        Text("סיום הטייק").font(.caption).foregroundStyle(LensTheme.recording)
                    }.frame(minWidth: 70, minHeight: 88)
                }.accessibilityLabel("סיום הטייק").accessibilityIdentifier("finish-take")
            }.disabled(model.lifecycle.phase == .starting || model.lifecycle.phase == .finishing)
        }.padding(18).background(LensTheme.background.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(LensTheme.divider))
            .padding(.horizontal, 16)
    }
    private func control(_ symbol: String, title: String, id: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 23, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(prominent ? LensTheme.background : LensTheme.text)
                    .background(prominent ? LensTheme.accent : LensTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                Text(title).font(.caption).lineLimit(2).multilineTextAlignment(.center)
            }.frame(maxWidth: prominent ? 110 : 84, minHeight: 88)
        }.accessibilityLabel(title).accessibilityIdentifier(id)
    }
    private var result: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: model.error == nil ? "checkmark.circle" : "exclamationmark.triangle").font(.system(size: 43, weight: .light)).foregroundStyle(LensTheme.accent)
            Text(model.practice ? "התרגול הסתיים" : "הטייק הסתיים").font(.title.bold())
            Text("משך \(LensTheme.time(model.playback.clock.elapsed))").font(.subheadline).foregroundStyle(.secondary)
            if let message = model.message { Text(message).font(.subheadline).multilineTextAlignment(.center) }
            if !model.practice, let take = model.take {
                NavigationStack { TakeDetailView(library: model.library, take: take, embedded: true) }.frame(maxHeight: 320)
            }
            Spacer()
            Button("טייק נוסף") {
                model.leave()
                model = RecordingModel(library: model.library, camera: model.camera, script: script, practice: model.practice)
                let width = UIScreen.main.bounds.width * model.settings.widthFraction - 32
                model.begin(travel: layoutCache.layout(text: model.isTalkingPoints ? "" : script.text, width: width, fontSize: model.settings.fontSize).lastLineY)
            }.buttonStyle(MainButtonStyle())
            Button("חזרה להכנה") { dismiss() }.buttonStyle(MainButtonStyle(secondary: true)).accessibilityIdentifier("back-setup")
        }.padding(24).foregroundStyle(LensTheme.text).frame(maxWidth: .infinity, maxHeight: .infinity).background(LensTheme.background).ignoresSafeArea(edges: .bottom)
    }
}
