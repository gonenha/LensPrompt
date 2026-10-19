import SwiftUI
import AVKit
import Photos
import PrompterCore

struct TakesView: View {
    @Bindable var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: Take?
    @State private var recoveryMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if !library.takesLoaded {
                    Text("רשימת הטייקים לא נטענה. הקבצים נשמרו ללא שינוי.")
                    Button("ניסיון נוסף") { library.reloadTakes() }
                } else if library.takes.isEmpty {
                    ContentUnavailableView("עוד אין טייקים", systemImage: "film", description: Text("הסרטונים שתצלם יישמרו כאן גם לפני הייצוא לתמונות."))
                }
                ForEach(library.takes) { take in
                    HStack {
                        NavigationLink { TakeDetailView(library: library, take: take) } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(take.scriptTitle.isEmpty ? "טייק ללא כותרת" : take.scriptTitle).font(.headline)
                            Text(take.createdAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            Text("\(statusLabel(take.status)) · \(LensTheme.time(take.duration))").font(.caption).foregroundStyle(LensTheme.accent)
                        }.padding(.vertical, 6)
                    }
                        Button(role: .destructive) { deleting = take } label: {
                            Image(systemName: "trash").frame(width: 48, height: 48).contentShape(Rectangle())
                        }.buttonStyle(.borderless).accessibilityLabel("מחיקת הטייק " + take.scriptTitle)
                            .accessibilityIdentifier("delete-list-take-" + take.id.uuidString)
                    }.listRowBackground(LensTheme.surface)
                        .swipeActions { Button("מחיקה", role: .destructive) { deleting = take } }

                }
                Text("הטייקים נשמרים בתוך האפליקציה. כדי לשמור עותק נוסף, ייצא לתמונות או שתף למקבוק. מחיקת האפליקציה עלולה למחוק את הקבצים המקומיים.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.scrollContentBackground(.hidden).background(LensTheme.background).foregroundStyle(LensTheme.text)
                .navigationTitle("הטייקים שלי").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("סיום") { dismiss() } } }
                .task { await recoverPending() }
                .confirmationDialog("למחוק את הטייק והסרטון?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("מחיקת טייק", role: .destructive) {
                        guard let deleting else { return }
                        if !library.deleteTake(deleting) { recoveryMessage = library.error }
                        self.deleting = nil
                    }
                    Button("ביטול", role: .cancel) { deleting = nil }
                }
        }.environment(\.layoutDirection, .rightToLeft).tint(LensTheme.accent).lensError($recoveryMessage)
    }

    private func statusLabel(_ status: TakeStatus) -> String {
        switch status {
        case .ready: "נשמר במכשיר"
        case .pending: "ממתין לבדיקת הקובץ"
        case .interrupted: "צילום שנקטע"
        case .failed: "נדרשת בדיקת קובץ"
        }
    }
    private func recoverPending() async {
        library.reloadTakes()
        for take in library.takes where take.status == .pending {
            do {
                let asset = AVURLAsset(url: library.disk.movieURL(for: take))
                let playable = try await asset.load(.isPlayable)
                let duration = try await asset.load(.duration).seconds
                let tracks = try await asset.loadTracks(withMediaType: .video)
                if playable, duration.isFinite, duration > 0, !tracks.isEmpty {
                    try library.disk.finishTake(id: take.id, duration: duration, interrupted: true)
                } else { try library.disk.failTake(id: take.id) }
            } catch {
                do { try library.disk.failTake(id: take.id) } catch { recoveryMessage = error.localizedDescription }
            }
        }
        library.reloadTakes()
    }
}

struct TakeDetailView: View {
    let library: LibraryModel
    let take: Take
    var embedded = false
    var autoPlay = false
    var onDeleted: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDeletion = false
    @State private var loading = true
    @State private var player: AVPlayer?
    @State private var error: String?
    @State private var saved = false
    @State private var saving = false
    private var url: URL { library.disk.movieURL(for: take) }
    private var fileExists: Bool { FileManager.default.fileExists(atPath: url.path) }
    private var valid: Bool { take.status == .ready || take.status == .interrupted }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if valid, let player {
                    VideoPlayer(player: player).frame(height: embedded ? 260 : 420).accessibilityIdentifier("take-video").clipShape(RoundedRectangle(cornerRadius: 16))
                    Button {
                        player.seek(to: .zero); player.play()
                    } label: { Label("ניגון מהתחלה", systemImage: "play.fill") }
                        .buttonStyle(MainButtonStyle()).accessibilityIdentifier("play-take")
                } else if valid && fileExists && loading {
                    ProgressView("טוענים את הסרטון…").frame(height: 260)
                } else {
                    Label("לא ניתן להציג תצוגה מקדימה לטייק הזה.", systemImage: "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(.secondary).padding()
                }
                if fileExists {
                    ShareLink(item: url) { Label("שיתוף הסרטון", systemImage: "square.and.arrow.up") }.buttonStyle(MainButtonStyle(secondary: true))
                    if valid {
                        Button { Task { await saveToPhotos() } } label: {
                            Label(saving ? "שומרים…" : saved ? "נשמר בתמונות" : "שמירה לתמונות", systemImage: saved ? "checkmark" : "photo")
                        }.buttonStyle(MainButtonStyle()).disabled(saving || saved)
                    }
                } else { Text("קובץ הסרטון אינו זמין. לא נמחקו קבצים נוספים.").font(.footnote).foregroundStyle(.secondary) }
                Button(role: .destructive) { confirmingDeletion = true } label: { Label("מחיקת הטייק", systemImage: "trash") }
                    .frame(minHeight: 48).accessibilityIdentifier("delete-take")
                if !embedded { Text("הקובץ המקורי נשאר באפליקציה גם אחרי שיתוף או שמירה לתמונות.").font(.footnote).foregroundStyle(.secondary) }
            }.padding(embedded ? 4 : 24)
        }.background(LensTheme.background).foregroundStyle(LensTheme.text).navigationTitle(embedded ? "" : "צפייה בטייק").navigationBarTitleDisplayMode(.inline)
            .task {
                defer { loading = false }
                guard valid && fileExists else { return }
                do {
                    let asset = AVURLAsset(url: url)
                    guard try await asset.load(.isPlayable) else { throw MovieError.invalid }
                    let newPlayer = AVPlayer(playerItem: AVPlayerItem(asset: asset))
                    player = newPlayer
                    if autoPlay { newPlayer.play() }
                } catch { self.error = "לא ניתן לנגן את הסרטון. הקובץ נשמר במכשיר. " + error.localizedDescription }
            }
            .alert("למחוק את הטייק והסרטון?", isPresented: $confirmingDeletion) {
                Button("מחיקת טייק", role: .destructive) {
                    player?.pause()
                    if library.deleteTake(take) { onDeleted?(); dismiss() }
                    else { error = library.error }
                }
                Button("ביטול", role: .cancel) {}
            }
            .onDisappear { player?.pause(); player = nil }
            .lensError($error)
    }
    private func saveToPhotos() async {
        saving = true; defer { saving = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            error = "לא ניתנה הרשאה להוספה לתמונות. הסרטון עדיין במכשיר וניתן לשתף אותו. ניתן לשנות את ההרשאה בהגדרות."
            return
        }
        do {
            let movieURL = url
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: movieURL) }
            saved = true
        } catch { self.error = "השמירה לתמונות נכשלה. המקור נשאר באפליקציה. \(error.localizedDescription)" }
    }
}
