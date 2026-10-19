import SwiftUI
import AVKit
import Photos
import PrompterCore

struct TakesView: View {
    @Bindable var library: LibraryModel
    var scriptFilter: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: Take?
    @State private var recoveryMessage: String?
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var preparingShare = false
    @State private var shareBatch: TakeShareBatch?
    @State private var shareTask: Task<Void, Never>?
    private var groups: [TakeGroup] { library.takeGroups.filter { scriptFilter == nil || $0.scriptID == scriptFilter } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if !library.takesLoaded {
                        Text("רשימת הטייקים לא נטענה. הקבצים נשמרו ללא שינוי.")
                        Button("ניסיון נוסף") { library.reloadTakes() }
                    } else if groups.isEmpty {
                        ContentUnavailableView("עוד אין טייקים", systemImage: "film", description: Text("הסרטונים שתצלם יישמרו כאן, מחוברים לתסריט שלהם."))
                    }
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top) {
                                Image(systemName: "doc.text").foregroundStyle(LensTheme.accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(group.title).font(.headline)
                                    Text("\(group.takes.count) טייקים לתסריט").font(.caption).foregroundStyle(LensTheme.muted)
                                }
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 16).padding(.top, 18)
                            ScrollView(.horizontal) {
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(group.takes) { take in
                                        VStack(alignment: .leading, spacing: 8) {
                                            if selecting {
                                                Button { if !selected.insert(take.id).inserted { selected.remove(take.id) } } label: {
                                                    ZStack(alignment: .topTrailing) {
                                                        TakeThumbnail(url: library.disk.movieURL(for: take))
                                                        Image(systemName: selected.contains(take.id) ? "checkmark.circle.fill" : "circle")
                                                            .font(.title2).foregroundStyle(LensTheme.accent).padding(8).background(.black.opacity(0.5), in: Circle())
                                                    }
                                                }.buttonStyle(.plain).accessibilityLabel("בחירת " + take.label)
                                                    .accessibilityIdentifier("select-take-" + take.id.uuidString)
                                                    .accessibilityAddTraits(selected.contains(take.id) ? .isSelected : [])
                                            } else {
                                                NavigationLink { TakeDetailView(library: library, take: take) } label: {
                                                    VStack(alignment: .leading, spacing: 8) {
                                                        TakeThumbnail(url: library.disk.movieURL(for: take))
                                                        Text(take.label).font(.subheadline.bold())
                                                    }
                                                }.buttonStyle(.plain).accessibilityIdentifier("open-take-" + take.id.uuidString)
                                            }
                                            if selecting { Text(take.label).font(.subheadline.bold()) }
                                            Text(take.createdAt, format: .dateTime.day().month().hour().minute()).font(.caption2).foregroundStyle(LensTheme.muted)
                                            Text("\(statusLabel(take.status)) · \(LensTheme.time(take.duration))").font(.caption2).foregroundStyle(LensTheme.muted)
                                            if let rating = take.rating { Text(rating.title).font(.caption.bold()).foregroundStyle(LensTheme.accent) }
                                            if !selecting {
                                                Button(role: .destructive) { deleting = take } label: {
                                                    Label("מחיקה", systemImage: "trash").font(.caption).frame(minHeight: 44)
                                                }.buttonStyle(.plain).accessibilityLabel("מחיקת " + take.label)
                                            }
                                        }.frame(width: 150, alignment: .leading)
                                    }
                                }.padding(.horizontal, 16).padding(.bottom, 16)
                            }
                        }.background(LensTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                            .accessibilityElement(children: .contain).accessibilityIdentifier("take-group-" + group.id)
                    }
                    Text("הטייקים נשמרים במכשיר. אפשר לבחור כמה סרטונים ולשתף אותם יחד. מחיקת האפליקציה עלולה למחוק את הקבצים המקומיים.")
                        .font(.footnote).foregroundStyle(LensTheme.muted)
                }.padding(20)
            }.background(LensTheme.background).foregroundStyle(LensTheme.text)
                .navigationTitle("הטייקים שלי")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("סיום") { dismiss() } }
                    ToolbarItem(placement: .topBarLeading) {
                        Button(selecting ? "ביטול בחירה" : "בחירה") { selecting.toggle(); selected.removeAll() }
                            .accessibilityIdentifier("select-takes").disabled(preparingShare || groups.isEmpty)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if selecting {
                        Button { prepareSelectedShare() } label: {
                            Label(preparingShare ? "מכינים לשיתוף…" : "שיתוף \(selected.count) סרטונים", systemImage: "square.and.arrow.up")
                        }.buttonStyle(MainButtonStyle()).disabled(selected.isEmpty || preparingShare)
                            .accessibilityIdentifier("share-selected").padding().background(LensTheme.background)
                    }
                }
                .task { await recoverPending() }
                .onDisappear { shareTask?.cancel() }
                .onChange(of: library.takes) { _, takes in selected.formIntersection(Set(takes.map(\.id))) }
                .sheet(item: $shareBatch) { batch in
                    TakeShareSheet(batch: batch).onDisappear { Task { await library.releaseShare(batch) } }
                }
                .alert("למחוק את הטייק והסרטון?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("מחיקת טייק", role: .destructive) {
                        guard let deleting else { return }
                        if !library.deleteTake(deleting) { recoveryMessage = library.error }
                        self.deleting = nil
                    }
                    Button("ביטול", role: .cancel) { deleting = nil }
                }
        }.environment(\.layoutDirection, .rightToLeft).tint(LensTheme.accent).lensError($recoveryMessage)
    }
    private func prepareSelectedShare() {
        preparingShare = true
        let takes = groups.flatMap(\.takes).filter { selected.contains($0.id) }
        shareTask = Task {
            defer { preparingShare = false }
            do { shareBatch = try await library.prepareShare(takes) }
            catch is CancellationError { }
            catch { recoveryMessage = "לא ניתן להכין את כל הסרטונים שנבחרו. " + error.localizedDescription }
        }
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
    @State private var preparingShare = false
    @State private var shareBatch: TakeShareBatch?
    @State private var shareTask: Task<Void, Never>?
    private var currentTake: Take { library.takes.first(where: { $0.id == take.id }) ?? take }
    private var url: URL { library.disk.movieURL(for: take) }
    private var fileExists: Bool { FileManager.default.fileExists(atPath: url.path) }
    private var valid: Bool { take.status == .ready || take.status == .interrupted }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(take.scriptTitle).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                Text(take.label).font(.subheadline).foregroundStyle(LensTheme.muted).frame(maxWidth: .infinity, alignment: .leading)
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
                VStack(alignment: .leading, spacing: 10) {
                    Text(currentTake.rating.map { "דירוג: " + $0.title } ?? "איך יצא הטייק?").font(.subheadline.bold())
                    HStack(spacing: 8) {
                        ForEach(TakeRating.allCases, id: \.self) { rating in
                            Button {
                                if !library.rateTake(take, rating: rating) { error = library.error }
                            } label: {
                                Text(rating.title).font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 48)
                                    .background(currentTake.rating == rating ? LensTheme.accent : LensTheme.surface, in: Capsule())
                                    .foregroundStyle(currentTake.rating == rating ? LensTheme.background : LensTheme.text)
                            }.buttonStyle(.plain).accessibilityIdentifier("rating-" + rating.rawValue)
                                .accessibilityAddTraits(currentTake.rating == rating ? .isSelected : [])
                        }
                    }
                }.padding(.vertical, 8)
                if fileExists {
                    Button {
                        player?.pause(); preparingShare = true
                        shareTask = Task {
                            defer { preparingShare = false }
                            do { shareBatch = try await library.prepareShare([currentTake]) }
                            catch is CancellationError { }
                            catch { self.error = "לא ניתן להכין את הסרטון לשיתוף. " + error.localizedDescription }
                        }
                    } label: { Label(preparingShare ? "מכינים לשיתוף…" : "שיתוף הסרטון", systemImage: "square.and.arrow.up") }
                        .buttonStyle(MainButtonStyle(secondary: true)).disabled(preparingShare)
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
            .sheet(item: $shareBatch) { batch in
                TakeShareSheet(batch: batch).onDisappear { Task { await library.releaseShare(batch) } }
            }
            .onDisappear { shareTask?.cancel(); player?.pause(); player = nil }
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

private struct TakeThumbnail: View {
    let url: URL
    @State private var thumbnail: UIImage?
    var body: some View {
        ZStack {
            LensTheme.background
            if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
            else { Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(LensTheme.muted) }
        }.frame(width: 150, height: 100).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
            .task(id: url) {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 400, height: 400)
                if let image = try? await generator.image(at: .zero), !Task.isCancelled { thumbnail = UIImage(cgImage: image.image) }
            }.accessibilityHidden(true)
    }
}

private struct TakeShareSheet: View {
    let batch: TakeShareBatch
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ActivityShareView(urls: batch.urls)
                .navigationTitle(batch.urls.count == 1 ? "שיתוף סרטון" : "שיתוף \(batch.urls.count) סרטונים")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("סיום") { dismiss() }.accessibilityIdentifier("close-share") } }
        }.environment(\.layoutDirection, .rightToLeft)
    }
}

private struct ActivityShareView: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
